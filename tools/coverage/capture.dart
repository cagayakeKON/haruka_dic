import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:pool/pool.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Raw evidence with explicit suite drains; no Dart line inference.
class OwnedCoverage {
  OwnedCoverage(this.connection, this.output, this.origin);
  final WipConnection connection;
  final Directory output;
  final Uri origin;
  final Map<String, Map<String, dynamic>> scripts = {};
  final List<Map<String, dynamic>> deltas = [];
  final List<Map<String, dynamic>> trace = [];
  final List<Future<void>> sourceReads = [];
  final List<String> errors = [];
  final Pool mapReads = Pool(8);
  final HttpClient mapClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 8;
  Future<void> pending = Future.value();
  late final StreamSubscription<ScriptParsedEvent> subscription;
  final List<StreamSubscription<dynamic>> diagnosticSubscriptions = [];
  int diagnosticCount = 0;
  int ignoredConsole = 0;
  final Stopwatch clock = Stopwatch()..start();

  void event(String action, [int? suite]) {
    final row = {'action': action, 'suite_id': suite, 'elapsed_us': clock.elapsedMicroseconds};
    trace.add(row);
    File('${output.path}/trace.jsonl').writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append, flush: true);
  }

  static Future<OwnedCoverage> attach(ChromeConnection browser, Uri url) async {
    final destination = Platform.environment['HARUKA_WEB_COVERAGE_RAW'];
    if (destination == null) throw StateError('Explicit raw output required');
    final tabs = await browser.getTabs();
    final tab = tabs.singleWhere((tab) => tab.url == url.toString());
    final connection = await tab.connect();
    final sessionId = DateTime.now().toUtc().microsecondsSinceEpoch;
    final collector = OwnedCoverage(connection,
      Directory('$destination/session-$sessionId')..createSync(recursive: true), url);
    Directory('${collector.output.path}/blobs').createSync();
    collector.subscription = connection.debugger.onScriptParsed.listen((event) {
      final script = event.script;
      if (script.url.isEmpty) return;
      collector.scripts[script.scriptId] = Map<String, dynamic>.from(script.json);
      collector.queueScriptRead(script.scriptId);
    });
    collector.diagnosticSubscriptions.add(connection.runtime.onConsoleAPICalled.listen((event) {
      // Only these fixed test-state markers may leave the browser. Never
      // persist arbitrary arguments, values, descriptions, or message text.
      collector.testMarker(event.json);
      collector.ignoredConsole++;
    }));
    collector.diagnosticSubscriptions.add(connection.runtime.onExceptionThrown.listen((event) {
      collector.diagnostic(event.exceptionDetails.json);
    }));
    await connection.sendCommand('Runtime.enable');
    await connection.sendCommand('Profiler.enable');
    await connection.sendCommand('Profiler.startPreciseCoverage', {'detailed': true, 'callCount': true});
    collector.event('profiler-enabled');
    await connection.debugger.enable();
    return collector;
  }

  void testMarker(Map<String, dynamic> event) {
    const markers = {
      'before-tap', 'after-tap', 'request-started', 'response-released',
      'auth-anonymous', 'auth-authenticated', 'login-visible', 'login-hidden',
      'settings-visible', 'settings-hidden', 'dialog-visible', 'dialog-hidden',
      'route-login', 'route-security', 'route-other', 'settle-start', 'settle-end',
    };
    final arguments = event['args'];
    if (arguments is! List || arguments.length != 1) return;
    final argument = arguments.single;
    if (argument is! Map || argument['type'] != 'string') return;
    final value = argument['value'];
    if (value is! String) return;
    const prefix = 'HARUKA_AUTH_TEST_DIAG:';
    if (!value.startsWith(prefix)) return;
    final marker = value.substring(prefix.length);
    if (!markers.contains(marker)) return;
    File('${output.path}/test-markers.jsonl').writeAsStringSync('${jsonEncode({
      'type': 'fixed-test-state', 'marker': marker,
      'elapsed_us': clock.elapsedMicroseconds,
    })}\n', mode: FileMode.append, flush: true);
  }

  void diagnostic(Map<String, dynamic> details) {
    if (diagnosticCount++ >= 100) return;
    final exception = details['exception'];
    final name = exception is Map ? exception['className'] : null;
    const allowed = {'Error', 'TypeError', 'RangeError', 'ReferenceError', 'SyntaxError', 'StateError', 'AssertionError'};
    final frames = <Map<String, Object?>>[];
    final stack = details['stackTrace'];
    final calls = stack is Map ? stack['callFrames'] : null;
    if (calls is List) {
      for (final frame in calls.take(30)) {
        if (frame is! Map) continue;
        final uri = Uri.tryParse(frame['url'] is String ? frame['url'] as String : '');
        if (uri == null || !sameOrigin(uri) || !(uri.path.endsWith('.js') || uri.path.endsWith('.dart')) || !RegExp(r'^/[A-Za-z0-9_./-]+$').hasMatch(uri.path)) continue;
        // Function names and URL queries can contain input: omit them.
        frames.add({'path': uri.path, 'line': frame['lineNumber'] is int ? frame['lineNumber'] : null,
          'column': frame['columnNumber'] is int ? frame['columnNumber'] : null});
      }
    }
    File('${output.path}/diagnostics.jsonl').writeAsStringSync('${jsonEncode({
      'type': 'runtime-exception', 'exception_type': allowed.contains(name) ? name : 'unknown-redacted',
      'elapsed_us': clock.elapsedMicroseconds, 'frames': frames,
      'message_policy': 'all-values-text-descriptions-omitted',
    })}\n', mode: FileMode.append, flush: true);
  }

  bool sameOrigin(Uri uri) => uri.scheme == origin.scheme &&
    uri.host == origin.host && uri.port == origin.port;

  bool projectUri(Uri uri) => uri.path.startsWith('/packages/haruka/') ||
    (uri.scheme == 'package' && uri.path.startsWith('haruka/'));

  Future<String> blob(String content) async {
    final bytes = utf8.encode(content);
    final hash = sha256.convert(bytes).toString();
    final target = File('${output.path}/blobs/$hash');
    if (!target.existsSync()) await target.writeAsBytes(bytes);
    return hash;
  }

  void queueScriptRead(String id) {
    // Only active reads have deadlines; time waiting for a slot is not a
    // missing-map failure. Keep the same-origin maps, including dependencies.
    sourceReads.add(mapReads.withResource(() async {
      try {
        await readScript(id).timeout(const Duration(seconds: 20));
      } catch (error) {
        errors.add('$id: bounded-map-read: $error');
      }
    }));
  }

  Future<void> readScript(String id) async {
    final entry = scripts[id]!;
    try {
      final scriptUri = Uri.parse(entry['url'] as String);
      final mapUrl = entry['sourceMapURL'] as String?;
      if (mapUrl == null || mapUrl.isEmpty) {
        entry['classification'] = 'unmapped-javascript';
        if (projectUri(scriptUri) || scriptUri.path.contains('/test/support/')) {
          throw StateError('Project script has no source map');
        }
        return;
      }
      final mapUri = scriptUri.resolve(mapUrl);
      String content;
      if (mapUri.scheme == 'data') {
        content = utf8.decode(mapUri.data!.contentAsBytes());
      } else {
        if (!sameOrigin(mapUri)) throw StateError('External map rejected');
        final request = await mapClient.getUrl(mapUri);
        final response = await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) throw StateError('Missing map ${response.statusCode}');
        content = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 15));
      }
      Map<String, dynamic> map;
      try {
        map = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        if (projectUri(scriptUri) || scriptUri.path.endsWith('/support/coverage_semantics_probe.dart.lib.js')) rethrow;
        entry['classification'] = 'nonproject-invalid-map-response';
        entry['map_sha256'] = await blob(content);
        return;
      }
      if (map['version'] != 3 || map['sections'] != null || map['sources'] is! List || map['mappings'] is! String) {
        throw StateError('Unsupported source map');
      }
      final sources = (map['sources'] as List).cast<String>();
      entry['resolved_sources'] = sources.map((source) => scriptUri.resolve(source).toString()).toList();
      final project = sources.any((source) => projectUri(scriptUri.resolve(source)) || scriptUri.resolve(source).path.endsWith('/support/coverage_semantics_probe.dart'));
      entry['classification'] = project ? 'project-or-explicit-probe' : 'sdk-or-dependency-or-test';
      if (!project && projectUri(scriptUri)) {
        final relative = scriptUri.path.substring('/packages/haruka/'.length).replaceFirst(RegExp(r'\.lib\.js$'), '');
        final root = Directory.current.parent;
        final key = 'frontend/lib/$relative';
        final manifest = jsonDecode(File('${root.path}/scripts/quality/coverage_manifest.json').readAsStringSync()) as Map<String, dynamic>;
        final classified = (manifest['files'] as Map<String, dynamic>)[key] as Map<String, dynamic>?;
        final file = File('${root.path}/$key');
        if (classified?['kind'] != 'declaration' || !file.existsSync()) throw StateError('Unmapped executable project module');
        final normalized = file.resolveSymbolicLinksSync().replaceAll('\\', '/');
        if (!normalized.startsWith('${root.path.replaceAll('\\', '/')}/frontend/lib/')) throw StateError('Declaration path escaped');
        final text = file.readAsStringSync().replaceAll(RegExp(r'//[^\n]*|/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'\b(?:export|import|library|part)\s+[^;]+;'), '');
        if (text.trim().isNotEmpty || sources.isNotEmpty) throw StateError('Executable declaration exception rejected');
        entry['classification'] = 'verified-directive-only-module';
        entry['declaration_source'] = key;
        entry['declaration_sha256'] = sha256.convert(file.readAsBytesSync()).toString();
      }
      entry['map_sha256'] = await blob(content);
      if (project) entry['source_sha256'] = await blob(await connection.debugger.getScriptSource(id).timeout(const Duration(seconds: 15)));
    } catch (error) {
      errors.add('$id: $error');
      entry['classification'] = 'capture-error';
    }
  }

  Future<void> drainReads() async {
    var drained = 0;
    while (drained < sourceReads.length) {
      final current = List<Future<void>>.from(sourceReads.skip(drained));
      drained = sourceReads.length;
      await Future.wait(current);
    }
    if (errors.isNotEmpty) throw StateError('Coverage capture failed: ${errors.length} errors');
  }

  Future<void> capture([int? suite]) {
    pending = pending.then((_) async {
      event('capture-start', suite);
      try {
        final response = await connection.sendCommand('Profiler.takePreciseCoverage').timeout(const Duration(seconds: 30));
        deltas.add({'suite_id': suite, 'response': response.result});
        await drainReads();
        event('capture-complete', suite);
      } catch (error) {
        errors.add('capture: $error');
        await persist();
        rethrow;
      }
    });
    return pending;
  }

  Future<void> persist() async {
    await File('${output.path}/raw.json').writeAsString(jsonEncode({
      'schema_version': 2, 'status': 'diagnostic-raw-only',
      'scripts': scripts, 'deltas': deltas, 'trace': trace, 'errors': errors,
    }));
  }

  Future<void> close() async {
    try {
      await pending;
      await capture();
      await drainReads();
      event('drained-before-browser-close');
      await persist();
    } catch (_) {
      // A failed pending capture must not start another profiler request.
      await persist();
      rethrow;
    } finally {
      try {
        for (final diagnostic in diagnosticSubscriptions) { await diagnostic.cancel().timeout(const Duration(seconds: 5)); }
        await File('${output.path}/diagnostic-counts.json').writeAsString(jsonEncode({'ignored_console': ignoredConsole, 'exception_events': diagnosticCount}));
      } finally {
        try {
          await subscription.cancel().timeout(const Duration(seconds: 5));
        } finally {
          mapClient.close(force: true);
          try {
            await mapReads.close().timeout(const Duration(seconds: 5));
          } finally {
            await connection.close().timeout(const Duration(seconds: 10));
          }
        }
      }
    }
  }
}

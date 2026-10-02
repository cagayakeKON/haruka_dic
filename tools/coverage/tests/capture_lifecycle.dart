import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';
import '../capture.dart';

class FakeConnection implements WipConnection {
  int requests = 0;
  bool closed = false;
  bool fail = false;
  @override
  Future<WipResponse> sendCommand(String method, [Map<String, dynamic>? params]) async {
    requests++;
    if (fail) throw StateError('injected CDP failure');
    return WipResponse({'id': requests, 'result': {'result': <Object>[]}});
  }
  @override
  Future<void> close() async { closed = true; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void require(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  final results = <Map<String, Object>>[];
  for (final failure in [false, true]) {
    final directory = await Directory.systemTemp.createTemp('haruka-cdp-test-');
    final connection = FakeConnection()..fail = failure;
    final collector = OwnedCoverage(connection, directory, Uri.parse('http://localhost:1234'));
    collector.subscription = const Stream<ScriptParsedEvent>.empty().listen((_) {});
    try {
      try { await collector.capture(1); } catch (_) { if (!failure) rethrow; }
      if (!failure) {
        require(!File('${directory.path}/raw.json').existsSync(), 'suite must not encode cumulative raw');
        await collector.capture(2);
        require(connection.requests == 2, 'both suite deltas captured');
      }
      try { await collector.close(); } catch (_) { if (!failure) rethrow; }
      require(connection.closed, 'CDP closed on success or failed pending');
      require(connection.requests == (failure ? 1 : 3), 'failed pending must not send new profiler request');
      final raw = jsonDecode(await File('${directory.path}/raw.json').readAsString()) as Map<String, dynamic>;
      require((raw['deltas'] as List).length == (failure ? 0 : 3), 'all genuine deltas retained');
      require((raw['errors'] as List).isEmpty == !failure, 'failure retained');
      results.add({'case': failure ? 'failed_pending_closes_without_recall' : 'successful_suites_persist_once_all_deltas', 'status': 'passed'});
    } finally { await directory.delete(recursive: true); }
  }
  final directory = await Directory.systemTemp.createTemp('haruka-map-pool-test-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var active = 0;
  var maximum = 0;
  var served = 0;
  server.listen((request) async {
    active++;
    if (active > maximum) maximum = active;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'version': 3, 'sources': <String>[], 'mappings': ''}));
    await request.response.close();
    active--;
    served++;
  });
  final origin = Uri.parse('http://127.0.0.1:${server.port}');
  final connection = FakeConnection();
  final collector = OwnedCoverage(connection, directory, origin);
  collector.subscription = const Stream<ScriptParsedEvent>.empty().listen((_) {});
  Directory('${directory.path}/blobs').createSync();
  try {
    for (var i = 0; i < 24; i++) {
      collector.scripts['$i'] = {'url': '$origin/packages/dependency/$i.dart.lib.js', 'sourceMapURL': '$i.dart.lib.js.map'};
      collector.queueScriptRead('$i');
    }
    await collector.drainReads();
    require(maximum <= 8 && maximum > 1, 'active map reads bounded');
    require(served == 24 && collector.errors.isEmpty, 'all queued same-origin dependency maps retained');
    await collector.close();
    results.add({'case': 'same_origin_dependency_maps_all_retained_bounded_eight_active_reads', 'status': 'passed'});
  } finally {
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
  stdout.writeln(jsonEncode({'tests': results.length, 'failed': 0, 'cases': results, 'network': 'fake WipConnection, no browser'}));
}

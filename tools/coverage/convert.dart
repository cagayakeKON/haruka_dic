import 'dart:convert';
import 'dart:io';
import 'package:coverage/coverage.dart';
import 'package:crypto/crypto.dart';
import 'package:source_maps/parser.dart' as source_maps;

Future<void> main(List<String> args) async {
  if (args.length != 4) throw ArgumentError('Required: RAW FREEZE ROOT FRESH_OUTPUT');
  final root = Directory(args[2]).absolute;
  final input = File(args[0]).absolute;
  final freezeFile = File(args[1]).absolute;
  final destination = Directory(args[3]).absolute;
  if (destination.existsSync()) throw StateError('Output already exists');
  final raw = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
  if ((raw['errors'] as List).isNotEmpty) throw StateError('Capture errors');
  final scripts = raw['scripts'] as Map<String, dynamic>;
  final freeze = jsonDecode(await freezeFile.readAsString()) as Map<String, dynamic>;
  final rawFiles = freeze['raw_files'] as Map<String, dynamic>;
  final rawHash = sha256.convert(input.readAsBytesSync()).toString();
  if (rawFiles[input.uri.toString()] != rawHash) throw StateError('Raw/freeze identity mismatch');
  final converterHash = sha256.convert(File.fromUri(Platform.script).readAsBytesSync()).toString();
  final helperHash = sha256.convert(File.fromUri(Platform.script.resolve('capture.dart')).readAsBytesSync()).toString();
  if (freeze['converter_sha256'] != converterHash || freeze['helper_sha256'] != helperHash) throw StateError('Collector/converter identity mismatch');
  if (freeze['restore_status'] != 'original-bytes-restored') throw StateError('SDK restore not verified');
  if (freeze['source_unchanged'] != true || freeze['tool_source_unchanged'] != true || freeze['native_exit_code'] != 0) throw StateError('Invalid native/source freeze');
  final counts = freeze['native_counts'];
  if (counts is! Map || counts['tests'] is! int || counts['passed'] is! int ||
      counts['failed'] != 0 || counts['skipped'] != 0 ||
      counts['passed'] <= 0 || counts['tests'] != counts['passed']) {
    throw StateError('Incomplete or skipped native tests');
  }
  final before = freeze['source_before'] as Map<String, dynamic>;
  final combined = <String, HitMap>{};
  final identities = <String, String>{};
  final resolvedCache = <String, Uri>{};
  final resolver = await Resolver.create();
  String readBlob(String hash) {
    final bytes = File('${input.parent.path}/blobs/$hash').readAsBytesSync();
    if (sha256.convert(bytes).toString() != hash) throw StateError('Blob identity mismatch');
    return utf8.decode(bytes);
  }
  Uri? candidateUri(String source, String id) {
    final script = scripts[id] as Map<String, dynamic>;
    var uri = Uri.parse(source);
    if (!uri.hasScheme) uri = Uri.parse(script['url'] as String).resolve(source);
    String? relative;
    const prefix = '/packages/haruka/';
    if (uri.path.startsWith(prefix)) relative = 'frontend/lib/${uri.path.substring(prefix.length)}';
    if (uri.scheme == 'package' && uri.path.startsWith('haruka/')) relative = 'frontend/lib/${uri.path.substring(7)}';
    if (uri.path.endsWith('/support/coverage_semantics_probe.dart')) relative = 'frontend/test/support/coverage_semantics_probe.dart';
    if (relative == null) return null;
    final cached = resolvedCache[relative];
    if (cached != null) return cached;
    final candidate = File('${root.path}/$relative').absolute;
    final normalized = candidate.resolveSymbolicLinksSync().replaceAll('\\', '/');
    if (!normalized.startsWith('${root.path.replaceAll('\\', '/')}/frontend/') || !before.containsKey(relative)) {
      throw StateError('Unfrozen or escaped source');
    }
    final hash = sha256.convert(candidate.readAsBytesSync()).toString();
    if (hash != before[relative]) throw StateError('Current source differs from compiler freeze');
    identities[relative] = hash;
    return resolvedCache[relative] = candidate.uri;
  }
  var entries = 0;
  final deltaFacts = <Map<String, dynamic>>[];
  for (final delta in raw['deltas'] as List) {
    final response = delta['response'] as Map<String, dynamic>;
    final allRows = (response['result'] as List).cast<Map<String, dynamic>>();
    final rows = <Map<String, dynamic>>[];
    final expectedDeltaSources = <String>{};
    for (final row in allRows) {
      final id = row['scriptId'] as String;
      final script = scripts[id] as Map<String, dynamic>?;
      if (script == null) throw StateError('Coverage script missing inventory');
      if (script['classification'] != 'project-or-explicit-probe') continue;
      if (script['source_sha256'] is! String || script['map_sha256'] is! String) throw StateError('Incomplete project script');
      final map = jsonDecode(readBlob(script['map_sha256'] as String)) as Map<String, dynamic>;
      if (map['version'] != 3 || map['sections'] != null || map['mappings'] is! String || map['sources'] is! List) throw StateError('Invalid project map');
      if (!(map['sources'] as List).cast<String>().any((source) => candidateUri(source, id) != null)) throw StateError('Project map missing frozen sources');
      // The official coverage parser silently skips FormatException/ArgumentError.
      // Validate every map ourselves so one malformed suite cannot hide behind another.
      final parsedMap = source_maps.parse(readBlob(script['map_sha256'] as String));
      if (parsedMap is! source_maps.SingleMapping) throw StateError('Indexed mapping unsupported');
      final mappedProjectSources = <String>{};
      for (final line in parsedMap.lines) {
        for (final point in line.entries) {
          final sourceId = point.sourceUrlId;
          if (sourceId == null) continue;
          final candidate = candidateUri(parsedMap.urls[sourceId], id);
          if (candidate != null) mappedProjectSources.add(candidate.toString());
        }
      }
      if (mappedProjectSources.isEmpty) throw StateError('Project map has no project positions');
      expectedDeltaSources.addAll(mappedProjectSources);
      rows.add(row);
    }
    entries += rows.length;
    final converted = await parseChromeCoverage(rows,
      (id) async => readBlob(scripts[id]['source_sha256'] as String),
      (id) async => readBlob(scripts[id]['map_sha256'] as String),
      (source, id) async => candidateUri(source, id));
    final parsed = await HitMap.parseJson((converted['coverage'] as List).cast<Map<String, dynamic>>(), checkIgnoredLines: false);
    if (expectedDeltaSources.difference(parsed.keys.toSet()).isNotEmpty) throw StateError('Official parser omitted a mapped delta source');
    final probeEntries = parsed.entries.where((entry) => entry.key.endsWith('/test/support/coverage_semantics_probe.dart')).toList();
    deltaFacts.add({'suite_id': delta['suite_id'], 'probe_line_hits': probeEntries.isEmpty ? null : probeEntries.single.value.lineHits.map((line, count) => MapEntry(line.toString(), count))});
    combined.merge(parsed);
  }
  for (final entry in identities.entries) {
    if (sha256.convert(File('${root.path}/${entry.key}').readAsBytesSync()).toString() != entry.value) throw StateError('Source changed during conversion');
  }
  if (destination.existsSync()) throw StateError('Output already exists');
  destination.createSync();
  final output = File('${destination.path}/full.lcov');
  await output.writeAsString(combined.formatLcov(resolver, basePath: '${root.path}/frontend'));
  final business = Map<String, HitMap>.fromEntries(combined.entries.where((entry) => !entry.key.endsWith('/test/support/coverage_semantics_probe.dart')));
  final businessOutput = File('${destination.path}/business.lcov');
  await businessOutput.writeAsString(business.formatLcov(resolver, basePath: '${root.path}/frontend'));
  final probe = combined.entries.where((entry) => entry.key.endsWith('/test/support/coverage_semantics_probe.dart')).toList();
  final facts = {
    'status': 'converted-not-coverage-gate', 'converted_entries': entries,
    'reported_sources': combined.length, 'source_hashes': identities,
    'probe_line_hits': probe.isEmpty ? null : probe.single.value.lineHits.map((line, count) => MapEntry(line.toString(), count)),
    'per_delta_probe_hits': deltaFacts,
    'business_sources': business.length,
    'converter_sha256': sha256.convert(File.fromUri(Platform.script).readAsBytesSync()).toString(),
    'lcov_sha256': sha256.convert(output.readAsBytesSync()).toString(),
    'business_lcov_sha256': sha256.convert(businessOutput.readAsBytesSync()).toString(),
    'raw_sha256': rawHash, 'freeze_sha256': sha256.convert(freezeFile.readAsBytesSync()).toString(),
    'helper_sha256': helperHash,
    'filtered_sources': probe.map((entry) => entry.key).toList(),
  };
  await File('${destination.path}/conversion-result.json').writeAsString(const JsonEncoder.withIndent('  ').convert(facts));
  stdout.writeln(jsonEncode({'sources': combined.length, 'probe_line_hits': facts['probe_line_hits'], 'entries': entries}));
}

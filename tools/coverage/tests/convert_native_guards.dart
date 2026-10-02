import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('SDK tools package config required');
  final base = await Directory.systemTemp.createTemp('haruka-convert-native-');
  final converter = File.fromUri(Platform.script.resolve('../convert.dart'));
  final helper = File.fromUri(Platform.script.resolve('../capture.dart'));
  final results = <Map<String, Object>>[];
  try {
    for (final skipped in [0, 1]) {
      final raw = File('${base.path}/raw-$skipped.json');
      await raw.writeAsString(jsonEncode({'errors': <Object>[], 'scripts': <String, Object>{}, 'deltas': <Object>[]}));
      final freeze = File('${base.path}/freeze-$skipped.json');
      await freeze.writeAsString(jsonEncode({
        'raw_files': {raw.uri.toString(): sha256.convert(raw.readAsBytesSync()).toString()},
        'converter_sha256': sha256.convert(converter.readAsBytesSync()).toString(),
        'helper_sha256': sha256.convert(helper.readAsBytesSync()).toString(),
        'restore_status': 'original-bytes-restored', 'source_unchanged': true,
        'tool_source_unchanged': true, 'native_exit_code': 0, 'source_before': <String, Object>{},
        'native_counts': {'tests': 1 + skipped, 'passed': 1, 'failed': 0, 'skipped': skipped},
      }));
      final output = Directory('${base.path}/output-$skipped');
      final native = await Process.run(Platform.resolvedExecutable,
        ['--packages=${args.single}', converter.path, raw.path, freeze.path, base.path, output.path]);
      if (skipped == 0) {
        if (native.exitCode != 0 || !File('${output.path}/full.lcov').existsSync()) {
          throw StateError('Valid native-count control rejected: ${native.stderr}');
        }
      } else if (native.exitCode == 0 || output.existsSync() ||
          !native.stderr.toString().contains('Incomplete or skipped native tests')) {
        throw StateError('Skipped native accepted or wrote LCOV');
      }
      results.add({'case': skipped == 0 ? 'valid_counts_control_empty_raw_not_gate' : 'skipped_native_rejected_no_lcov', 'status': 'passed'});
    }
    stdout.writeln(jsonEncode({'tests': results.length, 'failed': 0, 'cases': results}));
  } finally { await base.delete(recursive: true); }
}

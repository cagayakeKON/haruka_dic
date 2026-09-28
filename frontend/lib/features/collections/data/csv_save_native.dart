import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

import 'package:haruka/features/collections/data/csv_file_port.dart';

Future<CsvSaveOutcome> saveCsv(String name, Uint8List bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/csv')],
        fileNameOverrides: [name],
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? CsvSaveOutcome.cancelled
        : CsvSaveOutcome.systemFlowOpened;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return CsvSaveOutcome.cancelled;
  await XFile.fromData(bytes, mimeType: 'text/csv', name: name).saveTo(location.path);
  return CsvSaveOutcome.saved;
}

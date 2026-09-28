import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:haruka/features/collections/data/csv_save_native.dart'
    if (dart.library.js_interop) 'package:haruka/features/collections/data/csv_save_web.dart'
    as platform;
import 'package:haruka/features/collections/domain/vocabulary_csv.dart';

final class PickedCsvFile {
  const PickedCsvFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

enum CsvSaveOutcome { cancelled, saved, downloadStarted, systemFlowOpened }

abstract interface class CsvFilePort {
  Future<PickedCsvFile?> pick();
  Future<CsvSaveOutcome> save(String name, Uint8List bytes);
}

final class SystemCsvFilePort implements CsvFilePort {
  const SystemCsvFilePort();

  @override
  Future<PickedCsvFile?> pick() async {
    const csvTypes = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      mimeTypes: ['text/csv', 'text/plain'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
    );
    final file = await openFile(acceptedTypeGroups: [csvTypes]);
    if (file == null) return null;
    if (await file.length() > vocabularyCsvMaxBytes) {
      throw const CsvReadException(CsvProblem.tooLarge);
    }
    return PickedCsvFile(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<CsvSaveOutcome> save(String name, Uint8List bytes) => platform.saveCsv(name, bytes);
}

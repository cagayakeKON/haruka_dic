import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:haruka/features/collections/data/csv_file_port.dart';

Future<CsvSaveOutcome> saveCsv(String name, Uint8List bytes) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(anchor);
  try {
    anchor.click();
    return CsvSaveOutcome.downloadStarted;
  } finally {
    anchor.remove();
    // The browser may still be dispatching the download when click() returns.
    Future<void>.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  }
}

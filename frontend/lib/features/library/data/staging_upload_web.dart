import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

Future<void> uploadStaging(
  Uri target,
  Map<String, String> headers,
  Uint8List bytes,
  Dio transport,
) async {
  final grantHeaders = web.Headers();
  for (final entry in headers.entries) {
    grantHeaders.append(entry.key, entry.value);
  }
  final response = await web.window
      .fetch(
        target.toString().toJS,
        web.RequestInit(
          method: 'PUT',
          credentials: 'omit',
          redirect: 'error',
          headers: grantHeaders,
          body: bytes.toJS,
        ),
      )
      .toDart
      .timeout(const Duration(minutes: 2));
  if (!response.ok) throw const FormatException('Staging upload failed');
}

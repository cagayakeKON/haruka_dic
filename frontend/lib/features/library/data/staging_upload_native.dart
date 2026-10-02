import 'dart:typed_data';

import 'package:dio/dio.dart';

Future<void> uploadStaging(
  Uri target,
  Map<String, String> headers,
  Uint8List bytes,
  Dio transport,
) async {
  final response = await transport.put<void>(
    target.toString(),
    data: bytes,
    options: Options(
      headers: headers,
      followRedirects: false,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );
  if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
    throw const FormatException('Staging upload failed');
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';

final class SampleAdapter implements HttpClientAdapter {
  SampleAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions, Stream<Uint8List>?) handler;
  bool closed = false;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return handler(options, requestStream);
  }

  @override
  void close({bool force = false}) => closed = true;
}

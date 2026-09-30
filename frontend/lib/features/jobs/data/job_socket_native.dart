import 'dart:io';

import 'job_socket.dart';

Future<JobSocket> connect(Uri uri, Map<String, String> headers) async =>
    _NativeSocket(await WebSocket.connect(uri.toString(), headers: headers));

final class _NativeSocket implements JobSocket {
  _NativeSocket(this.socket);
  final WebSocket socket;
  @override
  Stream<String> get messages => socket.map((value) {
    if (value is! String) throw const FormatException('Invalid job message');
    return value;
  });
  @override
  void send(String message) => socket.add(message);
  @override
  Future<void> close() async {
    await socket.close();
  }
}

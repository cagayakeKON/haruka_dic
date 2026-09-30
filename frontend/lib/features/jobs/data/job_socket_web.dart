import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'job_socket.dart';

Future<JobSocket> connect(Uri uri, Map<String, String> headers) async {
  // Browser cookies are supplied by the browser; credentials never enter URLs.
  final socket = web.WebSocket(uri.toString());
  final opened = Completer<void>();
  socket.onopen = ((web.Event e) {
    if (!opened.isCompleted) opened.complete();
  }).toJS;
  socket.onerror = ((web.Event e) {
    if (!opened.isCompleted) opened.completeError(StateError('Job connection failed'));
  }).toJS;
  try {
    await opened.future.timeout(const Duration(seconds: 15));
  } catch (_) {
    socket.close();
    rethrow;
  }
  return _BrowserSocket(socket);
}

final class _BrowserSocket implements JobSocket {
  _BrowserSocket(this.socket) {
    socket.onmessage = ((web.MessageEvent e) {
      if (messagesController.isClosed) return;
      final value = e.data.dartify();
      if (value is String) {
        messagesController.add(value);
      } else {
        messagesController.addError(const FormatException('Invalid job message'));
      }
    }).toJS;
    socket.onclose = ((web.CloseEvent e) {
      if (!messagesController.isClosed) unawaited(messagesController.close());
    }).toJS;
    socket.onerror = ((web.Event e) {
      if (!messagesController.isClosed) {
        messagesController.addError(StateError('Job connection failed'));
      }
    }).toJS;
  }
  final web.WebSocket socket;
  final messagesController = StreamController<String>();
  @override
  Stream<String> get messages => messagesController.stream;
  @override
  void send(String message) => socket.send(message.toJS);
  @override
  Future<void> close() async {
    socket.close();
    // A rejected authorization can close before the consumer subscribes.
    // Waiting for an unlistened single-subscription stream would never finish.
    if (!messagesController.isClosed) unawaited(messagesController.close());
  }
}

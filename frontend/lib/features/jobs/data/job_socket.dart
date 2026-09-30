import 'job_socket_native.dart' if (dart.library.js_interop) 'job_socket_web.dart' as platform;

abstract interface class JobSocket {
  Stream<String> get messages;
  void send(String message);
  Future<void> close();
}

Future<JobSocket> connectJobSocket(Uri uri, Map<String, String> headers) =>
    platform.connect(uri, headers);

Future<JobSocket> authorizedJobSocket(
  Future<JobSocket> Function(Future<JobSocket> Function(Map<String, String>)) authorize,
  Future<JobSocket> Function(Map<String, String>) connect,
) async {
  JobSocket? opened;
  try {
    return await authorize((headers) async => opened = await connect(headers));
  } catch (_) {
    await opened?.close();
    rethrow;
  }
}

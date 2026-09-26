import 'auth_sync_native.dart' if (dart.library.js_interop) 'auth_sync_web.dart' as implementation;

enum AuthSyncEvent { started, changed }

/// Sends only opaque identity signals. Cookies and tokens never enter it.
abstract interface class AuthSync {
  factory AuthSync(String instanceId, void Function(AuthSyncEvent) onEvent) =
      implementation.PlatformAuthSync;
  void publishStarted();
  void publishChanged();
  Future<T> withIdentityLock<T>(Future<T> Function() action);
  bool locallySignedOut(String audience);
  void setLocallySignedOut(String audience, bool value);
  void dispose();
}

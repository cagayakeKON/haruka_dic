import 'auth_sync.dart';

final class PlatformAuthSync implements AuthSync {
  PlatformAuthSync(String instanceId, void Function(AuthSyncEvent) onEvent);
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  void dispose() {}
}

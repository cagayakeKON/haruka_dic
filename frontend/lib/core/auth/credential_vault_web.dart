import 'credential_vault.dart';

/// Web never reads, writes, or mirrors an HttpOnly session into Dart storage.
final class PlatformCredentialVault implements CredentialVault {
  PlatformCredentialVault(Uri endpoint, String instanceId, String audience);

  @override
  Future<RefreshCredential?> read() async => null;

  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;

  @override
  Future<void> clear({String? sessionRef}) async {}
}

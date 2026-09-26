import 'credential_vault_native.dart'
    if (dart.library.js_interop) 'credential_vault_web.dart'
    as implementation;

/// Only a native refresh secret is persisted. Access tokens remain in memory,
/// while Web sessions are exclusively held in HttpOnly cookies.
abstract interface class CredentialVault {
  factory CredentialVault(String instanceId, String audience) =
      implementation.PlatformCredentialVault;

  Future<RefreshCredential?> read();

  /// Replaces a credential only if the stored generation still matches [prior].
  /// A late refresh response must not overwrite a newer generation.
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next);

  Future<void> clear({String? sessionRef});
}

final class RefreshCredential {
  const RefreshCredential({
    required this.sessionRef,
    required this.generation,
    required this.secret,
    this.pendingRequestId,
    this.pendingAt,
  });

  final String sessionRef;
  final int generation;
  final String secret;

  /// One stable request ID survives a lost refresh response or process restart.
  final String? pendingRequestId;
  final DateTime? pendingAt;

  bool sameVersion(RefreshCredential other) =>
      sessionRef == other.sessionRef &&
      generation == other.generation &&
      secret == other.secret &&
      pendingRequestId == other.pendingRequestId &&
      pendingAt == other.pendingAt;
}

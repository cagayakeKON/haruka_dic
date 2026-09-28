import 'dart:convert';

import 'package:crypto/crypto.dart';

enum CacheSource { network, memory, disk }

enum CacheFreshness { validated, refreshing, offline, stale, blocked }

enum CacheStorageMode { persistent, memoryOnly }

enum CacheDisposition { networkOnly, memoryOnly, validatedText, validatedAudio }

/// Created only after the endpoint and current access response have been verified.
final class CacheScope {
  CacheScope._({
    required this.endpointKey,
    required this.instanceId,
    required this.userId,
    required this.audience,
    required this.sessionRef,
    required this.securityEpoch,
    required this.authzVersion,
    required this.policyVersion,
  });

  factory CacheScope.confirmed({
    required Uri endpoint,
    required String instanceId,
    required String userId,
    required String audience,
    required String sessionRef,
    int securityEpoch = -1,
    int authzVersion = 0,
    int policyVersion = 0,
  }) {
    if (!endpoint.hasScheme ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (endpoint.scheme != 'https' &&
            !(endpoint.scheme == 'http' &&
                const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(endpoint.host)))) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Expected a confirmed HTTPS API base URL');
    }
    if ([instanceId, userId, audience, sessionRef].any((part) => part.isEmpty)) {
      throw ArgumentError('A confirmed scope needs instance, user, audience and session');
    }
    final path = endpoint.path.replaceAll(RegExp(r'/+$'), '');
    final normalized = Uri(
      scheme: endpoint.scheme.toLowerCase(),
      host: endpoint.host.toLowerCase(),
      port: endpoint.hasPort ? endpoint.port : null,
      path: path,
    );
    return CacheScope._(
      endpointKey: normalized.toString(),
      instanceId: instanceId,
      userId: userId,
      audience: audience,
      sessionRef: sessionRef,
      securityEpoch: securityEpoch,
      authzVersion: authzVersion,
      policyVersion: policyVersion,
    );
  }

  final String endpointKey;
  final String instanceId;
  final String userId;
  final String audience;
  final String sessionRef;
  final int securityEpoch;
  final int authzVersion;
  final int policyVersion;

  String get partition => sha256
      .convert(utf8.encode(jsonEncode([endpointKey, instanceId, userId, audience])))
      .toString();

  String get binding => sha256.convert(utf8.encode(jsonEncode([partition, sessionRef]))).toString();
}

/// An exact resource projection. Callers cannot substitute a URL or a user ID.
final class CacheResource {
  const CacheResource({
    required this.kind,
    required this.id,
    required this.projection,
    required this.action,
    required this.sourceBinding,
    this.queryKey = '',
  });

  final String kind;
  final String id;
  final String projection;
  final String action;
  final String sourceBinding;
  final String queryKey;

  /// Only reviewed source/action projections may enter the private persistent
  /// cache. New domains must be added deliberately; exam sessions, answer
  /// sheets and attempt-limited listening are intentionally absent.
  bool allowsPersistent(CacheDisposition disposition) => switch ((
    kind,
    projection,
    action,
    disposition,
  )) {
    ('material_content', 'novel-reading-v1', 'material.read', CacheDisposition.validatedText) =>
      true,
    ('material_content', 'textbook-reading-v1', 'material.read', CacheDisposition.validatedText) =>
      true,
    ('learning_text', 'learning-card-v1', 'agent.read', CacheDisposition.validatedText) => true,
    ('speech_asset', 'ordinary-audio-v1', 'speech.play', CacheDisposition.validatedAudio) => true,
    _ => false,
  };

  static bool allowsPersistentKind(String kind, CacheDisposition disposition) =>
      switch ((kind, disposition)) {
        ('material_content', CacheDisposition.validatedText) => true,
        ('learning_text', CacheDisposition.validatedText) => true,
        ('speech_asset', CacheDisposition.validatedAudio) => true,
        _ => false,
      };

  /// Keep the existing local key for query cards while the wire kind moves to
  /// learning_text. This alias is limited to the historical card projection.
  String get _localKeyKind =>
      kind == 'learning_text' && projection == 'learning-card-v1' && action == 'agent.read'
      ? 'learning_result'
      : kind;

  bool acceptsStoredKind(String storedKind) =>
      storedKind == kind ||
      (storedKind == 'learning_result' &&
          _localKeyKind == 'learning_result' &&
          kind == 'learning_text');

  String keyFor(CacheScope scope) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            scope.partition,
            _localKeyKind,
            id,
            projection,
            action,
            sourceBinding,
            queryKey,
          ]),
        ),
      )
      .toString();
}

final class CachePolicy<T> {
  const CachePolicy({
    required this.kind,
    required this.disposition,
    required this.decode,
    required this.encode,
    required this.dependencies,
  });

  final String kind;
  final CacheDisposition disposition;
  final T Function(Map<String, Object?>) decode;
  final Map<String, Object?> Function(T) encode;
  final Set<String> Function(CacheResource) dependencies;

  bool get persistent =>
      disposition == CacheDisposition.validatedText ||
      disposition == CacheDisposition.validatedAudio;
}

final class CacheVersion {
  const CacheVersion({
    required this.resource,
    required this.representation,
    required this.artifact,
    this.nlp = '',
    this.binding = '',
  });
  final String resource;
  final String representation;
  final String artifact;
  final String nlp;
  final String binding;

  Map<String, String> toJson() => {
    'resource': resource,
    'representation': representation,
    'artifact': artifact,
    'nlp': nlp,
    'binding': binding,
  };

  static CacheVersion fromJson(Map<String, Object?> json) => CacheVersion(
    resource: json['resource'] as String,
    representation: json['representation'] as String,
    artifact: json['artifact'] as String,
    nlp: json['nlp'] as String? ?? '',
    binding: json['binding'] as String? ?? '',
  );
}

/// Physical entry identity. A logical resource may retain several immutable
/// completed versions while cache_heads selects its current version.
String cacheEntryKey(String logicalKey, CacheVersion version) =>
    sha256.convert(utf8.encode(jsonEncode([logicalKey, version.toJson()]))).toString();

final class CacheGrant {
  const CacheGrant({
    required this.scopeBinding,
    required this.resourceKey,
    required this.version,
    required this.expiresAt,
    required this.serverTime,
    required this.securityEpoch,
    required this.authzVersion,
    this.policyVersion = 0,
  });

  final String scopeBinding;
  final String resourceKey;
  final CacheVersion version;
  final DateTime expiresAt;
  final DateTime serverTime;
  final int securityEpoch;
  final int authzVersion;
  final int policyVersion;

  /// Converts a trusted, authenticated validate/descriptor response to the
  /// local lease format. The server describes a resource, never a device hash.
  static CacheGrant fromTrustedResponse({
    required Map<String, Object?> json,
    required CacheScope scope,
    required CacheResource resource,
    required CacheVersion version,
  }) {
    Map<String, Object?> object(Object? value) {
      if (value is! Map) throw const FormatException('Invalid cache grant object');
      return value.cast<String, Object?>();
    }

    if (json['schema_version'] != 1) throw const FormatException('Unsupported cache grant');
    final issuedScope = object(json['scope']);
    final authz = object(issuedScope['authz_version']);
    final issuedResource = object(json['resource']);
    final issuedVersion = CacheVersion.fromJson(object(json['version']));
    final requiredActions = json['required_actions'];
    if (issuedScope['instance_id'] != scope.instanceId ||
        issuedScope['user_id'] != scope.userId ||
        issuedScope['audience'] != scope.audience ||
        issuedScope['session_ref'] != scope.sessionRef ||
        issuedScope['security_epoch'] != scope.securityEpoch ||
        authz['user'] != scope.authzVersion ||
        authz['policy'] != scope.policyVersion ||
        issuedResource['kind'] != resource.kind ||
        issuedResource['id'] != resource.id ||
        issuedResource['source_binding'] != resource.sourceBinding ||
        issuedResource['projection'] != resource.projection ||
        issuedResource['action'] != resource.action ||
        (issuedResource['query_key'] ?? '') != resource.queryKey ||
        requiredActions is! List ||
        requiredActions.isEmpty ||
        !requiredActions.every((item) => item is String && item.isNotEmpty) ||
        !requiredActions.contains(resource.action) ||
        issuedVersion.resource != version.resource ||
        issuedVersion.representation != version.representation ||
        issuedVersion.artifact != version.artifact ||
        issuedVersion.nlp != version.nlp ||
        issuedVersion.binding != version.binding) {
      throw const FormatException('Cache grant scope or resource mismatch');
    }
    final issuedAt = DateTime.parse(json['issued_at'] as String).toUtc();
    final serverTime = DateTime.parse(json['server_time'] as String).toUtc();
    final expiresAt = DateTime.parse(json['expires_at'] as String).toUtc();
    if (issuedAt.isAfter(serverTime) || !expiresAt.isAfter(serverTime)) {
      throw const FormatException('Invalid cache grant lifetime');
    }
    return CacheGrant(
      scopeBinding: scope.binding,
      resourceKey: resource.keyFor(scope),
      version: version,
      expiresAt: expiresAt,
      serverTime: serverTime,
      securityEpoch: scope.securityEpoch,
      authzVersion: scope.authzVersion,
      policyVersion: scope.policyVersion,
    );
  }

  factory CacheGrant.fromJson(Map<String, Object?> json) => CacheGrant(
    scopeBinding: json['scope_binding'] as String,
    resourceKey: json['resource_key'] as String,
    version: CacheVersion.fromJson((json['version'] as Map).cast<String, Object?>()),
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    serverTime: DateTime.parse(json['server_time'] as String).toUtc(),
    securityEpoch: json['security_epoch'] as int,
    authzVersion: json['authz_version'] as int,
    policyVersion: json['policy_version'] as int,
  );

  Map<String, Object?> toJson() => {
    'scope_binding': scopeBinding,
    'resource_key': resourceKey,
    'version': version.toJson(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'server_time': serverTime.toUtc().toIso8601String(),
    'security_epoch': securityEpoch,
    'authz_version': authzVersion,
    'policy_version': policyVersion,
  };
}

enum ValidationState { same, changed, unavailable }

final class CacheValidation {
  const CacheValidation({
    required this.state,
    this.version,
    this.grant,
    this.revokeGrant = false,
    this.readResource,
  });
  final ValidationState state;
  final CacheVersion? version;
  final CacheGrant? grant;

  /// An explicit server revocation. A null grant alone means no new lease.
  final bool revokeGrant;
  final CacheResource? readResource;
}

final class CachePayload<T> {
  const CachePayload({
    required this.value,
    required this.version,
    this.serverSaved = true,
    this.grant,
  });
  final T value;
  final CacheVersion version;
  final bool serverSaved;
  final CacheGrant? grant;
}

final class CacheView<T> {
  const CacheView({
    required this.data,
    required this.source,
    required this.freshness,
    required this.serverSaved,
    required this.localReady,
    this.lastValidatedAt,
    this.error,
    this.resource,
    this.version,
    this.entryKey,
    this.publicationEpoch,
  });

  final T? data;
  final CacheSource source;
  final CacheFreshness freshness;
  final bool serverSaved;
  final bool localReady;
  final DateTime? lastValidatedAt;
  final Object? error;

  /// The resource actually validated/read; changed projections may have a new key.
  final CacheResource? resource;
  final CacheVersion? version;
  final String? entryKey;
  final int? publicationEpoch;
}

final class CacheBlocked implements Exception {
  const CacheBlocked(this.reason);
  final String reason;
  @override
  String toString() => 'CacheBlocked($reason)';
}

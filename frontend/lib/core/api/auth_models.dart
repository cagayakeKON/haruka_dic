import 'wire.dart';

final class AuthPolicy {
  const AuthPolicy({
    required this.registrationEnabled,
    required this.recoveryEnabled,
    required this.actionLinkBase,
    required this.passwordMinLength,
    required this.passwordMaxLength,
  });

  factory AuthPolicy.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['registration_enabled'] is! bool ||
        json['recovery_enabled'] is! bool ||
        json['approval_required'] != false ||
        json['email_verification_required'] != true ||
        json['recovery_mode'] != 'email' ||
        json['password_min_length'] is! int ||
        json['password_max_length'] is! int) {
      throw const FormatException('Invalid auth policy');
    }
    final base = Uri.tryParse(wireString(json['action_link_base_url']));
    if (base == null ||
        !base.hasAuthority ||
        !const {'http', 'https'}.contains(base.scheme) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        (json['password_min_length'] as int) < 1 ||
        (json['password_max_length'] as int) < (json['password_min_length'] as int)) {
      throw const FormatException('Invalid action link base');
    }
    return AuthPolicy(
      registrationEnabled: json['registration_enabled'] as bool,
      recoveryEnabled: json['recovery_enabled'] as bool,
      actionLinkBase: base,
      passwordMinLength: json['password_min_length'] as int,
      passwordMaxLength: json['password_max_length'] as int,
    );
  }

  final bool registrationEnabled;
  final bool recoveryEnabled;
  final Uri actionLinkBase;
  final int passwordMinLength;
  final int passwordMaxLength;
}

final class MailReceipt {
  const MailReceipt(this.nextStep);
  factory MailReceipt.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['state'] != 'accepted') throw const FormatException('Invalid mail receipt');
    final nextStep = wireString(json['next_step']);
    if (nextStep != 'verify_email' && nextStep != 'check_email') {
      throw const FormatException('Invalid mail receipt');
    }
    return MailReceipt(nextStep);
  }
  final String nextStep;
}

final class ActivationStatus {
  const ActivationStatus({required this.active, required this.expiresAt});
  factory ActivationStatus.fromJson(Object? value) {
    final json = wireObject(value);
    final state = wireString(json['state']);
    if (state != 'active' && state != 'pending_email') {
      throw const FormatException('Invalid activation state');
    }
    if (json['action_required'] != (state == 'active' ? null : 'verify_email')) {
      throw const FormatException('Invalid activation action');
    }
    return ActivationStatus(active: state == 'active', expiresAt: wireUtc(json['expires_at']));
  }
  final bool active;
  final DateTime expiresAt;
}

final class CsrfRead {
  const CsrfRead({required this.sessionRef, required this.token});
  factory CsrfRead.fromJson(Object? value) {
    final json = wireObject(value);
    final token = wireString(json['csrf_token']);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Invalid CSRF token');
    }
    return CsrfRead(sessionRef: wireUuid(json['session_ref']), token: token);
  }
  final String sessionRef;
  final String token;
}

final class LoginResult {
  const LoginResult._({
    required this.pending,
    this.sessionRef,
    this.accessToken,
    this.refreshToken,
    this.generation,
    this.continuationToken,
    this.continuationExpiresAt,
  });

  factory LoginResult.web(Object? value) => LoginResult._decode(value, native: false);
  factory LoginResult.native(Object? value) => LoginResult._decode(value, native: true);

  factory LoginResult._decode(Object? value, {required bool native}) {
    final json = wireObject(value);
    if (json['state'] == 'action_required') {
      if (json['action_required'] != 'verify_email') throw const FormatException('Invalid action');
      return LoginResult._(
        pending: true,
        continuationToken: wireString(json['continuation_token']),
        continuationExpiresAt: wireUtc(json['continuation_expires_at']),
      );
    }
    if (json['state'] != 'authenticated' ||
        json['audience'] != (native ? 'client' : json['audience'])) {
      throw const FormatException('Invalid login state');
    }
    final audience = wireString(json['audience']);
    if (audience != 'client' && audience != 'admin') {
      throw const FormatException('Invalid audience');
    }
    final sessionRef = wireUuid(json['session_ref']);
    wireUtc(json['absolute_expires_at']);
    wireUtc(json['server_time']);
    if (!native) {
      wireUtc(json['idle_expires_at']);
      return LoginResult._(pending: false, sessionRef: sessionRef);
    }
    wireUtc(json['access_expires_at']);
    wireUtc(json['refresh_expires_at']);
    final generation = json['session_generation'];
    if (generation is! int || generation < 1) throw const FormatException('Invalid generation');
    return LoginResult._(
      pending: false,
      sessionRef: sessionRef,
      accessToken: wireString(json['access_token']),
      refreshToken: wireString(json['refresh_token']),
      generation: generation,
    );
  }

  final bool pending;
  final String? sessionRef;
  final String? accessToken;
  final String? refreshToken;
  final int? generation;
  final String? continuationToken;
  final DateTime? continuationExpiresAt;
}

final class AuthorizationVersion {
  const AuthorizationVersion({required this.user, required this.policy});
  factory AuthorizationVersion.fromJson(Object? value) {
    final json = wireObject(value);
    final user = json['user'];
    final policy = json['policy'];
    if (user is! int || user < 1 || policy is! int || policy < 1) {
      throw const FormatException('Invalid authorization version');
    }
    return AuthorizationVersion(user: user, policy: policy);
  }
  final int user;
  final int policy;
}

final class PermissionGrant {
  const PermissionGrant({required this.code, required this.dataScope});
  factory PermissionGrant.fromJson(Object? value) {
    final json = wireObject(value);
    final code = wireString(json['code']);
    final scope = wireString(json['data_scope']);
    if (code.isEmpty || scope.isEmpty) throw const FormatException('Invalid permission');
    return PermissionGrant(code: code, dataScope: scope);
  }
  final String code;
  final String dataScope;
}

final class NavigationItem {
  const NavigationItem({required this.key, required this.routeKey, required this.title});
  factory NavigationItem.fromJson(Object? value) {
    final json = wireObject(value);
    return NavigationItem(
      key: wireString(json['key']),
      routeKey: wireString(json['route_key']),
      title: wireString(json['title']),
    );
  }
  final String key;
  final String routeKey;
  final String title;
}

final class AccessRead {
  const AccessRead({
    required this.userId,
    required this.instanceId,
    required this.audience,
    required this.sessionRef,
    required this.permissions,
    required this.authzVersion,
    required this.navigation,
    required this.featureFlags,
  });
  factory AccessRead.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['account_status'] != 'active') throw const FormatException('Inactive access');
    final audience = wireString(json['audience']);
    if (audience != 'client' && audience != 'admin') {
      throw const FormatException('Invalid audience');
    }
    final permissions = json['permissions'];
    if (permissions is! List<Object?>) throw const FormatException('Invalid permissions');
    final navigation = json['navigation'];
    final flags = json['feature_flags'];
    if (navigation is! List<Object?> || flags is! List<Object?>) {
      throw const FormatException('Invalid access projection');
    }
    return AccessRead(
      userId: wireUuid(json['user_id']),
      instanceId: wireString(json['instance_id']),
      audience: audience,
      sessionRef: wireUuid(json['session_ref']),
      permissions: List.unmodifiable(permissions.map(PermissionGrant.fromJson)),
      authzVersion: AuthorizationVersion.fromJson(json['authz_version']),
      navigation: List.unmodifiable(navigation.map(NavigationItem.fromJson)),
      featureFlags: List.unmodifiable(flags.map(wireString)),
    );
  }
  final String userId;
  final String instanceId;
  final String audience;
  final String sessionRef;
  final List<PermissionGrant> permissions;
  final AuthorizationVersion authzVersion;
  final List<NavigationItem> navigation;
  final List<String> featureFlags;
  bool allows(String code) => permissions.any((grant) => grant.code == code);
}

final class AdminPolicy {
  const AdminPolicy({required this.registrationEnabled, required this.revision});
  factory AdminPolicy.fromJson(Object? value) {
    final json = wireObject(value);
    final mode = wireString(json['registration_mode']);
    final enabled = json['registration_enabled'];
    final revision = json['revision'];
    if ((mode != 'open' && mode != 'closed') ||
        enabled is! bool ||
        enabled != (mode == 'open') ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid admin policy');
    }
    return AdminPolicy(registrationEnabled: enabled, revision: revision);
  }
  final bool registrationEnabled;
  final int revision;
}

final class AccountRead {
  const AccountRead({required this.email, required this.emailVerifiedAt, required this.createdAt});
  factory AccountRead.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['status'] != 'active') throw const FormatException('Invalid account status');
    final verified = json['email_verified_at'];
    return AccountRead(
      email: wireString(json['email']),
      emailVerifiedAt: verified == null ? null : wireUtc(verified),
      createdAt: wireUtc(json['created_at']),
    );
  }
  final String email;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;
}

final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.platform,
    required this.audience,
    required this.transport,
    required this.deviceSummary,
    required this.createdAt,
    required this.lastSeenAt,
    required this.absoluteExpiresAt,
    required this.revokedAt,
    required this.isCurrent,
    required this.isRevoked,
  });
  factory SessionSummary.fromJson(Object? value) {
    final json = wireObject(value);
    final revoked = json['revoked_at'];
    final revokedAt = revoked == null ? null : wireUtc(revoked);
    final lastSeen = json['last_seen_at'];
    final audience = wireString(json['audience']);
    final transport = wireString(json['transport']);
    final platform = wireString(json['platform']);
    if (!const {'client', 'admin'}.contains(audience) ||
        !const {'web', 'native'}.contains(transport) ||
        !const {'web', 'windows', 'android'}.contains(platform) ||
        (transport == 'web' && platform != 'web') ||
        (transport == 'native' && platform == 'web')) {
      throw const FormatException('Invalid session transport');
    }
    final summary = json['device_summary'];
    if (summary != null && summary is! String) {
      throw const FormatException('Invalid device summary');
    }
    final current = json['is_current'];
    if (current is! bool) throw const FormatException('Invalid current session');
    return SessionSummary(
      id: wireUuid(json['id']),
      platform: platform,
      audience: audience,
      transport: transport,
      deviceSummary: summary as String?,
      createdAt: wireUtc(json['created_at']),
      lastSeenAt: lastSeen == null ? null : wireUtc(lastSeen),
      absoluteExpiresAt: wireUtc(json['absolute_expires_at']),
      revokedAt: revokedAt,
      isCurrent: current,
      isRevoked: revoked != null,
    );
  }
  final String id;
  final String platform;
  final String audience;
  final String transport;
  final String? deviceSummary;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final DateTime absoluteExpiresAt;
  final DateTime? revokedAt;
  final bool isCurrent;
  final bool isRevoked;
}

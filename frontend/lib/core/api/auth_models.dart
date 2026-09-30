import 'wire.dart';

final class AuthPolicy {
  const AuthPolicy({
    required this.registrationEnabled,
    required this.approvalRequired,
    required this.recoveryEnabled,
    required this.recoveryMode,
    required this.actionLinkBase,
    required this.passwordMinLength,
    required this.passwordMaxLength,
  });

  factory AuthPolicy.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['registration_enabled'] is! bool ||
        json['recovery_enabled'] is! bool ||
        json['approval_required'] is! bool ||
        json['email_verification_required'] != true ||
        !_recoveryModes.contains(json['recovery_mode']) ||
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
      approvalRequired: json['approval_required'] as bool,
      recoveryEnabled: json['recovery_enabled'] as bool,
      recoveryMode: json['recovery_mode'] as String,
      actionLinkBase: base,
      passwordMinLength: json['password_min_length'] as int,
      passwordMaxLength: json['password_max_length'] as int,
    );
  }

  final bool registrationEnabled;
  final bool approvalRequired;
  final bool recoveryEnabled;
  final String recoveryMode;
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
    if (nextStep != 'verify_email' && nextStep != 'check_email' && nextStep != 'await_review') {
      throw const FormatException('Invalid mail receipt');
    }
    return MailReceipt(nextStep);
  }
  final String nextStep;
}

final class ActivationStatus {
  const ActivationStatus({required this.state, required this.expiresAt});
  factory ActivationStatus.fromJson(Object? value) {
    final json = wireObject(value);
    final state = wireString(json['state']);
    const known = {'pending_email', 'pending_approval', 'rejected', 'active'};
    if (!known.contains(state)) throw const FormatException('Invalid activation state');
    final action = json['action_required'];
    if (state == 'pending_email' ? action != 'verify_email' : action != null) {
      throw const FormatException('Invalid activation action');
    }
    return ActivationStatus(state: state, expiresAt: wireUtc(json['expires_at']));
  }
  final String state;
  final DateTime expiresAt;
  bool get active => state == 'active';
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
      const actions = {'verify_email', 'await_approval', 'rejected'};
      if (!actions.contains(json['action_required'])) {
        throw const FormatException('Invalid action');
      }
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
  const NavigationItem({
    required this.key,
    required this.routeKey,
    required this.title,
    this.iconKey,
    this.titleCustomized = false,
    this.iconCustomized = false,
  });
  factory NavigationItem.fromJson(Object? value) {
    final json = wireObject(value);
    return NavigationItem(
      key: wireString(json['key']),
      routeKey: wireString(json['route_key']),
      title: wireString(json['title']),
      iconKey: json['icon_key'] == null ? null : wireString(json['icon_key']),
      titleCustomized: json['title_customized'] == true,
      iconCustomized: json['icon_customized'] == true,
    );
  }
  final String key;
  final String routeKey;
  final String title;
  final String? iconKey;
  final bool titleCustomized;
  final bool iconCustomized;
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
    this.securityEpoch,
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
    final securityEpoch = json['security_epoch'];
    if (securityEpoch != null && (securityEpoch is! int || securityEpoch < 0)) {
      throw const FormatException('Invalid security epoch');
    }
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
      securityEpoch: securityEpoch as int?,
    );
  }
  final String userId;
  final String instanceId;
  final String audience;
  final String sessionRef;
  final int? securityEpoch;
  final List<PermissionGrant> permissions;
  final AuthorizationVersion authzVersion;
  final List<NavigationItem> navigation;
  final List<String> featureFlags;
  bool allows(String code) => permissions.any((grant) => grant.code == code);
}

final class AdminPolicy {
  const AdminPolicy({
    required this.registrationMode,
    required this.registrationEnabled,
    required this.recoveryMode,
    required this.revision,
  });
  factory AdminPolicy.fromJson(Object? value) {
    final json = wireObject(value);
    final mode = wireString(json['registration_mode']);
    final enabled = json['registration_enabled'];
    final revision = json['revision'];
    if (!const {'closed', 'approval', 'open'}.contains(mode) ||
        enabled is! bool ||
        enabled != (mode != 'closed') ||
        json['email_verification_required'] != true ||
        !_recoveryModes.contains(json['recovery_mode']) ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid admin policy');
    }
    return AdminPolicy(
      registrationMode: mode,
      registrationEnabled: enabled,
      recoveryMode: json['recovery_mode'] as String,
      revision: revision,
    );
  }
  final String registrationMode;
  final bool registrationEnabled;
  final String recoveryMode;
  final int revision;
}

const _recoveryModes = {'disabled', 'email', 'manual', 'email_or_manual'};

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

bool _flag(Object? value) {
  if (value is! bool) throw const FormatException('Invalid flag');
  return value;
}

int _revision(Object? value) {
  if (value is! int || value < 1) throw const FormatException('Invalid revision');
  return value;
}

int _count(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Invalid count');
  return value;
}

String _choice(Object? value, Set<String> allowed) {
  final text = wireString(value);
  if (!allowed.contains(text)) throw const FormatException('Invalid choice');
  return text;
}

final class RoleGrantRead {
  const RoleGrantRead({
    required this.permissionCode,
    required this.effect,
    required this.dataScope,
  });

  factory RoleGrantRead.fromJson(Object? value) {
    final json = wireObject(value);
    return RoleGrantRead(
      permissionCode: wireString(json['permission_code']),
      effect: _choice(json['effect'], const {'allow', 'deny'}),
      dataScope: _choice(json['data_scope'], const {'self', 'platform_metadata'}),
    );
  }

  final String permissionCode;
  final String effect;
  final String dataScope;
}

final class RoleParentRead {
  const RoleParentRead({required this.roleId, required this.code, required this.enabled});

  factory RoleParentRead.fromJson(Object? value) {
    final json = wireObject(value);
    return RoleParentRead(
      roleId: wireUuid(json['role_id']),
      code: wireString(json['code']),
      enabled: _flag(json['enabled']),
    );
  }

  final String roleId;
  final String code;
  final bool enabled;
}

final class RoleRead {
  const RoleRead({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.protected,
    required this.enabled,
    required this.revision,
    required this.grants,
    required this.parents,
    required this.memberCount,
  });

  factory RoleRead.fromJson(Object? value) {
    final json = wireObject(value);
    final description = json['description'];
    if (description != null && description is! String) {
      throw const FormatException('Invalid role description');
    }
    final grants = json['grants'];
    final parents = json['parents'];
    if (grants is! List<Object?> || parents is! List<Object?>) {
      throw const FormatException('Invalid role graph');
    }
    return RoleRead(
      id: wireUuid(json['id']),
      code: wireString(json['code']),
      name: wireString(json['name']),
      description: description as String?,
      protected: _flag(json['protected']),
      enabled: _flag(json['enabled']),
      revision: _revision(json['revision']),
      grants: List.unmodifiable(grants.map(RoleGrantRead.fromJson)),
      parents: List.unmodifiable(parents.map(RoleParentRead.fromJson)),
      memberCount: _count(json['member_count']),
    );
  }

  final String id;
  final String code;
  final String name;
  final String? description;
  final bool protected;
  final bool enabled;
  final int revision;
  final List<RoleGrantRead> grants;
  final List<RoleParentRead> parents;
  final int memberCount;

  RoleRead copy({
    String? name,
    String? description,
    bool clearDescription = false,
    bool? enabled,
    int? revision,
    List<RoleGrantRead>? grants,
    List<RoleParentRead>? parents,
  }) => RoleRead(
    id: id,
    code: code,
    name: name ?? this.name,
    description: clearDescription ? null : description ?? this.description,
    protected: protected,
    enabled: enabled ?? this.enabled,
    revision: revision ?? this.revision,
    grants: grants ?? this.grants,
    parents: parents ?? this.parents,
    memberCount: memberCount,
  );
}

final class PermissionCatalogRead {
  const PermissionCatalogRead({
    required this.code,
    required this.audience,
    required this.dataScope,
    required this.enabled,
  });

  factory PermissionCatalogRead.fromJson(Object? value) {
    final json = wireObject(value);
    return PermissionCatalogRead(
      code: wireString(json['code']),
      audience: _choice(json['audience'], const {'client', 'admin'}),
      dataScope: _choice(json['data_scope'], const {'self', 'platform_metadata'}),
      enabled: _flag(json['enabled']),
    );
  }

  static List<PermissionCatalogRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid permissions');
    return List.unmodifiable(value.map(PermissionCatalogRead.fromJson));
  }

  final String code;
  final String audience;
  final String dataScope;
  final bool enabled;
}

final class GrantBoundaryRead {
  const GrantBoundaryRead({
    required this.boundaryKind,
    required this.targetRoleId,
    required this.permissionCode,
    required this.dataScope,
    required this.revision,
  });

  factory GrantBoundaryRead.fromJson(Object? value) {
    final json = wireObject(value);
    final target = json['target_role_id'];
    final code = json['permission_code'];
    final scope = json['data_scope'];
    if ((target != null && target is! String) ||
        (code != null && code is! String) ||
        (scope != null && scope is! String)) {
      throw const FormatException('Invalid grant boundary');
    }
    return GrantBoundaryRead(
      boundaryKind: _choice(json['boundary_kind'], const {
        'assign_role',
        'assign_permission',
        'manage_account_role',
        'manage_unassigned_accounts',
      }),
      targetRoleId: target == null ? null : wireUuid(target),
      permissionCode: code as String?,
      dataScope: scope == null ? null : _choice(scope, const {'self', 'platform_metadata'}),
      revision: _revision(json['revision']),
    );
  }

  static List<GrantBoundaryRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid grant boundaries');
    return List.unmodifiable(value.map(GrantBoundaryRead.fromJson));
  }

  final String boundaryKind;
  final String? targetRoleId;
  final String? permissionCode;
  final String? dataScope;
  final int revision;
}

final class AuthorizationWriteResult {
  const AuthorizationWriteResult({
    required this.roleId,
    required this.revision,
    required this.authorizationRevision,
    required this.auditId,
    required this.affectedCount,
  });

  factory AuthorizationWriteResult.fromJson(Object? value) {
    final json = wireObject(value);
    final audit = json['audit_id'];
    if (audit != null && audit is! String) throw const FormatException('Invalid audit id');
    return AuthorizationWriteResult(
      roleId: wireUuid(json['role_id']),
      revision: _revision(json['revision']),
      authorizationRevision: _revision(json['authorization_revision']),
      auditId: audit == null ? null : wireUuid(audit),
      affectedCount: _count(json['affected_count']),
    );
  }

  final String roleId;
  final int revision;
  final int authorizationRevision;
  final String? auditId;
  final int affectedCount;
}

final class AccountRoleRead {
  const AccountRoleRead({
    required this.roleId,
    required this.code,
    required this.name,
    required this.enabled,
    required this.protected,
  });

  factory AccountRoleRead.fromJson(Object? value) {
    final json = wireObject(value);
    return AccountRoleRead(
      roleId: wireUuid(json['role_id']),
      code: wireString(json['code']),
      name: wireString(json['name']),
      enabled: _flag(json['enabled']),
      protected: _flag(json['protected']),
    );
  }

  final String roleId;
  final String code;
  final String name;
  final bool enabled;
  final bool protected;
}

final class GovernedAccountRead {
  const GovernedAccountRead({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.status,
    required this.emailVerified,
    required this.locked,
    required this.approvalStatus,
    required this.audiences,
    required this.roles,
    required this.liveSessionCount,
    required this.revision,
  });

  factory GovernedAccountRead.fromJson(Object? value) {
    final json = wireObject(value);
    final name = json['display_name'];
    if (name != null && name is! String) throw const FormatException('Invalid display name');
    final audiences = json['audiences'];
    final roles = json['roles'];
    if (audiences is! List<Object?> || roles is! List<Object?>) {
      throw const FormatException('Invalid account');
    }
    return GovernedAccountRead(
      userId: wireUuid(json['user_id']),
      email: wireString(json['email']),
      displayName: name == null ? null : wireString(name),
      status: _choice(json['status'], const {'pending', 'active', 'disabled'}),
      emailVerified: _flag(json['email_verified']),
      locked: _flag(json['locked']),
      approvalStatus: _choice(json['approval_status'], const {
        'not_required',
        'pending',
        'approved',
        'rejected',
      }),
      audiences: List.unmodifiable(
        audiences.map((item) => _choice(item, const {'client', 'admin'})),
      ),
      roles: List.unmodifiable(roles.map(AccountRoleRead.fromJson)),
      liveSessionCount: _count(json['live_session_count']),
      revision: _revision(json['revision']),
    );
  }

  static List<GovernedAccountRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid accounts');
    return List.unmodifiable(value.map(GovernedAccountRead.fromJson));
  }

  GovernedAccountRead copy({
    String? displayName,
    List<AccountRoleRead>? roles,
    int? revision,
    String? status,
  }) {
    return GovernedAccountRead(
      userId: userId,
      email: email,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      emailVerified: emailVerified,
      locked: locked,
      approvalStatus: approvalStatus,
      audiences: audiences,
      roles: roles ?? this.roles,
      liveSessionCount: liveSessionCount,
      revision: revision ?? this.revision,
    );
  }

  final String userId;
  final String email;
  final String? displayName;
  final String status;
  final bool emailVerified;
  final bool locked;
  final String approvalStatus;
  final List<String> audiences;
  final List<AccountRoleRead> roles;
  final int liveSessionCount;
  final int revision;
}

final class AccountSessionRead {
  const AccountSessionRead({
    required this.sessionId,
    required this.audience,
    required this.transport,
    required this.platform,
    required this.deviceSummary,
    required this.createdAt,
    required this.lastSeenAt,
    required this.absoluteExpiresAt,
    required this.revokedAt,
  });

  factory AccountSessionRead.fromJson(Object? value) {
    final json = wireObject(value);
    final device = json['device_summary'];
    final seen = json['last_seen_at'];
    final revoked = json['revoked_at'];
    if (device != null && device is! String) throw const FormatException('Invalid device summary');
    if (seen != null && seen is! String) throw const FormatException('Invalid session time');
    if (revoked != null && revoked is! String) throw const FormatException('Invalid session time');
    return AccountSessionRead(
      sessionId: wireUuid(json['session_id']),
      audience: _choice(json['audience'], const {'client', 'admin'}),
      transport: _choice(json['transport'], const {'web', 'native'}),
      platform: wireString(json['platform']),
      deviceSummary: device == null ? null : wireString(device),
      createdAt: DateTime.parse(wireString(json['created_at'])),
      lastSeenAt: seen == null ? null : DateTime.parse(wireString(seen)),
      absoluteExpiresAt: DateTime.parse(wireString(json['absolute_expires_at'])),
      revokedAt: revoked == null ? null : DateTime.parse(wireString(revoked)),
    );
  }

  static List<AccountSessionRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid sessions');
    return List.unmodifiable(value.map(AccountSessionRead.fromJson));
  }

  final String sessionId;
  final String audience;
  final String transport;
  final String platform;
  final String? deviceSummary;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final DateTime absoluteExpiresAt;
  final DateTime? revokedAt;
}

final class ManualRecoveryRead {
  const ManualRecoveryRead({
    required this.challengeId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ManualRecoveryRead.fromJson(Object? value) {
    final json = wireObject(value);
    return ManualRecoveryRead(
      challengeId: wireUuid(json['challenge_id']),
      status: _choice(json['status'], const {
        'requested',
        'issued',
        'rejected',
        'consumed',
        'expired',
      }),
      createdAt: DateTime.parse(wireString(json['created_at'])),
      expiresAt: DateTime.parse(wireString(json['expires_at'])),
    );
  }

  static List<ManualRecoveryRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid recovery requests');
    return List.unmodifiable(value.map(ManualRecoveryRead.fromJson));
  }

  final String challengeId;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
}

final class ManualRecoveryDecisionResult {
  const ManualRecoveryDecisionResult({
    required this.challengeId,
    required this.status,
    required this.revision,
    required this.expiresAt,
    required this.token,
  });

  factory ManualRecoveryDecisionResult.fromJson(Object? value) {
    final json = wireObject(value);
    final token = json['token'];
    if (token != null && token is! String) throw const FormatException('Invalid recovery token');
    final revision = json['revision'];
    if (revision is! int || revision < 1) throw const FormatException('Invalid recovery revision');
    return ManualRecoveryDecisionResult(
      challengeId: wireUuid(json['challenge_id']),
      status: _choice(json['status'], const {'issued', 'rejected'}),
      revision: revision,
      expiresAt: DateTime.parse(wireString(json['expires_at'])),
      token: token is String ? token : null,
    );
  }

  final String challengeId;
  final String status;
  final int revision;
  final DateTime expiresAt;
  final String? token;
}

final class AccountCeilingsRead {
  const AccountCeilingsRead({
    required this.assignRoleIds,
    required this.manageAccountRoleIds,
    required this.manageUnassignedAccounts,
  });

  factory AccountCeilingsRead.fromJson(Object? value) {
    final json = wireObject(value);
    final assign = json['assign_role_ids'];
    final manage = json['manage_account_role_ids'];
    if (assign is! List<Object?> || manage is! List<Object?>) {
      throw const FormatException('Invalid account ceilings');
    }
    return AccountCeilingsRead(
      assignRoleIds: List.unmodifiable(assign.map(wireUuid)),
      manageAccountRoleIds: List.unmodifiable(manage.map(wireUuid)),
      manageUnassignedAccounts: _flag(json['manage_unassigned_accounts']),
    );
  }

  final List<String> assignRoleIds;
  final List<String> manageAccountRoleIds;
  final bool manageUnassignedAccounts;
}

final class MenuRead {
  const MenuRead({
    required this.id,
    required this.code,
    required this.audience,
    required this.routeKey,
    required this.componentKey,
    required this.parentMenuId,
    required this.title,
    required this.iconKey,
    required this.sortOrder,
    required this.permissionMatch,
    required this.enabled,
    required this.floor,
    required this.permissionCodes,
    required this.revision,
  });

  factory MenuRead.fromJson(Object? value) {
    final json = wireObject(value);
    final route = json['route_key'];
    final component = json['component_key'];
    final parent = json['parent_menu_id'];
    final icon = json['icon_key'];
    final floor = json['floor'];
    final extras = json['permission_codes'];
    if (route != null && route is! String) throw const FormatException('Invalid menu route');
    if (component != null && component is! String) {
      throw const FormatException('Invalid menu component');
    }
    if (parent != null && parent is! String) throw const FormatException('Invalid menu parent');
    if (icon != null && icon is! String) throw const FormatException('Invalid menu icon');
    if (floor is! List<Object?> || extras is! List<Object?>) {
      throw const FormatException('Invalid menu permissions');
    }
    return MenuRead(
      id: wireUuid(json['id']),
      code: wireString(json['code']),
      audience: _choice(json['audience'], const {'client', 'admin'}),
      routeKey: route == null ? null : wireString(route),
      componentKey: component == null ? null : wireString(component),
      parentMenuId: parent == null ? null : wireUuid(parent),
      title: wireString(json['title']),
      iconKey: icon == null ? null : wireString(icon),
      sortOrder: _count(json['sort_order']),
      permissionMatch: _choice(json['permission_match'], const {'all', 'any'}),
      enabled: _flag(json['enabled']),
      floor: List.unmodifiable(floor.map(wireString)),
      permissionCodes: List.unmodifiable(extras.map(wireString)),
      revision: _revision(json['revision']),
    );
  }

  static List<MenuRead> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Invalid menus');
    return List.unmodifiable(value.map(MenuRead.fromJson));
  }

  final String id;
  final String code;
  final String audience;
  final String? routeKey;
  final String? componentKey;
  final String? parentMenuId;
  final String title;
  final String? iconKey;
  final int sortOrder;
  final String permissionMatch;
  final bool enabled;
  final List<String> floor;
  final List<String> permissionCodes;
  final int revision;
}

final class MenuCatalogPage {
  const MenuCatalogPage({
    required this.code,
    required this.audience,
    required this.routeKey,
    required this.componentKey,
    required this.floor,
    required this.iconKey,
    required this.title,
    required this.sortOrder,
  });

  factory MenuCatalogPage.fromJson(Object? value) {
    final json = wireObject(value);
    final floor = json['floor'];
    if (floor is! List<Object?>) throw const FormatException('Invalid menu catalog');
    return MenuCatalogPage(
      code: wireString(json['code']),
      audience: _choice(json['audience'], const {'client', 'admin'}),
      routeKey: wireString(json['route_key']),
      componentKey: wireString(json['component_key']),
      floor: List.unmodifiable(floor.map(wireString)),
      iconKey: wireString(json['icon_key']),
      title: wireString(json['title']),
      sortOrder: _count(json['sort_order']),
    );
  }

  final String code;
  final String audience;
  final String routeKey;
  final String componentKey;
  final List<String> floor;
  final String iconKey;
  final String title;
  final int sortOrder;
}

final class MenuPermissionChoice {
  const MenuPermissionChoice({required this.code, required this.audience});

  factory MenuPermissionChoice.fromJson(Object? value) {
    final json = wireObject(value);
    return MenuPermissionChoice(
      code: wireString(json['code']),
      audience: _choice(json['audience'], const {'client', 'admin'}),
    );
  }

  final String code;
  final String audience;
}

final class MenuCatalogRead {
  const MenuCatalogRead({required this.pages, required this.icons, required this.permissionCodes});

  factory MenuCatalogRead.fromJson(Object? value) {
    final json = wireObject(value);
    final pages = json['pages'];
    final icons = json['icons'];
    final codes = json['permission_codes'];
    if (pages is! List<Object?> || icons is! List<Object?> || codes is! List<Object?>) {
      throw const FormatException('Invalid menu catalog');
    }
    return MenuCatalogRead(
      pages: List.unmodifiable(pages.map(MenuCatalogPage.fromJson)),
      icons: List.unmodifiable(icons.map(wireString)),
      permissionCodes: List.unmodifiable(codes.map(MenuPermissionChoice.fromJson)),
    );
  }

  final List<MenuCatalogPage> pages;
  final List<String> icons;
  final List<MenuPermissionChoice> permissionCodes;
}

final class MenuPreviewRead {
  const MenuPreviewRead({required this.navigation});

  factory MenuPreviewRead.fromJson(Object? value) {
    final json = wireObject(value);
    final navigation = json['navigation'];
    if (navigation is! List<Object?>) throw const FormatException('Invalid menu preview');
    return MenuPreviewRead(navigation: List.unmodifiable(navigation.map(NavigationItem.fromJson)));
  }

  final List<NavigationItem> navigation;
}

final class MenuWriteResult {
  const MenuWriteResult({
    required this.authorizationRevision,
    required this.auditId,
    required this.affectedCount,
    required this.menus,
  });

  factory MenuWriteResult.fromJson(Object? value) {
    final json = wireObject(value);
    final audit = json['audit_id'];
    final menus = json['menus'];
    if (audit != null && audit is! String) throw const FormatException('Invalid menu audit');
    if (menus is! List<Object?>) throw const FormatException('Invalid menus');
    return MenuWriteResult(
      authorizationRevision: _revision(json['authorization_revision']),
      auditId: audit == null ? null : wireUuid(audit),
      affectedCount: _count(json['affected_count']),
      menus: List.unmodifiable(menus.map(MenuRead.fromJson)),
    );
  }

  final int authorizationRevision;
  final String? auditId;
  final int affectedCount;
  final List<MenuRead> menus;
}

final class AccountWriteResult {
  const AccountWriteResult({
    required this.userId,
    required this.revision,
    required this.authorizationRevision,
    required this.auditId,
    required this.affectedCount,
  });

  factory AccountWriteResult.fromJson(Object? value) {
    final json = wireObject(value);
    final audit = json['audit_id'];
    if (audit != null && audit is! String) throw const FormatException('Invalid audit id');
    return AccountWriteResult(
      userId: wireUuid(json['user_id']),
      revision: _revision(json['revision']),
      authorizationRevision: _revision(json['authorization_revision']),
      auditId: audit == null ? null : wireUuid(audit),
      affectedCount: _count(json['affected_count']),
    );
  }

  final String userId;
  final int revision;
  final int authorizationRevision;
  final String? auditId;
  final int affectedCount;
}

final class GovernanceSummaryRead {
  const GovernanceSummaryRead({
    required this.accountsActive,
    required this.accountsPending,
    required this.accountsDisabled,
    required this.approvalsPending,
    required this.rolesEnabled,
    required this.authorizationRevision,
    required this.openManualRecoveries,
  });

  factory GovernanceSummaryRead.fromJson(Object? value) {
    final json = wireObject(value);
    return GovernanceSummaryRead(
      accountsActive: _count(json['accounts_active']),
      accountsPending: _count(json['accounts_pending']),
      accountsDisabled: _count(json['accounts_disabled']),
      approvalsPending: _count(json['approvals_pending']),
      rolesEnabled: _count(json['roles_enabled']),
      authorizationRevision: _revision(json['authorization_revision']),
      openManualRecoveries: _count(json['open_manual_recoveries']),
    );
  }

  final int accountsActive;
  final int accountsPending;
  final int accountsDisabled;
  final int approvalsPending;
  final int rolesEnabled;
  final int authorizationRevision;
  final int openManualRecoveries;
}

final class AuditEventRead {
  const AuditEventRead({
    required this.eventId,
    required this.action,
    required this.actor,
    required this.actorUserId,
    required this.audience,
    required this.permissionCode,
    required this.targetType,
    required this.targetId,
    required this.targetCode,
    required this.result,
    required this.reasonCode,
    required this.authorizationRevision,
    required this.requestId,
    required this.operationId,
    required this.changeSummary,
    required this.createdAt,
  });

  factory AuditEventRead.fromJson(Object? value) {
    final json = wireObject(value);
    final summary = json['change_summary'];
    if (summary != null && summary is! Map) {
      throw const FormatException('Invalid audit summary');
    }
    final clean = <String, String>{};
    if (summary is Map) {
      for (final entry in summary.entries) {
        final key = entry.key;
        final item = entry.value;
        if (key is! String || item is! String) {
          throw const FormatException('Invalid audit summary');
        }
        clean[key] = item;
      }
    }
    final actorUser = json['actor_user_id'];
    final audience = json['audience'];
    final permission = json['permission_code'];
    final targetType = json['target_type'];
    final targetId = json['target_id'];
    final targetCode = json['target_code'];
    final result = json['result'];
    final reason = json['reason_code'];
    final requestId = json['request_id'];
    final operationId = json['operation_id'];
    return AuditEventRead(
      eventId: wireUuid(json['event_id']),
      action: wireString(json['action']),
      actor: wireString(json['actor']),
      actorUserId: actorUser == null ? null : wireUuid(actorUser),
      audience: audience == null ? null : _choice(audience, const {'client', 'admin'}),
      permissionCode: permission == null ? null : wireString(permission),
      targetType: targetType == null ? null : wireString(targetType),
      targetId: targetId == null ? null : wireUuid(targetId),
      targetCode: targetCode == null ? null : wireString(targetCode),
      result: result == null
          ? null
          : _choice(result, const {'accepted', 'committed', 'denied', 'failed'}),
      reasonCode: reason == null ? null : wireString(reason),
      authorizationRevision: _revision(json['authorization_revision']),
      requestId: requestId == null ? null : wireUuid(requestId),
      operationId: operationId == null ? null : wireUuid(operationId),
      changeSummary: clean.isEmpty ? null : Map.unmodifiable(clean),
      createdAt: DateTime.parse(wireString(json['created_at'])),
    );
  }

  final String eventId;
  final String action;
  final String actor;
  final String? actorUserId;
  final String? audience;
  final String? permissionCode;
  final String? targetType;
  final String? targetId;
  final String? targetCode;
  final String? result;
  final String? reasonCode;
  final int authorizationRevision;
  final String? requestId;
  final String? operationId;
  final Map<String, String>? changeSummary;
  final DateTime createdAt;
}

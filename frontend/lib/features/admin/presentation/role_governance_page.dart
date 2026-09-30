import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/features/admin/presentation/governance_overview_page.dart';
import 'package:haruka/generated/api_catalog.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/identified.dart';

Widget _closedGovernanceDialog(BuildContext context) {
  final strings = AppLocalizations.of(context);
  return AlertDialog(
    content: Text(strings.authNoAdminPermission),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
    ],
  );
}

/// Live role, grant, inheritance, and ceiling editor inside the confirmed admin shell.
class AdminRoleGovernance extends StatefulWidget {
  const AdminRoleGovernance({required this.auth, super.key});

  final AuthController auth;

  @override
  State<AdminRoleGovernance> createState() => _AdminRoleGovernanceState();
}

class _AdminRoleScope {
  const _AdminRoleScope({
    required this.auth,
    required this.endpoint,
    required this.instanceId,
    required this.userId,
    required this.sessionRef,
    required this.actionEpoch,
    required this.userVersion,
    required this.securityEpoch,
    required this.rights,
  });

  final AuthController auth;
  final Uri endpoint;
  final String instanceId;
  final String userId;
  final String sessionRef;
  final int actionEpoch;
  final int userVersion;
  final int? securityEpoch;
  final String rights;

  static _AdminRoleScope? capture(AuthController auth) {
    final access = auth.access;
    if (!auth.isAuthenticated || !auth.admin || access == null || access.audience != 'admin') {
      return null;
    }
    final rights = [
      'admin.role.read',
      'admin.role.create',
      'admin.role.update',
      'admin.role.delete',
      'admin.role.permission.assign',
      'admin.permission.read',
      'admin.grant_boundary.read',
      'admin.grant_boundary.update',
      'admin.protected_role.manage',
    ].map((code) => auth.access?.allows(code) == true ? code : '').join('|');
    return _AdminRoleScope(
      auth: auth,
      endpoint: auth.repository.api.endpoint,
      instanceId: auth.boundInstanceId,
      userId: access.userId,
      sessionRef: access.sessionRef,
      actionEpoch: auth.actionEpoch,
      userVersion: access.authzVersion.user,
      securityEpoch: access.securityEpoch,
      rights: rights,
    );
  }

  bool allows(String code) => rights.split('|').contains(code);

  bool same(_AdminRoleScope? other) =>
      other != null &&
      identical(auth, other.auth) &&
      endpoint == other.endpoint &&
      instanceId == other.instanceId &&
      userId == other.userId &&
      sessionRef == other.sessionRef &&
      actionEpoch == other.actionEpoch &&
      userVersion == other.userVersion &&
      securityEpoch == other.securityEpoch &&
      rights == other.rights;

  bool get isCurrent {
    final access = auth.access;
    final next = capture(auth);
    return next != null &&
        next.endpoint == endpoint &&
        next.instanceId == instanceId &&
        access?.instanceId == instanceId &&
        next.userId == userId &&
        next.sessionRef == sessionRef &&
        next.actionEpoch == actionEpoch &&
        next.userVersion == userVersion &&
        next.securityEpoch == securityEpoch &&
        next.rights == rights &&
        auth.repository.api.endpoint == endpoint &&
        auth.boundInstanceId == instanceId;
  }
}

class _AdminRoleGovernanceState extends State<AdminRoleGovernance> {
  _AdminRoleScope? _scope;
  List<RoleRead>? _roles;
  List<PermissionCatalogRead>? _catalog;
  final Map<String, List<GrantBoundaryRead>> _boundaryCache = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    _capture(load: true);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    final next = _AdminRoleScope.capture(widget.auth);
    if (_scope?.same(next) ?? next == null) return;
    setState(() => _capture(load: true));
  }

  void _capture({required bool load}) {
    final scope = _AdminRoleScope.capture(widget.auth);
    _scope = scope;
    _roles = null;
    _catalog = null;
    _boundaryCache.clear();
    _error = null;
    if (load && scope != null && scope.allows('admin.role.read')) {
      unawaited(_load(scope));
    }
  }

  Future<void> _load(_AdminRoleScope scope) async {
    try {
      final roles = await widget.auth.adminRoles();
      final catalog = scope.allows('admin.permission.read')
          ? await widget.auth.adminPermissions()
          : null;
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _roles = roles;
        _catalog = catalog;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted || !scope.isCurrent) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  void _replace(RoleRead role) {
    final roles = _roles;
    final scope = _scope;
    if (roles == null || scope == null || !scope.isCurrent || !mounted) return;
    setState(() {
      _roles = [for (final item in roles) item.id == role.id ? role : item];
    });
  }

  void _insert(RoleRead role) {
    final roles = _roles;
    final scope = _scope;
    if (roles == null || scope == null || !scope.isCurrent || !mounted) return;
    final next = [...roles, role]..sort((left, right) => left.code.compareTo(right.code));
    setState(() => _roles = next);
  }

  void _remove(String roleId) {
    final roles = _roles;
    final scope = _scope;
    if (roles == null || scope == null || !scope.isCurrent || !mounted) return;
    setState(() {
      _roles = [
        for (final item in roles)
          if (item.id != roleId) item,
      ];
      _boundaryCache.remove(roleId);
    });
  }

  Future<void> _preview(RoleRead role) async {
    final scope = _scope;
    final roles = _roles;
    if (scope == null || roles == null || !scope.isCurrent) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _RoleEditorDialog(
          scope: scope,
          role: role,
          roles: roles,
          catalog: _catalog,
          cachedBoundaries: _boundaryCache[role.id],
          boundariesKnown: _boundaryCache.containsKey(role.id),
          onRole: _replace,
          onDeleted: () => _remove(role.id),
          onBoundaries: (boundaries) {
            if (!mounted || !scope.isCurrent) return;
            setState(() => _boundaryCache[role.id] = boundaries);
          },
        ),
      ),
    );
  }

  Future<void> _create() async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _RoleCreateDialog(scope: scope, onCreated: _insert),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = _scope;
    if (scope == null || !scope.isCurrent || !scope.allows('admin.role.read')) {
      return Text(strings.authNoAdminPermission);
    }
    final roles = _roles;
    return Identified(
      id: UiTestIds.adminRolesPage,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (scope.allows('admin.role.create'))
                Identified(
                  id: UiTestIds.adminRoleCreate,
                  merge: true,
                  child: FilledButton(onPressed: _create, child: Text(strings.adminRoleCreate)),
                ),
              if (scope.allows('admin.role.create')) const SizedBox(height: 16),
              if (_error != null)
                _RoleCard(child: Text(_error!))
              else if (roles == null)
                const _RoleCard(child: CircularProgressIndicator())
              else if (roles.isEmpty)
                _RoleCard(child: Text(strings.adminRoleEmpty))
              else
                _roleTable(context, roles, _catalog, _preview),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: HarukaColors.of(context).content,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(26), child: child),
  );
}

Widget _roleTable(
  BuildContext context,
  List<RoleRead> roles,
  List<PermissionCatalogRead>? catalog,
  Future<void> Function(RoleRead role) onPreview,
) {
  final strings = AppLocalizations.of(context);
  return _RoleCard(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            columns: [
              DataColumn(label: Text(strings.mockAdminRoleColumn)),
              DataColumn(label: Text(strings.mockAdminAudienceColumn)),
              DataColumn(label: Text(strings.mockAdminMembersColumn)),
              DataColumn(label: Text(strings.mockAdminStatusColumn)),
              const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final role in roles)
                DataRow(
                  cells: [
                    DataCell(Text(role.name)),
                    DataCell(Text(_audienceLabel(strings, role, catalog))),
                    DataCell(Text('${role.memberCount}')),
                    DataCell(_RoleTag(_statusLabel(strings, role), warning: role.protected)),
                    DataCell(
                      TextButton(
                        onPressed: () => onPreview(role),
                        child: Text(strings.mockAdminPreview),
                      ),
                    ),
                  ],
                ),
            ],
            dataRowMinHeight: 65,
            dataRowMaxHeight: 77,
            headingRowHeight: 55,
            horizontalMargin: 21,
            columnSpacing: 56,
            dividerThickness: .7,
            headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

class _RoleTag extends StatelessWidget {
  const _RoleTag(this.label, {this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? HarukaColors.of(context).warning
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _audienceLabel(
  AppLocalizations strings,
  RoleRead role,
  List<PermissionCatalogRead>? catalog,
) {
  final byCode = {for (final item in catalog ?? const <PermissionCatalogRead>[]) item.code: item};
  final audiences = <String>{
    for (final grant in role.grants)
      if (byCode[grant.permissionCode] != null) byCode[grant.permissionCode]!.audience,
  };
  final client = audiences.contains('client');
  final admin = audiences.contains('admin');
  if (client && admin) return '${strings.mockAdminClientAudience} · ${strings.mockAdminAudience}';
  if (client) return strings.mockAdminClientAudience;
  if (admin) return strings.mockAdminAudience;
  return '—';
}

String _statusLabel(AppLocalizations strings, RoleRead role) {
  if (role.protected) return strings.mockAdminProtected;
  if (!role.enabled) return strings.adminRoleDisabled;
  return strings.mockAdminNormal;
}

final _roleCode = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

class _GrantDraft {
  _GrantDraft({required this.effect, required this.both});

  String? effect;
  bool both;
}

Map<String, _GrantDraft> _grantDrafts(List<RoleGrantRead> grants) {
  final grouped = <String, Set<String>>{};
  for (final grant in grants) {
    grouped.putIfAbsent(grant.permissionCode, () => {}).add(grant.effect);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: _GrantDraft(
        effect: entry.value.contains('deny') ? 'deny' : 'allow',
        both: entry.value.contains('allow') && entry.value.contains('deny'),
      ),
  };
}

String _grantSignature(Iterable<RoleGrantRead> grants) {
  final keys = [
    for (final grant in grants) '${grant.permissionCode}|${grant.effect}|${grant.dataScope}',
  ]..sort();
  return keys.join('\n');
}

class _RoleEditorDialog extends StatefulWidget {
  const _RoleEditorDialog({
    required this.scope,
    required this.role,
    required this.roles,
    required this.catalog,
    required this.cachedBoundaries,
    required this.boundariesKnown,
    required this.onRole,
    required this.onDeleted,
    required this.onBoundaries,
  });

  final _AdminRoleScope scope;
  final RoleRead role;
  final List<RoleRead> roles;
  final List<PermissionCatalogRead>? catalog;
  final List<GrantBoundaryRead>? cachedBoundaries;
  final bool boundariesKnown;
  final ValueChanged<RoleRead> onRole;
  final VoidCallback onDeleted;
  final ValueChanged<List<GrantBoundaryRead>> onBoundaries;

  @override
  State<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<_RoleEditorDialog> {
  late RoleRead _role;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late int _revision;
  late bool _enabled;
  late Set<String> _parents;
  late Map<String, _GrantDraft> _grants;
  List<GrantBoundaryRead>? _boundaries;
  bool _busy = false;
  bool _boundaryLoading = false;
  String? _message;
  String? _boundaryError;
  String? _affected;
  String _boundaryKind = 'assign_role';
  String? _boundaryTarget;
  String? _boundaryPermission;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _name = TextEditingController(text: _role.name);
    _description = TextEditingController(text: _role.description ?? '');
    _revision = _role.revision;
    _enabled = _role.enabled;
    _parents = {for (final parent in _role.parents) parent.roleId};
    _grants = _grantDrafts(_role.grants);
    _boundaries = widget.boundariesKnown ? widget.cachedBoundaries : null;
    if (!widget.boundariesKnown && widget.scope.allows('admin.grant_boundary.read')) {
      unawaited(_loadBoundaries());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _current => mounted && widget.scope.isCurrent;

  bool _canWrite(String code) =>
      widget.scope.allows(code) &&
      (!_role.protected || widget.scope.allows('admin.protected_role.manage'));

  void _fail(Object error) {
    if (!_current) return;
    final code = error is ApiFailure ? error.code : 'INVALID_RESPONSE';
    setState(() => _message = ApiCatalog.message(AppLocalizations.of(context), code));
  }

  void _publish(RoleRead role, AuthorizationWriteResult result) {
    _role = role;
    _revision = result.revision;
    _affected = '${AppLocalizations.of(context).adminRoleAffected} ${result.affectedCount}';
    widget.onRole(role);
  }

  Future<void> _loadBoundaries() async {
    setState(() {
      _boundaryLoading = true;
      _boundaryError = null;
    });
    try {
      final boundaries = await widget.scope.auth.adminGrantBoundaries(_role.id);
      if (!_current) return;
      setState(() => _boundaries = boundaries);
      widget.onBoundaries(boundaries);
    } on ApiFailure catch (error) {
      if (!_current) return;
      setState(() => _boundaryError = ApiCatalog.message(AppLocalizations.of(context), error.code));
    } finally {
      if (mounted) setState(() => _boundaryLoading = false);
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final fresh = await widget.scope.auth.adminRole(_role.id);
      if (!_current) return;
      setState(() {
        _role = fresh;
        _name.text = fresh.name;
        _description.text = fresh.description ?? '';
        _revision = fresh.revision;
        _enabled = fresh.enabled;
        _parents = {for (final parent in fresh.parents) parent.roleId};
        _grants = _grantDrafts(fresh.grants);
        _affected = null;
      });
      widget.onRole(fresh);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMetadata() async {
    if (_busy || !_canWrite('admin.role.update')) return;
    final strings = AppLocalizations.of(context);
    final name = _name.text.trim();
    final description = _description.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _message = strings.adminRoleNameInvalid);
      return;
    }
    if (description.length > 2000) {
      setState(() => _message = strings.adminRoleDescriptionInvalid);
      return;
    }
    final stored = description.isEmpty ? null : description;
    if (name == _role.name && stored == _role.description) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.updateAdminRole(_role.id, _revision, name, stored);
      if (!_current) return;
      setState(() {
        _publish(
          _role.copy(
            name: name,
            description: stored,
            clearDescription: stored == null,
            revision: result.revision,
          ),
          result,
        );
      });
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEnabled(bool enabled) async {
    if (_busy || !_canWrite('admin.role.update') || enabled == _enabled) return;
    final previous = _enabled;
    setState(() {
      _enabled = enabled;
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.setAdminRoleEnabled(_role.id, _revision, enabled);
      if (!_current) return;
      setState(() {
        _publish(_role.copy(enabled: enabled, revision: result.revision), result);
      });
    } on ApiFailure catch (error) {
      if (_current) setState(() => _enabled = previous);
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<RoleGrantRead> _editedGrants() {
    final catalog = widget.catalog ?? const <PermissionCatalogRead>[];
    final known = {for (final item in catalog) item.code};
    final result = <RoleGrantRead>[];
    for (final item in catalog) {
      final draft = _grants[item.code];
      if (draft == null ||
          (!item.enabled && !_role.grants.any((grant) => grant.permissionCode == item.code))) {
        continue;
      }
      if (draft.both) {
        result
          ..add(
            RoleGrantRead(permissionCode: item.code, effect: 'allow', dataScope: item.dataScope),
          )
          ..add(
            RoleGrantRead(permissionCode: item.code, effect: 'deny', dataScope: item.dataScope),
          );
      } else if (draft.effect != null) {
        result.add(
          RoleGrantRead(
            permissionCode: item.code,
            effect: draft.effect!,
            dataScope: item.dataScope,
          ),
        );
      }
    }
    result.addAll(_role.grants.where((grant) => !known.contains(grant.permissionCode)));
    return result;
  }

  Future<void> _saveGrants() async {
    if (_busy || !_canWrite('admin.role.permission.assign') || widget.catalog == null) return;
    final grants = _editedGrants();
    if (_grantSignature(grants) == _grantSignature(_role.grants)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.replaceAdminRoleGrants(_role.id, _revision, grants);
      if (!_current) return;
      setState(() => _publish(_role.copy(grants: grants, revision: result.revision), result));
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveParents() async {
    if (_busy || !_canWrite('admin.role.permission.assign')) return;
    final current = {for (final parent in _role.parents) parent.roleId};
    if (current.length == _parents.length && current.containsAll(_parents)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.replaceAdminRoleParents(
        _role.id,
        _revision,
        _parents.toList(),
      );
      if (!_current) return;
      final parents = [
        for (final item in widget.roles)
          if (_parents.contains(item.id))
            RoleParentRead(roleId: item.id, code: item.code, enabled: item.enabled),
      ];
      setState(() => _publish(_role.copy(parents: parents, revision: result.revision), result));
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addBoundary() {
    final current = _boundaries;
    if (current == null || current.length >= 256) return;
    final GrantBoundaryRead next;
    switch (_boundaryKind) {
      case 'assign_permission':
        PermissionCatalogRead? selected;
        for (final item in widget.catalog ?? const <PermissionCatalogRead>[]) {
          if (item.code == _boundaryPermission) selected = item;
        }
        if (selected == null) return;
        next = GrantBoundaryRead(
          boundaryKind: 'assign_permission',
          targetRoleId: null,
          permissionCode: selected.code,
          dataScope: selected.dataScope,
          revision: 1,
        );
      case 'manage_unassigned_accounts':
        if (current.any((item) => item.boundaryKind == 'manage_unassigned_accounts')) return;
        next = const GrantBoundaryRead(
          boundaryKind: 'manage_unassigned_accounts',
          targetRoleId: null,
          permissionCode: null,
          dataScope: null,
          revision: 1,
        );
      case 'assign_role' || 'manage_account_role':
        if (_boundaryTarget == null) return;
        next = GrantBoundaryRead(
          boundaryKind: _boundaryKind,
          targetRoleId: _boundaryTarget,
          permissionCode: null,
          dataScope: null,
          revision: 1,
        );
      default:
        return;
    }
    final duplicate = current.any(
      (item) =>
          item.boundaryKind == next.boundaryKind &&
          item.targetRoleId == next.targetRoleId &&
          item.permissionCode == next.permissionCode &&
          item.dataScope == next.dataScope,
    );
    if (duplicate) return;
    setState(() => _boundaries = [...current, next]);
  }

  Future<void> _saveBoundaries() async {
    final boundaries = _boundaries;
    if (_busy || boundaries == null || !_canWrite('admin.grant_boundary.update')) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.replaceAdminGrantBoundaries(
        _role.id,
        _revision,
        boundaries,
      );
      if (!_current) return;
      setState(() {
        _publish(_role.copy(revision: result.revision), result);
      });
      widget.onBoundaries(boundaries);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || !_canWrite('admin.role.delete')) return;
    final strings = AppLocalizations.of(context);
    final confirmed = await showHarukaDialog<bool>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: widget.scope.auth,
        current: () => widget.scope.isCurrent,
        child: AlertDialog(
          title: Text(strings.adminRoleDelete),
          content: Text(strings.adminRoleDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.mockAdminClose),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.adminRoleDelete),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !_current) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.scope.auth.deleteAdminRole(_role.id, _revision);
      if (!_current) return;
      widget.onDeleted();
      if (mounted) Navigator.of(context).pop();
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    final catalog = widget.catalog;
    final canUpdate = _canWrite('admin.role.update') && !_busy;
    final canAssign = _canWrite('admin.role.permission.assign') && !_busy;
    final canBoundaries = _canWrite('admin.grant_boundary.update') && !_busy;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Identified(
      id: UiTestIds.adminRoleDialog,
      child: AlertDialog(
        title: Text(strings.mockAdminSummary),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_role.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${strings.adminRoleCode} ${_role.code}'),
                const SizedBox(height: 8),
                _RoleTag(_statusLabel(strings, _role), warning: _role.protected),
                const SizedBox(height: 8),
                Text('${strings.mockAdminMembersColumn} ${_role.memberCount}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: canUpdate,
                  decoration: InputDecoration(labelText: strings.adminRoleName),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  enabled: canUpdate,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: strings.adminRoleDescription),
                ),
                const SizedBox(height: 12),
                Identified(
                  id: UiTestIds.adminRoleSave,
                  merge: true,
                  child: FilledButton(
                    onPressed: canUpdate ? _saveMetadata : null,
                    child: Text(strings.adminRoleSaveMetadata),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(strings.adminRoleEnabled)),
                    Switch(value: _enabled, onChanged: canUpdate ? _saveEnabled : null),
                  ],
                ),
                const SizedBox(height: 16),
                Text(strings.adminRoleParents, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(strings.adminRoleParentHint),
                for (final item in widget.roles)
                  if (item.id != _role.id)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _parents.contains(item.id),
                      title: Text(item.name),
                      onChanged:
                          !canAssign || (_parents.length >= 32 && !_parents.contains(item.id))
                          ? null
                          : (value) => setState(() {
                              if (value ?? false) {
                                _parents.add(item.id);
                              } else {
                                _parents.remove(item.id);
                              }
                            }),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: canAssign ? _saveParents : null,
                    child: Text(strings.adminRoleSaveParents),
                  ),
                ),
                const SizedBox(height: 8),
                Text(strings.adminRoleGrants, style: Theme.of(context).textTheme.titleSmall),
                if (catalog == null)
                  Text(strings.adminRoleNoCatalog)
                else
                  for (final audience in const ['client', 'admin']) ...[
                    const SizedBox(height: 8),
                    Text(
                      audience == 'client'
                          ? strings.mockAdminClientAudience
                          : strings.mockAdminAudience,
                    ),
                    for (final item in catalog.where((entry) => entry.audience == audience))
                      if (item.enabled || _grants.containsKey(item.code))
                        Row(
                          children: [
                            Expanded(child: Text(item.code)),
                            DropdownButton<String>(
                              value: (_grants[item.code]?.both ?? false)
                                  ? 'both'
                                  : (_grants[item.code]?.effect ?? 'unset'),
                              items: [
                                DropdownMenuItem(
                                  value: 'unset',
                                  child: Text(strings.adminRoleUnset),
                                ),
                                DropdownMenuItem(
                                  value: 'allow',
                                  child: Text(strings.adminRoleAllow),
                                ),
                                DropdownMenuItem(value: 'deny', child: Text(strings.adminRoleDeny)),
                                if (_grants[item.code]?.both ?? false)
                                  DropdownMenuItem(
                                    value: 'both',
                                    child: Text(strings.adminRoleBothEffects),
                                  ),
                              ],
                              onChanged: canAssign
                                  ? (value) => setState(() {
                                      if (value == null || value == 'unset') {
                                        _grants.remove(item.code);
                                      } else if (value == 'both') {
                                        _grants[item.code] = _GrantDraft(
                                          effect: 'deny',
                                          both: true,
                                        );
                                      } else {
                                        _grants[item.code] = _GrantDraft(
                                          effect: value,
                                          both: false,
                                        );
                                      }
                                    })
                                  : null,
                            ),
                          ],
                        ),
                  ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: canAssign && catalog != null ? _saveGrants : null,
                    child: Text(strings.adminRoleSaveGrants),
                  ),
                ),
                if (widget.scope.allows('admin.grant_boundary.read')) ...[
                  const SizedBox(height: 8),
                  Text(strings.adminRoleBoundaries, style: Theme.of(context).textTheme.titleSmall),
                  if (_boundaryLoading) const CircularProgressIndicator(),
                  if (_boundaryError != null) Text(_boundaryError!),
                  for (final boundary in _boundaries ?? const <GrantBoundaryRead>[])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_boundaryLabel(strings, boundary)),
                      trailing: IconButton(
                        onPressed: canBoundaries
                            ? () => setState(
                                () => _boundaries = [
                                  for (final item in _boundaries!)
                                    if (!identical(item, boundary)) item,
                                ],
                              )
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  if (canBoundaries && _boundaries != null) ...[
                    DropdownButton<String>(
                      value: _boundaryKind,
                      items: [
                        DropdownMenuItem(
                          value: 'assign_role',
                          child: Text(strings.adminRoleAssignRole),
                        ),
                        DropdownMenuItem(
                          value: 'assign_permission',
                          child: Text(strings.adminRoleAssignPermission),
                        ),
                        DropdownMenuItem(
                          value: 'manage_account_role',
                          child: Text(strings.adminRoleManageRole),
                        ),
                        DropdownMenuItem(
                          value: 'manage_unassigned_accounts',
                          child: Text(strings.adminRoleUnassigned),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _boundaryKind = value ?? 'assign_role';
                        _boundaryTarget = null;
                        _boundaryPermission = null;
                      }),
                    ),
                    if (_boundaryKind == 'assign_permission')
                      DropdownButton<String>(
                        value: _boundaryPermission,
                        hint: Text(strings.adminRoleAssignPermission),
                        items: [
                          for (final item in widget.catalog ?? const <PermissionCatalogRead>[])
                            DropdownMenuItem(value: item.code, child: Text(item.code)),
                        ],
                        onChanged: (value) => setState(() => _boundaryPermission = value),
                      ),
                    if (_boundaryKind == 'assign_role' || _boundaryKind == 'manage_account_role')
                      DropdownButton<String>(
                        value: _boundaryTarget,
                        hint: Text(strings.mockAdminRoleColumn),
                        items: [
                          for (final item in widget.roles)
                            DropdownMenuItem(value: item.id, child: Text(item.name)),
                        ],
                        onChanged: (value) => setState(() => _boundaryTarget = value),
                      ),
                    TextButton(onPressed: _addBoundary, child: Text(strings.adminRoleAddBoundary)),
                    TextButton(
                      onPressed: _saveBoundaries,
                      child: Text(strings.adminRoleSaveBoundaries),
                    ),
                  ],
                ],
                if (_affected != null) ...[const SizedBox(height: 8), Text(_affected!)],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!),
                  if (_message == strings.apiRevisionConflict)
                    TextButton(
                      onPressed: _busy ? null : _reload,
                      child: Text(strings.adminRoleReload),
                    ),
                ],
                if (_canWrite('admin.role.delete')) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    child: Text(strings.adminRoleDelete),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
        ],
      ),
    );
  }
}

String _boundaryLabel(AppLocalizations strings, GrantBoundaryRead boundary) =>
    switch (boundary.boundaryKind) {
      'assign_role' => strings.adminRoleAssignRole,
      'assign_permission' => strings.adminRoleAssignPermission,
      'manage_account_role' => strings.adminRoleManageRole,
      _ => strings.adminRoleUnassigned,
    };

class _RoleCreateDialog extends StatefulWidget {
  const _RoleCreateDialog({required this.scope, required this.onCreated});

  final _AdminRoleScope scope;
  final ValueChanged<RoleRead> onCreated;

  @override
  State<_RoleCreateDialog> createState() => _RoleCreateDialogState();
}

class _RoleCreateDialogState extends State<_RoleCreateDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !widget.scope.allows('admin.role.create') || !widget.scope.isCurrent) return;
    final strings = AppLocalizations.of(context);
    final code = _code.text.trim();
    final name = _name.text.trim();
    final description = _description.text.trim();
    if (!_roleCode.hasMatch(code)) {
      setState(() => _message = strings.adminRoleCodeInvalid);
      return;
    }
    if (name.isEmpty || name.length > 100) {
      setState(() => _message = strings.adminRoleNameInvalid);
      return;
    }
    if (description.length > 2000) {
      setState(() => _message = strings.adminRoleDescriptionInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.scope.auth.createAdminRole(
        code,
        name,
        description.isEmpty ? null : description,
      );
      if (!mounted || !widget.scope.isCurrent) return;
      widget.onCreated(
        RoleRead(
          id: result.roleId,
          code: code,
          name: name,
          description: description.isEmpty ? null : description,
          protected: false,
          enabled: true,
          revision: result.revision,
          grants: const [],
          parents: const [],
          memberCount: 0,
        ),
      );
      Navigator.of(context).pop();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _message = ApiCatalog.message(strings, error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    return AlertDialog(
      title: Text(strings.adminRoleCreate),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              decoration: InputDecoration(labelText: strings.adminRoleCode),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: strings.adminRoleName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: InputDecoration(labelText: strings.adminRoleDescription),
            ),
            if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(strings.adminRoleCreate)),
      ],
    );
  }
}

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

/// Live account list inside the confirmed admin shell.
class AdminUserGovernance extends StatefulWidget {
  const AdminUserGovernance({required this.auth, super.key});

  final AuthController auth;

  @override
  State<AdminUserGovernance> createState() => _AdminUserGovernanceState();
}

class _AdminUserScope {
  const _AdminUserScope({
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

  static _AdminUserScope? capture(AuthController auth) {
    final access = auth.access;
    if (!auth.isAuthenticated || !auth.admin || access == null || access.audience != 'admin') {
      return null;
    }
    final rights = [
      'admin.user.read',
      'admin.user.create',
      'admin.user.update',
      'admin.user.enable',
      'admin.user.disable',
      'admin.user.approve',
      'admin.user.role.assign',
      'admin.role.read',
      'admin.session.read',
      'admin.session.revoke',
    ].map((code) => auth.access?.allows(code) == true ? code : '').join('|');
    return _AdminUserScope(
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

  bool same(_AdminUserScope? other) =>
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
    final next = capture(auth);
    return next != null &&
        next.endpoint == endpoint &&
        next.instanceId == instanceId &&
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

class _AdminUserGovernanceState extends State<AdminUserGovernance> {
  _AdminUserScope? _scope;
  List<GovernedAccountRead>? _accounts;
  List<RoleRead>? _roles;
  AccountCeilingsRead? _ceilings;
  final Map<String, List<AccountSessionRead>> _sessions = {};
  final Map<String, List<ManualRecoveryRead>> _recoveries = {};
  final TextEditingController _search = TextEditingController();
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
    _search.dispose();
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    final next = _AdminUserScope.capture(widget.auth);
    if (_scope?.same(next) ?? next == null) return;
    setState(() => _capture(load: true));
  }

  void _capture({required bool load}) {
    final scope = _AdminUserScope.capture(widget.auth);
    _scope = scope;
    _accounts = null;
    _roles = null;
    _ceilings = null;
    _sessions.clear();
    _recoveries.clear();
    _error = null;
    if (load && scope != null && scope.allows('admin.user.read')) {
      unawaited(_load(scope));
    }
  }

  Future<void> _load(_AdminUserScope scope) async {
    try {
      final accounts = await widget.auth.adminAccounts();
      final ceilings = await widget.auth.adminAccountCeilings();
      final roles = scope.allows('admin.role.read') ? await widget.auth.adminRoles() : null;
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _accounts = accounts;
        _ceilings = ceilings;
        _roles = roles;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted || !scope.isCurrent) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  void _replace(GovernedAccountRead account) {
    final accounts = _accounts;
    final scope = _scope;
    if (accounts == null || scope == null || !scope.isCurrent || !mounted) return;
    setState(() {
      _accounts = [for (final item in accounts) item.userId == account.userId ? account : item];
    });
  }

  void _insert(GovernedAccountRead account) {
    final accounts = _accounts;
    final scope = _scope;
    if (accounts == null || scope == null || !scope.isCurrent || !mounted) return;
    final next = [...accounts, account]..sort((left, right) => left.email.compareTo(right.email));
    setState(() => _accounts = next);
  }

  Future<void> _preview(GovernedAccountRead account) async {
    final scope = _scope;
    final accounts = _accounts;
    if (scope == null || accounts == null || !scope.isCurrent) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _AccountDialog(
          scope: scope,
          account: account,
          roles: _roles ?? const [],
          ceilings: _ceilings,
          cachedSessions: _sessions[account.userId],
          sessionsKnown: _sessions.containsKey(account.userId),
          cachedRecoveries: _recoveries[account.userId],
          recoveriesKnown: _recoveries.containsKey(account.userId),
          onAccount: _replace,
          onSessions: (sessions) {
            if (!mounted || !scope.isCurrent) return;
            setState(() => _sessions[account.userId] = sessions);
          },
          onRecoveries: (requests) {
            if (!mounted || !scope.isCurrent) return;
            setState(() => _recoveries[account.userId] = requests);
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
        child: _AccountCreateDialog(
          scope: scope,
          roles: _roles ?? const [],
          ceilings: _ceilings,
          onCreated: _insert,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = _scope;
    if (scope == null || !scope.isCurrent || !scope.allows('admin.user.read')) {
      return Text(strings.authNoAdminPermission);
    }
    final accounts = _accounts;
    final needle = _search.text.trim().toLowerCase();
    final visible = accounts?.where((account) {
      final name = account.displayName ?? '';
      return '${account.email} $name ${_statusLabel(strings, account)}'.toLowerCase().contains(
        needle,
      );
    }).toList();
    return Identified(
      id: UiTestIds.adminUsersPage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                strings.mockAdminUserList,
                style: Theme.of(context).textTheme.titleLarge,
              );
              final create = scope.allows('admin.user.create')
                  ? Identified(
                      id: UiTestIds.adminUserCreate,
                      merge: true,
                      child: FilledButton(onPressed: _create, child: Text(strings.adminUserCreate)),
                    )
                  : null;
              final search = TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: strings.mockAdminSearchUsers,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              );
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: title),
                        ?create,
                      ],
                    ),
                    const SizedBox(height: 12),
                    search,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  ?create,
                  if (create != null) const SizedBox(width: 12),
                  SizedBox(width: 260, child: search),
                ],
              );
            },
          ),
          const SizedBox(height: 17),
          if (_error != null)
            _UserCard(child: Text(_error!))
          else if (visible == null)
            const _UserCard(child: CircularProgressIndicator())
          else if (visible.isEmpty)
            _UserCard(child: Text(strings.adminUserEmpty))
          else
            _userTable(context, visible, _preview),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: HarukaColors.of(context).content,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(26), child: child),
  );
}

class _UserTag extends StatelessWidget {
  const _UserTag(this.label, {required this.positive, required this.warning});

  final String label;
  final bool positive;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = HarukaColors.of(context);
    final color = positive
        ? colors.positive
        : warning
        ? colors.warning
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

Widget _userTable(
  BuildContext context,
  List<GovernedAccountRead> accounts,
  Future<void> Function(GovernedAccountRead account) onPreview,
) {
  final strings = AppLocalizations.of(context);
  return _UserCard(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            columns: [
              DataColumn(label: Text(strings.mockAdminUserColumn)),
              DataColumn(label: Text(strings.mockAdminEmailColumn)),
              DataColumn(label: Text(strings.mockAdminStatusColumn)),
              DataColumn(label: Text(strings.mockAdminAudienceColumn)),
              DataColumn(label: Text(strings.mockAdminActionColumn)),
            ],
            rows: [
              for (final account in accounts)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        account.displayName?.isNotEmpty == true
                            ? account.displayName!
                            : account.email,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text(account.email)),
                    DataCell(
                      _UserTag(
                        _statusLabel(strings, account),
                        positive: account.status == 'active' && !account.locked,
                        warning: account.status != 'active' || account.locked,
                      ),
                    ),
                    DataCell(Text(_audienceLabel(strings, account))),
                    DataCell(
                      TextButton(
                        onPressed: () => onPreview(account),
                        child: Text(strings.mockAdminViewOperationalSummary),
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
            dividerThickness: 0.7,
          ),
        ),
      ),
    ),
  );
}

String _recoveryLabel(AppLocalizations strings, String status) => switch (status) {
  'issued' => strings.adminRecoveryIssued,
  'rejected' => strings.adminRecoveryRejected,
  'consumed' => strings.adminRecoveryConsumed,
  'expired' => strings.adminRecoveryExpired,
  _ => strings.adminRecoveryRequested,
};

String _statusLabel(AppLocalizations strings, GovernedAccountRead account) {
  if (account.locked) return strings.adminUserLocked;
  if (account.approvalStatus == 'pending') return strings.mockAdminPendingApproval;
  return switch (account.status) {
    'active' => strings.mockAdminNormal,
    'disabled' => strings.adminUserDisabled,
    _ => strings.adminUserPendingGrant,
  };
}

String _audienceLabel(AppLocalizations strings, GovernedAccountRead account) {
  final labels = [
    if (account.audiences.contains('client')) strings.mockAdminClientAudience,
    if (account.audiences.contains('admin')) strings.mockAdminAudience,
  ];
  if (labels.isEmpty) return strings.mockAdminInactive;
  return labels.join(' · ');
}

class _AccountCreateDialog extends StatefulWidget {
  const _AccountCreateDialog({
    required this.scope,
    required this.roles,
    required this.ceilings,
    required this.onCreated,
  });

  final _AdminUserScope scope;
  final List<RoleRead> roles;
  final AccountCeilingsRead? ceilings;
  final ValueChanged<GovernedAccountRead> onCreated;

  @override
  State<_AccountCreateDialog> createState() => _AccountCreateDialogState();
}

class _AccountCreateDialogState extends State<_AccountCreateDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final Set<String> _roles = {};
  String? _createdId;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var userId = _createdId;
      if (userId == null) {
        final created = await widget.scope.auth.createAdminAccount(
          _email.text.trim(),
          _name.text.trim().isEmpty ? null : _name.text.trim(),
          _roles.toList(),
        );
        userId = created.userId;
        _createdId = userId;
      }
      final account = await widget.scope.auth.adminAccount(userId);
      if (!mounted || !widget.scope.isCurrent) return;
      widget.onCreated(account);
      if (mounted) Navigator.of(context).pop();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    final assignable = widget.ceilings?.assignRoleIds.toSet() ?? const <String>{};
    return Identified(
      id: UiTestIds.adminUserDialog,
      child: AlertDialog(
        title: Text(strings.adminUserCreate),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.adminUserNoPassword),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: InputDecoration(labelText: strings.mockAdminEmailColumn),
              ),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: strings.adminUserDisplayName),
              ),
              if (widget.scope.allows('admin.user.role.assign'))
                for (final role in widget.roles)
                  if (assignable.contains(role.id))
                    CheckboxListTile(
                      value: _roles.contains(role.id),
                      onChanged: _busy
                          ? null
                          : (selected) => setState(() {
                              if (selected ?? false) {
                                _roles.add(role.id);
                              } else {
                                _roles.remove(role.id);
                              }
                            }),
                      title: Text(role.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(strings.mockAdminClose),
          ),
          Identified(
            id: UiTestIds.adminUserSave,
            merge: true,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(strings.adminUserCreate),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.scope,
    required this.account,
    required this.roles,
    required this.ceilings,
    required this.cachedSessions,
    required this.sessionsKnown,
    required this.cachedRecoveries,
    required this.recoveriesKnown,
    required this.onAccount,
    required this.onSessions,
    required this.onRecoveries,
  });

  final _AdminUserScope scope;
  final GovernedAccountRead account;
  final List<RoleRead> roles;
  final AccountCeilingsRead? ceilings;
  final List<AccountSessionRead>? cachedSessions;
  final bool sessionsKnown;
  final List<ManualRecoveryRead>? cachedRecoveries;
  final bool recoveriesKnown;
  final ValueChanged<GovernedAccountRead> onAccount;
  final ValueChanged<List<AccountSessionRead>> onSessions;
  final ValueChanged<List<ManualRecoveryRead>> onRecoveries;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late GovernedAccountRead _account;
  late Set<String> _roles;
  List<AccountSessionRead>? _sessions;
  List<ManualRecoveryRead>? _recoveries;
  var _busy = false;
  var _conflict = false;
  String? _error;

  bool get _canReviewRecovery =>
      widget.scope.allows('admin.user.update') && widget.scope.userId != _account.userId;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _roles = {for (final role in widget.account.roles) role.roleId};
    _sessions = widget.cachedSessions;
    _recoveries = widget.cachedRecoveries;
    if (!widget.sessionsKnown && widget.scope.allows('admin.session.read')) {
      unawaited(_loadSessions());
    }
    if (!widget.recoveriesKnown && _canReviewRecovery) {
      unawaited(_loadRecoveries());
    }
  }

  Future<void> _loadRecoveries() async {
    try {
      final requests = await widget.scope.auth.adminRecoveryRequests(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      setState(() => _recoveries = requests);
      widget.onRecoveries(requests);
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await widget.scope.auth.adminAccountSessions(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      setState(() => _sessions = sessions);
      widget.onSessions(sessions);
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  Future<void> _decide(String decision) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.scope.auth.decideAdminApproval(_account.userId, _account.revision, decision);
      if (!mounted || !widget.scope.isCurrent) return;
      final next = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      _apply(next);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recovery(ManualRecoveryRead request, String decision, String? method) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.scope.auth.decideAdminRecovery(
        _account.userId,
        request.challengeId,
        _account.revision,
        decision,
        method,
      );
      if (!mounted || !widget.scope.isCurrent) return;
      final token = result.token;
      if (token != null) {
        final strings = AppLocalizations.of(context);
        await showHarukaDialog<void>(
          context: context,
          animationStyle: HarukaMotion.dialogStyle(context),
          builder: (context) => GovernanceDialogGate(
            auth: widget.scope.auth,
            current: () => widget.scope.isCurrent,
            child: AlertDialog(
              title: Text(strings.adminRecoveryIssued),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.adminRecoveryTokenOnce),
                    const SizedBox(height: 12),
                    SelectableText(token),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(strings.mockAdminClose),
                ),
              ],
            ),
          ),
        );
      }
      if (!mounted || !widget.scope.isCurrent) return;
      final next = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      final requests = [
        for (final item in _recoveries ?? const <ManualRecoveryRead>[])
          if (item.challengeId == result.challengeId)
            ManualRecoveryRead(
              challengeId: item.challengeId,
              status: result.status,
              createdAt: item.createdAt,
              expiresAt: result.expiresAt,
            )
          else
            item,
      ];
      setState(() => _recoveries = requests);
      widget.onRecoveries(requests);
      _apply(next);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseRecoveryMethod(ManualRecoveryRead request) async {
    final strings = AppLocalizations.of(context);
    final method = await showHarukaDialog<String>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: widget.scope.auth,
        current: () => widget.scope.isCurrent,
        child: AlertDialog(
          title: Text(strings.adminRecoveryIssue),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'in_person'),
                child: Text(strings.adminRecoveryInPerson),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'known_channel'),
                child: Text(strings.adminRecoveryKnownChannel),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.mockAdminClose),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    await _recovery(request, 'issue', method);
  }

  Future<void> _status(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.scope.auth.setAdminAccountStatus(_account.userId, _account.revision, status);
      if (!mounted || !widget.scope.isCurrent) return;
      final next = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      final sessions = status == 'disabled' && _sessions != null
          ? [for (final session in _sessions!) _markedRevoked(session)]
          : null;
      _apply(next, sessions: sessions);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRoles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.scope.auth.replaceAdminAccountRoles(
        _account.userId,
        _account.revision,
        _roles.toList(),
      );
      if (!mounted || !widget.scope.isCurrent) return;
      final next = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      _apply(next);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke({String? sessionId, bool all = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.scope.auth.revokeAdminAccountSessions(_account.userId, _account.revision, {
        'expected_revision': _account.revision,
        'session_id': sessionId,
        'audience': null,
        'all_sessions': all,
      });
      if (!mounted || !widget.scope.isCurrent) return;
      final next = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      final sessions = [
        for (final session in _sessions ?? const <AccountSessionRead>[])
          if (all || session.sessionId == sessionId) _markedRevoked(session) else session,
      ];
      _apply(next, sessions: sessions);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _conflict = false;
    });
    try {
      final fresh = await widget.scope.auth.adminAccount(_account.userId);
      if (!mounted || !widget.scope.isCurrent) return;
      _apply(fresh);
    } on ApiFailure catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(GovernedAccountRead next, {List<AccountSessionRead>? sessions}) {
    setState(() {
      _account = next;
      _roles = {for (final role in next.roles) role.roleId};
      _error = null;
      _conflict = false;
      if (sessions != null) _sessions = sessions;
    });
    widget.onAccount(next);
    if (sessions != null) widget.onSessions(sessions);
  }

  void _fail(ApiFailure error) {
    if (!mounted) return;
    setState(() {
      _error = ApiCatalog.message(AppLocalizations.of(context), error.code);
      _conflict = error.code == 'REVISION_CONFLICT';
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    final assignable = widget.ceilings?.assignRoleIds.toSet() ?? const <String>{};
    return Identified(
      id: UiTestIds.adminUserDialog,
      child: AlertDialog(
        title: Text(strings.mockAdminSummary),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _account.displayName?.isNotEmpty == true ? _account.displayName! : _account.email,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_account.email),
              const SizedBox(height: 8),
              Text('${strings.mockAdminStatusColumn}：${_statusLabel(strings, _account)}'),
              if (widget.scope.allows('admin.user.enable') &&
                  _account.status != 'active' &&
                  _account.approvalStatus != 'pending' &&
                  _account.approvalStatus != 'rejected')
                TextButton(
                  onPressed: _busy ? null : () => _status('active'),
                  child: Text(strings.adminUserEnable),
                ),
              if (widget.scope.allows('admin.user.disable') && _account.status != 'disabled')
                TextButton(
                  onPressed: _busy ? null : () => _status('disabled'),
                  child: Text(strings.adminUserDisable),
                ),
              if (widget.scope.allows('admin.user.approve') &&
                  _account.approvalStatus != 'not_required' &&
                  _account.approvalStatus != 'approved')
                TextButton(
                  onPressed: _busy ? null : () => _decide('approve'),
                  child: Text(strings.adminUserApprove),
                ),
              if (widget.scope.allows('admin.user.approve') &&
                  _account.approvalStatus != 'not_required' &&
                  _account.approvalStatus != 'rejected')
                TextButton(
                  onPressed: _busy ? null : () => _decide('reject'),
                  child: Text(strings.adminUserReject),
                ),
              if (widget.scope.allows('admin.user.role.assign')) ...[
                const SizedBox(height: 8),
                Text(strings.adminUserRoles),
                for (final role in widget.roles)
                  if (assignable.contains(role.id) || _roles.contains(role.id))
                    CheckboxListTile(
                      value: _roles.contains(role.id),
                      onChanged: _busy
                          ? null
                          : (selected) => setState(() {
                              if (selected ?? false) {
                                _roles.add(role.id);
                              } else {
                                _roles.remove(role.id);
                              }
                            }),
                      title: Text(role.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                Identified(
                  id: UiTestIds.adminUserSave,
                  merge: true,
                  child: FilledButton(
                    onPressed: _busy ? null : _saveRoles,
                    child: Text(strings.adminUserSaveRoles),
                  ),
                ),
              ],
              if (_canReviewRecovery) ...[
                const SizedBox(height: 8),
                Text(strings.adminRecoveryRequests),
                if (_recoveries == null)
                  const CircularProgressIndicator()
                else
                  for (final request in _recoveries!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_recoveryLabel(strings, request.status)),
                      subtitle: request.status == 'issued'
                          ? Text(strings.adminRecoveryTokenHidden)
                          : null,
                      trailing: request.status == 'requested'
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _busy ? null : () => _chooseRecoveryMethod(request),
                                  child: Text(strings.adminRecoveryIssue),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _recovery(request, 'reject', null),
                                  child: Text(strings.adminRecoveryReject),
                                ),
                              ],
                            )
                          : null,
                    ),
              ],
              if (widget.scope.allows('admin.session.read')) ...[
                const SizedBox(height: 8),
                Text(strings.adminUserSessions),
                if (_sessions == null)
                  const CircularProgressIndicator()
                else
                  for (final session in _sessions!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${session.audience} · ${session.platform}'),
                      subtitle: Text(session.deviceSummary ?? session.transport),
                      trailing:
                          session.revokedAt != null || !widget.scope.allows('admin.session.revoke')
                          ? null
                          : TextButton(
                              onPressed: _busy ? null : () => _revoke(sessionId: session.sessionId),
                              child: Text(strings.adminUserRevoke),
                            ),
                    ),
                if (widget.scope.allows('admin.session.revoke'))
                  TextButton(
                    onPressed: _busy ? null : () => _revoke(all: true),
                    child: Text(strings.adminUserRevokeAll),
                  ),
              ],
              if (_error != null) ...[
                Text(_error!),
                if (_conflict)
                  TextButton(
                    onPressed: _busy ? null : _reload,
                    child: Text(strings.adminRoleReload),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.mockAdminClose),
          ),
        ],
      ),
    );
  }
}

AccountSessionRead _markedRevoked(AccountSessionRead session) {
  if (session.revokedAt != null) return session;
  return AccountSessionRead(
    sessionId: session.sessionId,
    audience: session.audience,
    transport: session.transport,
    platform: session.platform,
    deviceSummary: session.deviceSummary,
    createdAt: session.createdAt,
    lastSeenAt: session.lastSeenAt,
    absoluteExpiresAt: session.absoluteExpiresAt,
    revokedAt: DateTime.now().toUtc(),
  );
}

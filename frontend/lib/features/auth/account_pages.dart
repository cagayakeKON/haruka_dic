import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/motion.dart';
import '../../app/preview_shell.dart';
import '../../core/api/responses.dart';
import '../../core/api/request_ids.dart';
import '../../core/api/auth_models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/telemetry/telemetry.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import '../../shared/presentation/components.dart';

Future<void> showPasswordChangeDialog(BuildContext context, {bool admin = false}) async {
  final scope = _IdentityDialogScope.capture(context, admin: admin);
  if (scope == null) return;
  await showHarukaDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _IdentityDialogGuard(
      scope: scope,
      child: PasswordChangePage(admin: admin),
    ),
  );
}

Future<void> showDeviceSessionsDialog(BuildContext context, {bool admin = false}) async {
  final scope = _IdentityDialogScope.capture(context, admin: admin);
  if (scope == null) return;
  await showHarukaDialog<void>(
    context: context,
    builder: (_) => _IdentityDialogGuard(
      scope: scope,
      child: DeviceSessionsPage(admin: admin),
    ),
  );
}

/// Capture the identity before pushing the route. The dialog builder may run
/// after a logout or instance switch and must never bind to the new account.
final class _IdentityDialogScope {
  const _IdentityDialogScope({
    required this.auth,
    required this.endpoint,
    required this.instanceId,
    required this.userId,
    required this.admin,
    required this.sessionRef,
    required this.actionEpoch,
    required this.authzUserVersion,
    required this.securityEpoch,
  });

  final AuthController auth;
  final Uri endpoint;
  final String instanceId;
  final String userId;
  final bool admin;
  final String sessionRef;
  final int actionEpoch;
  final int authzUserVersion;
  final int? securityEpoch;

  bool sameIdentity(_IdentityDialogScope? other) =>
      other != null &&
      identical(auth, other.auth) &&
      endpoint == other.endpoint &&
      instanceId == other.instanceId &&
      userId == other.userId &&
      admin == other.admin &&
      sessionRef == other.sessionRef &&
      actionEpoch == other.actionEpoch &&
      authzUserVersion == other.authzUserVersion &&
      securityEpoch == other.securityEpoch;

  static _IdentityDialogScope? capture(BuildContext context, {required bool admin}) {
    final auth = ProviderScope.containerOf(context, listen: false).read(authControllerProvider);
    return captureAuth(auth, admin: admin);
  }

  static _IdentityDialogScope? captureAuth(AuthController auth, {required bool admin}) {
    final access = auth.access;
    if (!auth.isAuthenticated || auth.admin != admin || access == null) return null;
    return _IdentityDialogScope(
      auth: auth,
      endpoint: auth.repository.api.endpoint,
      instanceId: auth.boundInstanceId,
      userId: access.userId,
      admin: admin,
      sessionRef: access.sessionRef,
      actionEpoch: auth.actionEpoch,
      authzUserVersion: access.authzVersion.user,
      securityEpoch: access.securityEpoch,
    );
  }

  bool get isCurrent {
    final access = auth.access;
    return auth.isAuthenticated &&
        auth.actionEpoch == actionEpoch &&
        auth.admin == admin &&
        auth.repository.api.endpoint == endpoint &&
        auth.boundInstanceId == instanceId &&
        access?.instanceId == instanceId &&
        access?.userId == userId &&
        access?.sessionRef == sessionRef &&
        access?.authzVersion.user == authzUserVersion &&
        access?.securityEpoch == securityEpoch &&
        access?.audience == (admin ? 'admin' : 'client');
  }
}

class _IdentityDialogGuard extends ConsumerStatefulWidget {
  const _IdentityDialogGuard({required this.scope, required this.child});
  final _IdentityDialogScope scope;
  final Widget child;

  @override
  ConsumerState<_IdentityDialogGuard> createState() => _IdentityDialogGuardState();
}

class _IdentityDialogGuardState extends ConsumerState<_IdentityDialogGuard> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.scope.auth.addListener(_checkScope);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScope());
  }

  void _checkScope() {
    if (_closing || !mounted) return;
    if (widget.scope.isCurrent) return;
    _closing = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context, rootNavigator: true).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    widget.scope.auth.removeListener(_checkScope);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closing || !widget.scope.isCurrent) {
      if (!_closing) WidgetsBinding.instance.addPostFrameCallback((_) => _checkScope());
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}

/// A single scoped account read shared by the mock-styled account and settings
/// surfaces. An old read is hidden as soon as identity or service changes.
final _accountIdentityCacheProvider = ChangeNotifierProvider<_AccountIdentityCache>((ref) {
  return _AccountIdentityCache(ref.read(authControllerProvider));
});

/// Lives above mobile/desktop presentation branches in the provider scope.
/// Rebuilding either branch reuses the same in-flight or completed read.
final class _AccountIdentityCache extends ChangeNotifier {
  _AccountIdentityCache(this._auth) {
    _auth.addListener(_onAuthChanged);
    _capture();
  }

  final AuthController _auth;
  _IdentityDialogScope? _scope;
  Future<AccountRead>? _flight;
  AccountRead? _value;
  Object? _error;

  _IdentityDialogScope? get scope => _scope;
  AccountRead? get value => _value;
  Object? get error => _error;

  void _capture() {
    final next = _IdentityDialogScope.captureAuth(_auth, admin: false);
    _scope = next;
    _value = null;
    _error = null;
    _flight = null;
    if (next != null) _load(next);
  }

  void _load(_IdentityDialogScope scope) {
    final flight = _auth.account();
    _flight = flight;
    unawaited(
      flight.then<void>(
        (value) {
          if (identical(_flight, flight) && scope.isCurrent) {
            _value = value;
            notifyListeners();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_flight, flight) && scope.isCurrent) {
            _error = error;
            notifyListeners();
          }
        },
      ),
    );
  }

  void _onAuthChanged() {
    final next = _IdentityDialogScope.captureAuth(_auth, admin: false);
    if (_scope?.sameIdentity(next) ?? next == null) return;
    _capture();
    notifyListeners();
  }

  void retry() {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    _value = null;
    _error = null;
    _load(scope);
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _flight = null;
    _scope = null;
    super.dispose();
  }
}

class AccountIdentitySummary extends ConsumerWidget {
  const AccountIdentitySummary({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(_accountIdentityCacheProvider);
    final scope = cache.scope;
    if (scope == null || !scope.isCurrent) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    if (cache.error != null) {
      return TextButton(
        onPressed: cache.retry,
        child: Text('${strings.authUnavailable} · ${strings.authCheckAgain}'),
      );
    }
    final email = cache.value?.email ?? strings.authLoading;
    if (compact) return Text(email, overflow: TextOverflow.ellipsis);
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.person_outline),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.authAccount, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(email, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    final controller = ref.read(authControllerProvider);
    final epoch = controller.actionEpoch;
    final sessionRef = controller.access?.sessionRef;
    final operationId = newRequestId();
    var confirmed = true;
    try {
      final telemetry = ref.read(telemetryProvider);
      telemetry?.track('auth.logout.requested', operationId: operationId);
      if (telemetry != null) unawaited(telemetry.flush());
      await controller.signOut(operationId: operationId);
    } on Object {
      confirmed = false;
    }
    if (sessionRef != null && controller.wasLocallySignedOutBy(epoch, sessionRef)) {
      router.go(confirmed ? AppRoutes.login : AppRoutes.signedOutLocally);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final strings = AppLocalizations.of(context);
    if (!controller.isAuthenticated || controller.admin) {
      return Center(child: Text(strings.apiAuthRequired));
    }
    final canReadProfile = controller.access!.allows('client.profile.read');
    final mobile = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        HarukaSurface(child: const AccountIdentitySummary()),
        const SizedBox(height: 18),
        if (canReadProfile) ...[
          _securityCard(
            context,
            strings.mockSettingProfile,
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.mockSettingProfile),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.settings),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _securityCard(
          context,
          strings.mockSettingChangePassword,
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.mockSettingChangePassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(showPasswordChangeDialog(context)),
          ),
        ),
        const SizedBox(height: 16),
        _securityCard(
          context,
          strings.mockSettingCurrentSession,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.mockSettingSessionActive),
              const SizedBox(height: 13),
              OutlinedButton(
                onPressed: () => unawaited(showDeviceSessionsDialog(context)),
                child: Text(strings.mockSettingViewSession),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => unawaited(_signOut()),
                child: Text(strings.mockSettingLogout),
              ),
            ],
          ),
        ),
      ],
    );
    final desktop = ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HarukaSurface(child: const AccountIdentitySummary()),
                const SizedBox(height: 18),
                HarukaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canReadProfile) ...[
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(strings.mockSettingProfile),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(AppRoutes.settings),
                        ),
                        const Divider(),
                      ],
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(strings.mockSettingChangePassword),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(showPasswordChangeDialog(context)),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.devices_outlined),
                        title: Text(strings.mockSettingCurrentSession),
                        subtitle: Text(strings.mockSettingSessionActive),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(showDeviceSessionsDialog(context)),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: () => unawaited(_signOut()),
                          child: Text(strings.mockSettingLogout),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return Identified(
      id: UiTestIds.accountPage,
      child: PreviewPageFrame(
        location: AppRoutes.account,
        title: strings.mockSettingMyTitle,
        mobile: mobile,
        desktop: desktop,
      ),
    );
  }
}

Widget _securityCard(BuildContext context, String title, Widget child) => HarukaSurface(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 14),
      child,
    ],
  ),
);

class PasswordChangePage extends ConsumerStatefulWidget {
  const PasswordChangePage({this.admin = false, super.key});
  final bool admin;
  @override
  ConsumerState<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends ConsumerState<PasswordChangePage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final router = GoRouter.of(context);
    final auth = ref.read(authControllerProvider);
    final actionEpoch = auth.actionEpoch;
    final sessionRef = auth.access?.sessionRef;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final operationId = newRequestId();
      final telemetry = ref.read(telemetryProvider);
      telemetry?.track('auth.password.change.submitted', operationId: operationId);
      if (telemetry != null) unawaited(telemetry.flush());
      await auth.changePassword(_current.text, _next.text, operationId: operationId);
      if (auth.actionEpoch == actionEpoch + 1 &&
          auth.phase == AuthPhase.anonymous &&
          sessionRef != null) {
        // The identity guard removes its own dialog after the intentional
        // sign-out. Never pop here: it could pop the page underneath.
        router.go(AppRoutes.passwordChanged);
      }
    } on ApiFailure catch (error) {
      if (sessionRef != null &&
          auth.actionEpoch == actionEpoch + 1 &&
          auth.phase == AuthPhase.anonymous &&
          !const {
            'INPUT_INVALID',
            'BAD_REQUEST',
            'AUTH_LOGIN_FAILED',
            'REVISION_CONFLICT',
            'CSRF_FAILED',
            'PERMISSION_DENIED',
            'RATE_LIMITED',
            'STATE_CONFLICT',
          }.contains(error.code)) {
        router.go(AppRoutes.passwordChangeUnknown);
        return;
      }
      if (mounted) {
        setState(
          () => _error =
              error.code == 'NETWORK_UNAVAILABLE' || error.code == 'EXTERNAL_RESULT_UNKNOWN'
              ? AppLocalizations.of(context).authPasswordOutcomeUnknown
              : ApiCatalog.message(AppLocalizations.of(context), error.code),
        );
      }
    } on Object {
      if (sessionRef != null &&
          auth.actionEpoch == actionEpoch + 1 &&
          auth.phase == AuthPhase.anonymous) {
        router.go(AppRoutes.passwordChangeUnknown);
        return;
      }
      if (mounted) setState(() => _error = AppLocalizations.of(context).authPasswordOutcomeUnknown);
    } finally {
      if (mounted) {
        _current.clear();
        _next.clear();
        _confirm.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final policy = ref.watch(authControllerProvider).policy;
    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Identified(
            id: UiTestIds.accountCurrentPassword,
            merge: true,
            child: TextFormField(
              controller: _current,
              obscureText: true,
              enabled: !_busy,
              decoration: InputDecoration(labelText: strings.authCurrentPassword),
              validator: (value) => value == null || value.isEmpty ? strings.authRequired : null,
            ),
          ),
          const SizedBox(height: 16),
          Identified(
            id: UiTestIds.accountNewPassword,
            merge: true,
            child: TextFormField(
              controller: _next,
              obscureText: true,
              enabled: !_busy,
              decoration: InputDecoration(labelText: strings.authNewPassword),
              validator: (value) {
                if (value == null || value.isEmpty) return strings.authRequired;
                if (policy == null) return strings.authUnavailable;
                final length = value.runes.length;
                return length < policy.passwordMinLength || length > policy.passwordMaxLength
                    ? strings.authPasswordLength(policy.passwordMinLength, policy.passwordMaxLength)
                    : null;
              },
            ),
          ),
          const SizedBox(height: 16),
          Identified(
            id: UiTestIds.accountConfirmPassword,
            merge: true,
            child: TextFormField(
              controller: _confirm,
              obscureText: true,
              enabled: !_busy,
              decoration: InputDecoration(labelText: strings.authConfirmPassword),
              validator: (value) => value != _next.text ? strings.authPasswordMismatch : null,
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!)),
          const SizedBox(height: 24),
          Identified(
            id: UiTestIds.accountChangePassword,
            merge: true,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(strings.authChangePassword),
            ),
          ),
        ],
      ),
    );
    return AlertDialog(
      title: Text(strings.authChangePassword),
      content: SizedBox(width: 390, child: SingleChildScrollView(child: form)),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(strings.mockSettingCancel),
        ),
      ],
    );
  }
}

class DeviceSessionsPage extends ConsumerStatefulWidget {
  const DeviceSessionsPage({this.admin = false, super.key});
  final bool admin;
  @override
  ConsumerState<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

class _DeviceSessionsPageState extends ConsumerState<DeviceSessionsPage> {
  Future<PageResponse<SessionSummary>>? _sessions;
  final List<SessionSummary> _loaded = [];
  String? _nextCursor;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(authControllerProvider).sessions();
  }

  void _reload() {
    final next = ref.read(authControllerProvider).sessions();
    _loaded.clear();
    _nextCursor = null;
    setState(() {
      _sessions = next;
    });
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(authControllerProvider).sessions(cursor: cursor);
      if (!mounted) return;
      setState(() {
        _loaded.addAll(page.data);
        _nextCursor = page.nextCursor;
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _revoke(String id) async {
    final router = GoRouter.of(context);
    final auth = ref.read(authControllerProvider);
    final telemetry = ref.read(telemetryProvider);
    final epoch = auth.actionEpoch;
    final sessionRef = auth.access?.sessionRef;
    if (sessionRef == null) return;
    try {
      final operationId = newRequestId();
      await auth.revoke(id, operationId: operationId);
      if (auth.wasLocallySignedOutBy(epoch, sessionRef)) {
        router.go(widget.admin ? AppRoutes.adminLogin : AppRoutes.login);
        return;
      }
      if (epoch == auth.actionEpoch && auth.isAuthenticated) {
        telemetry?.track(
          'auth.session.revoked',
          attributes: {'result': 'success'},
          operationId: operationId,
        );
      }
      if (!mounted) return;
      if (epoch == auth.actionEpoch && auth.access?.sessionRef == sessionRef) _reload();
    } on ApiFailure catch (error) {
      if (auth.wasLocallySignedOutBy(epoch, sessionRef)) {
        router.go(AppRoutes.signedOutLocally);
        return;
      }
      if (mounted) {
        setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) Text(_error!),
        FutureBuilder<PageResponse<SessionSummary>>(
          key: ObjectKey(_sessions),
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(strings.authUnavailable);
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (_loaded.isEmpty) {
              _loaded.addAll(snapshot.data!.data);
              _nextCursor = snapshot.data!.nextCursor;
            }
            if (_loaded.isEmpty) return Text(strings.authNoSessions);
            return Column(
              children: [
                for (final session in _loaded)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${session.audience} · ${session.platform} · ${session.transport}${session.isCurrent ? ' · ${strings.authSessionCurrent}' : ''}',
                      ),
                      subtitle: Text(
                        [
                          if (session.deviceSummary != null) session.deviceSummary!,
                          '${strings.authSessionLastSeen}: ${session.lastSeenAt?.toLocal() ?? strings.authSessionNever}',
                          '${strings.authSessionExpires}: ${session.absoluteExpiresAt.toLocal()}',
                          if (session.isRevoked) strings.authSessionRevoked,
                        ].join('\n'),
                      ),
                      trailing: session.isRevoked
                          ? null
                          : Identified(
                              id: UiTestIds.sessionRevoke(session.id),
                              merge: true,
                              child: TextButton(
                                onPressed: () => _revoke(session.id),
                                child: Text(strings.authRevokeSession),
                              ),
                            ),
                    ),
                  ),
                if (_nextCursor != null)
                  TextButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: Text(strings.authLoadMoreSessions),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Identified(
          id: UiTestIds.sessionRevokeAll,
          merge: true,
          child: FilledButton.tonal(
            onPressed: () async {
              final router = GoRouter.of(context);
              final auth = ref.read(authControllerProvider);
              final epoch = auth.actionEpoch;
              final sessionRef = auth.access?.sessionRef;
              try {
                final cleared = await auth.revokeAll();
                if (cleared &&
                    auth.actionEpoch == epoch + 1 &&
                    !auth.isAuthenticated &&
                    sessionRef != null) {
                  router.go(widget.admin ? AppRoutes.adminLogin : AppRoutes.login);
                }
              } on ApiFailure catch (error) {
                if (mounted) setState(() => _error = ApiCatalog.message(strings, error.code));
              }
            },
            child: Text(strings.authRevokeAll),
          ),
        ),
      ],
    );
    return Identified(
      id: UiTestIds.accountSessions,
      child: AlertDialog(
        title: Text(strings.authDeviceSessions),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.mockSettingClose),
          ),
        ],
      ),
    );
  }
}

class AdminPolicyEditor extends ConsumerStatefulWidget {
  const AdminPolicyEditor({super.key});

  @override
  ConsumerState<AdminPolicyEditor> createState() => _AdminPolicyEditorState();
}

class _AdminPolicyEditorState extends ConsumerState<AdminPolicyEditor> {
  late final AuthController _auth;
  _IdentityDialogScope? _scope;
  Future<AdminPolicy>? _policy;
  bool _readAllowed = false;
  AdminPolicy? _loaded;
  String _draft = 'closed';
  String _recovery = 'email';
  bool _busy = false;
  bool _conflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authControllerProvider);
    _auth.addListener(_onAuthChanged);
    _capture();
  }

  void _capture() {
    final scope = _IdentityDialogScope.captureAuth(_auth, admin: true);
    _scope = scope;
    _readAllowed = scope != null && _auth.access?.allows('admin.auth_policy.read') == true;
    _loaded = null;
    _draft = 'closed';
    _recovery = 'email';
    _busy = false;
    _conflict = false;
    _error = null;
    _policy = _readAllowed ? _auth.adminPolicy() : null;
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final next = _IdentityDialogScope.captureAuth(_auth, admin: true);
    final nextReadAllowed = next != null && _auth.access?.allows('admin.auth_policy.read') == true;
    if ((_scope?.sameIdentity(next) ?? next == null) && _readAllowed == nextReadAllowed) return;
    setState(_capture);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _save() async {
    final scope = _scope;
    final loaded = _loaded;
    if (_busy ||
        scope == null ||
        !scope.isCurrent ||
        loaded == null ||
        _auth.access?.allows('admin.auth_policy.update') != true) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await _auth.updateAdminPolicy(
        _draft,
        loaded.revision,
        recoveryMode: _recovery == loaded.recoveryMode ? null : _recovery,
      );
      if (mounted && scope.isCurrent) {
        setState(() {
          _loaded = updated;
          _draft = updated.registrationMode;
          _recovery = updated.recoveryMode;
          _conflict = false;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted && scope.isCurrent) {
        setState(() {
          _error = ApiCatalog.message(AppLocalizations.of(context), error.code);
          _conflict = error.code == 'REVISION_CONFLICT';
        });
      }
    } finally {
      if (mounted && scope.isCurrent) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return const SizedBox.shrink();
    if (!_readAllowed || _auth.access?.allows('admin.auth_policy.read') != true) {
      return Text(AppLocalizations.of(context).authNoAdminPermission);
    }
    final strings = AppLocalizations.of(context);
    return Identified(
      id: UiTestIds.adminPolicyPage,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_policy == null)
              Text(strings.authNoAdminPermission)
            else
              FutureBuilder<AdminPolicy>(
                key: ObjectKey(scope),
                future: _policy,
                builder: (context, snapshot) {
                  if (!scope.isCurrent) return const SizedBox.shrink();
                  if (snapshot.hasError) return Text(strings.authUnavailable);
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  if (_loaded == null) {
                    _loaded = snapshot.data;
                    _draft = snapshot.data!.registrationMode;
                    _recovery = snapshot.data!.recoveryMode;
                  }
                  final canUpdate = _auth.access?.allows('admin.auth_policy.update') == true;
                  final changed =
                      _draft != _loaded!.registrationMode || _recovery != _loaded!.recoveryMode;
                  final editor = _PolicyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(strings.authAdminPolicyHint),
                        const SizedBox(height: 18),
                        Identified(
                          id: UiTestIds.adminRegistrationToggle,
                          merge: true,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_draft),
                            initialValue: _draft,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: strings.mockAdminRegistrationMode,
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'closed',
                                child: Text(strings.mockAdminClosedExample),
                              ),
                              DropdownMenuItem(
                                value: 'approval',
                                child: Text(strings.mockAdminApprovalExample),
                              ),
                              DropdownMenuItem(value: 'open', child: Text(strings.adminPolicyOpen)),
                            ],
                            onChanged: !canUpdate || _busy
                                ? null
                                : (value) {
                                    if (value != null) setState(() => _draft = value);
                                  },
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${strings.mockAdminEmailVerification}：${strings.mockAdminVerifyWhenEnabled}',
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          key: ValueKey('recovery-$_recovery'),
                          initialValue: _recovery,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: strings.mockAdminAccountRecovery,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final mode in const [
                              'email',
                              'manual',
                              'email_or_manual',
                              'disabled',
                            ])
                              DropdownMenuItem(
                                value: mode,
                                child: Text(_recoveryLabel(strings, mode)),
                              ),
                          ],
                          onChanged: !canUpdate || _busy
                              ? null
                              : (value) {
                                  if (value != null) setState(() => _recovery = value);
                                },
                        ),
                        if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
                        if (_conflict)
                          TextButton(
                            onPressed: _busy ? null : _reload,
                            child: Text(strings.adminRoleReload),
                          ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: canUpdate && !_busy && changed
                                ? () => _preview(strings)
                                : null,
                            child: Text(strings.mockAdminPreviewPolicy),
                          ),
                        ),
                      ],
                    ),
                  );
                  final current = _PolicyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.mockAdminCurrentPolicy,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 18),
                        Text(_registrationLabel(strings, _loaded!.registrationMode)),
                        const SizedBox(height: 11),
                        Text(strings.mockAdminVerifyWhenEnabled),
                        const SizedBox(height: 11),
                        Text(_recoveryLabel(strings, _loaded!.recoveryMode)),
                      ],
                    ),
                  );
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 700) {
                        return Column(children: [editor, const SizedBox(height: 16), current]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: editor),
                          const SizedBox(width: 22),
                          Expanded(flex: 2, child: current),
                        ],
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    final scope = _scope;
    if (_busy || scope == null || !scope.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
      _conflict = false;
    });
    try {
      final fresh = await _auth.adminPolicy();
      if (mounted && scope.isCurrent) {
        setState(() {
          _loaded = fresh;
          _draft = fresh.registrationMode;
          _recovery = fresh.recoveryMode;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted && scope.isCurrent) {
        setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
      }
    } finally {
      if (mounted && scope.isCurrent) setState(() => _busy = false);
    }
  }

  void _preview(AppLocalizations strings) {
    final draft = _draft;
    final recovery = _recovery;
    unawaited(
      showHarukaDialog<void>(
        context: context,
        animationStyle: HarukaMotion.dialogStyle(context),
        builder: (context) => AlertDialog(
          title: Text(strings.mockAdminPolicyPreviewTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${strings.mockAdminRegistrationMode}: ${_registrationLabel(strings, draft)}'),
                const SizedBox(height: 12),
                Text(
                  '${strings.mockAdminEmailVerification}: ${strings.mockAdminVerifyWhenEnabled}',
                ),
                const SizedBox(height: 12),
                Text('${strings.mockAdminAccountRecovery}: ${_recoveryLabel(strings, recovery)}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.mockAdminClose),
            ),
            Identified(
              id: UiTestIds.adminRegistrationSave,
              merge: true,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        unawaited(_save());
                      },
                child: Text(strings.mockAdminApplyPolicy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _registrationLabel(AppLocalizations strings, String mode) => switch (mode) {
  'approval' => strings.mockAdminApprovalExample,
  'open' => strings.adminPolicyOpen,
  _ => strings.mockAdminClosedExample,
};

String _recoveryLabel(AppLocalizations strings, String mode) => switch (mode) {
  'manual' => strings.mockAdminManualRecovery,
  'email_or_manual' => strings.adminPolicyRecoveryEither,
  'disabled' => strings.adminPolicyRecoveryDisabled,
  _ => strings.mockAdminEmailRecovery,
};

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(18),
    child: Padding(padding: const EdgeInsets.all(26), child: child),
  );
}

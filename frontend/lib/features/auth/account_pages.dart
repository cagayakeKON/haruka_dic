import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/responses.dart';
import '../../core/api/request_ids.dart';
import '../../core/api/auth_models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/telemetry/telemetry.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  Future<AccountRead>? _account;
  String? _accountUserId;

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
      return _AccountScaffold(title: strings.authAccount, child: Text(strings.apiAuthRequired));
    }
    if (_accountUserId != controller.access!.userId) {
      _accountUserId = controller.access!.userId;
      _account = controller.account();
    }
    return Identified(
      id: UiTestIds.accountPage,
      child: LayoutBuilder(
        builder: (context, size) => size.maxWidth >= 900
            ? _DesktopAccountHome(
                account: _account,
                canReadMaterials: controller.access!.allows('client.material.list'),
                canReadCollections: controller.access!.allows('client.collection.read'),
                canReadProfile: controller.access!.allows('client.profile.read'),
                onSignOut: _signOut,
              )
            : _MobileAccountHome(
                account: _account,
                canReadMaterials: controller.access!.allows('client.material.list'),
                canReadCollections: controller.access!.allows('client.collection.read'),
                canReadProfile: controller.access!.allows('client.profile.read'),
                onSignOut: _signOut,
              ),
      ),
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({required this.account});

  final Future<AccountRead>? account;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return FutureBuilder<AccountRead>(
      future: account,
      builder: (context, snapshot) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.person_outline,
                color: Theme.of(context).colorScheme.primary,
                size: 29,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.authAccount,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  if (snapshot.hasError)
                    Text(strings.authUnavailable)
                  else if (!snapshot.hasData)
                    const LinearProgressIndicator()
                  else
                    Text(
                      snapshot.data!.email,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountActionTile extends StatelessWidget {
  const _AccountActionTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Identified(
    id: id,
    merge: true,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 19),
      onTap: onTap,
    ),
  );
}

class _MobileAccountHome extends StatelessWidget {
  const _MobileAccountHome({
    required this.account,
    required this.canReadMaterials,
    required this.canReadCollections,
    required this.canReadProfile,
    required this.onSignOut,
  });

  final Future<AccountRead>? account;
  final bool canReadMaterials;
  final bool canReadCollections;
  final bool canReadProfile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'h',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(strings.accountHomeTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccountIdentity(account: account),
              const SizedBox(height: 28),
              if (canReadMaterials || canReadCollections) ...[
                Text(strings.accountLearningTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (canReadMaterials)
                        _AccountActionTile(
                          id: UiTestIds.accountMaterials,
                          icon: Icons.auto_stories_outlined,
                          label: strings.referenceMaterialsTitle,
                          onTap: () => context.go(AppRoutes.materials),
                        ),
                      if (canReadMaterials && canReadCollections)
                        const Divider(height: 1, indent: 18, endIndent: 18),
                      if (canReadCollections)
                        _AccountActionTile(
                          id: UiTestIds.referenceCollectionsNav,
                          icon: Icons.bookmark_outline,
                          label: strings.referenceCollectionsTitle,
                          onTap: () => context.go(AppRoutes.collections),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
              ],
              Text(strings.authAccount, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (canReadProfile) ...[
                      _AccountActionTile(
                        id: UiTestIds.accountNavigation,
                        icon: Icons.tune_outlined,
                        label: '个人资料与设置',
                        onTap: () => context.go(AppRoutes.settings),
                      ),
                      const Divider(height: 1, indent: 18, endIndent: 18),
                    ],
                    _AccountActionTile(
                      id: UiTestIds.accountChangePassword,
                      icon: Icons.lock_outline,
                      label: strings.authChangePassword,
                      onTap: () => context.go(AppRoutes.accountPassword),
                    ),
                    const Divider(height: 1, indent: 18, endIndent: 18),
                    _AccountActionTile(
                      id: UiTestIds.accountSessions,
                      icon: Icons.devices_outlined,
                      label: strings.authDeviceSessions,
                      onTap: () => context.go(AppRoutes.accountSessions),
                    ),
                    const Divider(height: 1, indent: 18, endIndent: 18),
                    _AccountActionTile(
                      id: UiTestIds.accountSignOut,
                      icon: Icons.logout,
                      label: strings.authSignOut,
                      onTap: () => unawaited(onSignOut()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopAccountHome extends StatelessWidget {
  const _DesktopAccountHome({
    required this.account,
    required this.canReadMaterials,
    required this.canReadCollections,
    required this.canReadProfile,
    required this.onSignOut,
  });

  final Future<AccountRead>? account;
  final bool canReadMaterials;
  final bool canReadCollections;
  final bool canReadProfile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 224,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '▣  haruka',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 55),
                      if (canReadMaterials)
                        ListTile(
                          leading: const Icon(Icons.auto_stories_outlined),
                          title: Text(strings.referenceMaterialsTitle),
                          onTap: () => context.go(AppRoutes.materials),
                        ),
                      if (canReadCollections)
                        ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(strings.referenceCollectionsTitle),
                          onTap: () => context.go(AppRoutes.collections),
                        ),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(strings.accountHomeTitle),
                        selected: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(48, 88, 48, 50),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.accountHomeTitle,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 28),
                        _AccountIdentity(account: account),
                        const SizedBox(height: 36),
                        Wrap(
                          spacing: 28,
                          runSpacing: 28,
                          children: [
                            if (canReadMaterials || canReadCollections)
                              SizedBox(
                                width: 330,
                                child: _DesktopAccountGroup(
                                  title: strings.accountLearningTitle,
                                  children: [
                                    if (canReadMaterials)
                                      _AccountActionTile(
                                        id: UiTestIds.accountMaterials,
                                        icon: Icons.auto_stories_outlined,
                                        label: strings.referenceMaterialsTitle,
                                        onTap: () => context.go(AppRoutes.materials),
                                      ),
                                    if (canReadCollections)
                                      _AccountActionTile(
                                        id: UiTestIds.referenceCollectionsNav,
                                        icon: Icons.bookmark_outline,
                                        label: strings.referenceCollectionsTitle,
                                        onTap: () => context.go(AppRoutes.collections),
                                      ),
                                  ],
                                ),
                              ),
                            SizedBox(
                              width: 330,
                              child: _DesktopAccountGroup(
                                title: strings.authAccount,
                                children: [
                                  if (canReadProfile)
                                    _AccountActionTile(
                                      id: UiTestIds.accountNavigation,
                                      icon: Icons.tune_outlined,
                                      label: '个人资料与设置',
                                      onTap: () => context.go(AppRoutes.settings),
                                    ),
                                  _AccountActionTile(
                                    id: UiTestIds.accountChangePassword,
                                    icon: Icons.lock_outline,
                                    label: strings.authChangePassword,
                                    onTap: () => context.go(AppRoutes.accountPassword),
                                  ),
                                  _AccountActionTile(
                                    id: UiTestIds.accountSessions,
                                    icon: Icons.devices_outlined,
                                    label: strings.authDeviceSessions,
                                    onTap: () => context.go(AppRoutes.accountSessions),
                                  ),
                                  _AccountActionTile(
                                    id: UiTestIds.accountSignOut,
                                    icon: Icons.logout,
                                    label: strings.authSignOut,
                                    onTap: () => unawaited(onSignOut()),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAccountGroup extends StatelessWidget {
  const _DesktopAccountGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 14),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const Divider(height: 1, indent: 18, endIndent: 18),
              children[index],
            ],
          ],
        ),
      ),
    ],
  );
}

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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final operationId = newRequestId();
      final telemetry = ref.read(telemetryProvider);
      telemetry?.track('auth.password.change.submitted', operationId: operationId);
      if (telemetry != null) unawaited(telemetry.flush());
      await ref
          .read(authControllerProvider)
          .changePassword(_current.text, _next.text, operationId: operationId);
      if (mounted) context.go(AppRoutes.passwordChanged);
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.code == 'NETWORK_UNAVAILABLE' || error.code == 'EXTERNAL_RESULT_UNKNOWN'
              ? AppLocalizations.of(context).authPasswordOutcomeUnknown
              : ApiCatalog.message(AppLocalizations.of(context), error.code),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = AppLocalizations.of(context).authPasswordOutcomeUnknown);
    } finally {
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final policy = ref.watch(authControllerProvider).policy;
    return _AccountScaffold(
      title: strings.authChangePassword,
      child: Form(
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
                      ? strings.authPasswordLength(
                          policy.passwordMinLength,
                          policy.passwordMaxLength,
                        )
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
      ),
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
    _loaded.clear();
    _nextCursor = null;
    setState(() => _sessions = ref.read(authControllerProvider).sessions());
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
    return Identified(
      id: UiTestIds.accountSessions,
      child: _AccountScaffold(
        title: strings.authDeviceSessions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) Text(_error!),
            FutureBuilder<PageResponse<SessionSummary>>(
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
        ),
      ),
    );
  }
}

class AdminPolicyPage extends ConsumerStatefulWidget {
  const AdminPolicyPage({super.key});
  @override
  ConsumerState<AdminPolicyPage> createState() => _AdminPolicyPageState();
}

class _AdminPolicyPageState extends ConsumerState<AdminPolicyPage> {
  Future<AdminPolicy>? _policy;
  AdminPolicy? _loaded;
  bool _enabled = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated && auth.admin && auth.access!.allows('admin.auth_policy.read')) {
      _policy = auth.adminPolicy();
    }
  }

  Future<void> _save() async {
    if (_loaded == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(authControllerProvider)
          .updateAdminPolicy(_enabled, _loaded!.revision);
      if (mounted) {
        setState(() {
          _loaded = updated;
          _enabled = updated.registrationEnabled;
        });
      }
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    final auth = ref.read(authControllerProvider);
    final telemetry = ref.read(telemetryProvider);
    final epoch = auth.actionEpoch;
    final sessionRef = auth.access?.sessionRef;
    final operationId = newRequestId();
    var confirmed = true;
    try {
      telemetry?.track('auth.logout.requested', operationId: operationId);
      if (telemetry != null) unawaited(telemetry.flush());
      await auth.signOut(operationId: operationId);
    } on Object {
      confirmed = false;
    }
    if (sessionRef != null && auth.wasLocallySignedOutBy(epoch, sessionRef)) {
      router.go(confirmed ? AppRoutes.adminLogin : AppRoutes.signedOutLocally);
    }
  }

  Widget _policyEditor(AuthController auth, AppLocalizations strings) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.authAdminPolicyHint),
        const SizedBox(height: 24),
        if (_policy == null)
          Text(strings.authNoAdminPermission)
        else
          FutureBuilder<AdminPolicy>(
            future: _policy,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(strings.authUnavailable);
              if (!snapshot.hasData) return const CircularProgressIndicator();
              if (_loaded == null) {
                _loaded = snapshot.data;
                _enabled = snapshot.data!.registrationEnabled;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Identified(
                    id: UiTestIds.adminRegistrationToggle,
                    merge: true,
                    child: Row(
                      children: [
                        Expanded(child: Text(strings.authRegistrationEnabled)),
                        Switch(
                          value: _enabled,
                          onChanged:
                              auth.access?.allows('admin.auth_policy.update') == true && !_busy
                              ? (value) => setState(() => _enabled = value)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
                  const SizedBox(height: 20),
                  Identified(
                    id: UiTestIds.adminRegistrationSave,
                    merge: true,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed: auth.access?.allows('admin.auth_policy.update') == true && !_busy
                          ? _save
                          : null,
                      child: Text(strings.authSavePolicy),
                    ),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(strings.authEmailVerificationFact),
        const SizedBox(height: 10),
        Text(
          '${strings.authMailRecoveryFact}：${auth.policy?.recoveryEnabled == true ? strings.authAvailable : strings.authUnavailableShort}',
        ),
      ],
    ),
  );

  Widget _securityActions(AuthController auth, AppLocalizations strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Identified(
        id: UiTestIds.adminSecurityPassword,
        merge: true,
        child: TextButton.icon(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: auth.isAuthenticated ? () => context.go(AppRoutes.adminPassword) : null,
          icon: const Icon(Icons.lock_outline),
          label: Text(strings.authChangePassword),
        ),
      ),
      Identified(
        id: UiTestIds.adminSecuritySessions,
        merge: true,
        child: TextButton.icon(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: auth.isAuthenticated ? () => context.go(AppRoutes.adminSessions) : null,
          icon: const Icon(Icons.devices_outlined),
          label: Text(strings.authDeviceSessions),
        ),
      ),
      Identified(
        id: UiTestIds.adminSignOut,
        merge: true,
        child: TextButton.icon(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: Text(strings.authSignOut),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    return Identified(
      id: UiTestIds.adminPolicyPage,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, size) {
              if (size.maxWidth < 1080) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.authAdminPolicy,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 20),
                      _policyEditor(auth, strings),
                      const SizedBox(height: 20),
                      _securityActions(auth, strings),
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 224,
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'h',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'haruka',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          strings.authAdminWorkspace,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 36),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.settings_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                strings.authAdminPolicy,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _securityActions(auth, strings),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(48, 36, 48, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(strings.authAdminWorkspace),
                          const SizedBox(height: 45),
                          Text(
                            strings.authAdminPolicy,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 30),
                          _policyEditor(auth, strings),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AccountScaffold extends StatelessWidget {
  const _AccountScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Card(
              child: Padding(padding: const EdgeInsets.all(24), child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

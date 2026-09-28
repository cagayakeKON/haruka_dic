import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

/// In-memory state for the management interface.
final class AdminPreviewState extends ChangeNotifier {
  AdminPreviewState({Set<String>? permissions})
    : _permissions = Set.unmodifiable(permissions ?? defaultPermissions);

  static const defaultPermissions = <String>{
    'admin.login',
    'admin.dashboard.view',
    'admin.user.read',
    'admin.role.read',
    'admin.menu.read',
    'admin.auth_policy.read',
    'admin.auth_policy.update',
    'admin.job.read',
    'admin.audit.read',
  };

  static const _sectionPermissions = <String, String>{
    'overview': 'admin.dashboard.view',
    'users': 'admin.user.read',
    'roles': 'admin.role.read',
    'menus': 'admin.menu.read',
    'policy': 'admin.auth_policy.read',
    'jobs': 'admin.job.read',
    'audit': 'admin.audit.read',
    'usage': 'admin.dashboard.view',
    'security': 'admin.login',
  };

  Set<String> _permissions;
  bool signedIn = false;
  String search = '';
  String registration = 'approval';
  String verification = 'pending';
  String recovery = 'pending';
  String appliedRegistration = 'approval';
  String appliedVerification = 'pending';
  String appliedRecovery = 'pending';
  String? _accountEmail;
  String? _passwordDigest;

  bool get allowsLogin => _permissions.contains('admin.login');

  bool can(String permission) =>
      signedIn && _permissions.contains('admin.login') && _permissions.contains(permission);

  bool canSection(String section) {
    final requiredPermission = _sectionPermissions[section];
    return requiredPermission != null && can(requiredPermission);
  }

  String get firstAccessibleSection =>
      _sectionPermissions.keys.firstWhere(canSection, orElse: () => 'security');

  /// Simulates a fresh admin access projection, including permission revocation.
  void setPermissions(Set<String> permissions) {
    _permissions = Set.unmodifiable(permissions);
    if (!allowsLogin) {
      signOut();
      return;
    }
    if (!can('admin.user.read')) search = '';
    if (!can('admin.auth_policy.read') || !can('admin.auth_policy.update')) {
      _resetPolicyDraft();
    }
    notifyListeners();
  }

  bool get hasPolicyChanges =>
      registration != appliedRegistration ||
      verification != appliedVerification ||
      recovery != appliedRecovery;

  String _digest(String password) => sha256.convert(utf8.encode(password)).toString();

  bool signIn({String? email, String? password}) {
    if (!allowsLogin) return false;
    if (email != null && password != null) {
      final normalizedEmail = email.trim().toLowerCase();
      if (_accountEmail != null &&
          (_accountEmail != normalizedEmail || _passwordDigest != _digest(password))) {
        return false;
      }
      _accountEmail ??= normalizedEmail;
      _passwordDigest ??= _digest(password);
    }
    signedIn = true;
    notifyListeners();
    return true;
  }

  bool changePassword(String currentPassword, String newPassword) {
    if (!can('admin.login') || !matchesCurrentPassword(currentPassword)) {
      return false;
    }
    _passwordDigest = _digest(newPassword);
    signOut();
    return true;
  }

  bool matchesCurrentPassword(String value) =>
      _passwordDigest != null && _passwordDigest == _digest(value);

  bool applyPolicy() {
    if (!can('admin.auth_policy.read') || !can('admin.auth_policy.update') || !hasPolicyChanges) {
      return false;
    }
    appliedRegistration = registration;
    appliedVerification = verification;
    appliedRecovery = recovery;
    notifyListeners();
    return true;
  }

  void signOut() {
    signedIn = false;
    search = '';
    _resetPolicyDraft();
    notifyListeners();
  }

  void _resetPolicyDraft() {
    registration = appliedRegistration;
    verification = appliedVerification;
    recovery = appliedRecovery;
  }

  void setSearch(String value) {
    if (!can('admin.user.read')) return;
    search = value;
    notifyListeners();
  }

  void setRegistration(String value) {
    if (!can('admin.auth_policy.read') || !can('admin.auth_policy.update')) return;
    registration = value;
    notifyListeners();
  }

  void setVerification(String value) {
    if (!can('admin.auth_policy.read') || !can('admin.auth_policy.update')) return;
    verification = value;
    notifyListeners();
  }

  void setRecovery(String value) {
    if (!can('admin.auth_policy.read') || !can('admin.auth_policy.update')) return;
    recovery = value;
    notifyListeners();
  }
}

/// Owns management preview state for one preview app instance.
class AdminPreviewScope extends InheritedWidget {
  const AdminPreviewScope({required this.state, required super.child, super.key});

  final AdminPreviewState state;

  static AdminPreviewState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminPreviewScope>()!.state;

  @override
  bool updateShouldNotify(AdminPreviewScope oldWidget) => state != oldWidget.state;
}

class _AdminShellHosted extends InheritedWidget {
  const _AdminShellHosted({required this.hosted, required super.child});

  final bool hosted;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AdminShellHosted>()?.hosted ?? false;

  @override
  bool updateShouldNotify(_AdminShellHosted oldWidget) => hosted != oldWidget.hosted;
}

/// Keeps the management navigation mounted while section routes change.
class AdminPersistentFrame extends StatelessWidget {
  const AdminPersistentFrame({
    required this.location,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  final String location;
  final ValueChanged<String> onNavigate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = AdminPreviewScope.of(context);
    return AnimatedBuilder(
      animation: state,
      child: child,
      builder: (context, routedChild) {
        if (!state.signedIn || location == AppRoutes.mockAdminLogin) {
          return routedChild ?? const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final hosted = constraints.maxWidth >= 900;
            final section = location.split('/').last;
            return Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: _AdminShellHosted(
                    hosted: hosted,
                    child: routedChild ?? const SizedBox.shrink(),
                  ),
                ),
                if (hosted)
                  SizedBox(
                    width: 224,
                    child: _AdminSidebar(section: section, state: state, onNavigate: onNavigate),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

bool _adminReducedMotion(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<PreviewStoreScope>()?.notifier?.reducedMotion ??
    false;

/// The admin route is Web only. Each section is a distinct presentation widget.
class AdminPage extends StatelessWidget {
  const AdminPage({required this.section, this.previewState, super.key});

  final String section;
  final AdminPreviewState? previewState;

  @override
  Widget build(BuildContext context) {
    final state = previewState ?? AdminPreviewScope.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => section == 'login' || !state.signedIn
          ? _AdminLogin(state: state)
          : _AdminShell(section: section, state: state),
    );
  }
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin({required this.state});
  final AdminPreviewState state;

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool credentialError = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (formKey.currentState?.validate() != true) return;
    if (!widget.state.signIn(email: email.text, password: password.text)) {
      setState(() => credentialError = true);
      password.clear();
      return;
    }
    password.clear();
    context.go(AppRoutes.mockAdminPath(widget.state.firstAccessibleSection));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final hero = ColoredBox(
            color: scheme.primary,
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 88 : 30, wide ? 86 : 26, 38, wide ? 70 : 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdminBrand(onPrimary: true),
                  const Spacer(),
                  _AdminEyebrow(strings.mockAdminLoginEyebrow, onPrimary: true),
                  const SizedBox(height: 26),
                  Text(
                    strings.mockAdminLoginHero,
                    style: Theme.of(context).textTheme.displayMedium
                        ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          );
          final login = ColoredBox(
            color: roles.canvas,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 45),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AdminEyebrow(strings.mockAdminLoginEntry),
                        const SizedBox(height: 17),
                        Text(
                          strings.mockAdminLoginTitle,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 7),
                        const SizedBox(height: 28),
                        Text(
                          strings.mockAdminLoginEmail,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: email,
                          onChanged: (_) => setState(() => credentialError = false),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: strings.mockAdminLoginEmailExample,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || !value.contains('@')
                              ? strings.mockAdminLoginEmailInvalid
                              : null,
                        ),
                        const SizedBox(height: 17),
                        Text(
                          strings.mockAdminLoginPassword,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: password,
                          onChanged: (_) => setState(() => credentialError = false),
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: strings.mockAdminLoginPasswordHint,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.length < 6
                              ? strings.mockAdminLoginPasswordInvalid
                              : null,
                          onFieldSubmitted: (_) => submit(),
                        ),
                        const SizedBox(height: 17),
                        if (credentialError) ...[
                          Text(
                            widget.state.allowsLogin
                                ? strings.mockAdminInvalidCredentials
                                : strings.authNoAdminPermission,
                            style: TextStyle(color: scheme.error),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(onPressed: submit, child: Text(strings.mockAdminLoginAction)),
                        const SizedBox(height: 15),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => context.go(AppRoutes.mockLogin),
                            child: Text(strings.mockAdminBackToClient),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 5, child: hero),
                Expanded(flex: 7, child: login),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 280, child: hero),
                login,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdminShell extends StatelessWidget {
  const _AdminShell({required this.section, required this.state});
  final String section;
  final AdminPreviewState state;

  static const sections = <(String, IconData)>[
    ('overview', Icons.grid_view_outlined),
    ('users', Icons.person_outline),
    ('roles', Icons.shield_outlined),
    ('menus', Icons.layers_outlined),
    ('policy', Icons.settings_outlined),
    ('jobs', Icons.schedule_outlined),
    ('audit', Icons.menu_book_outlined),
    ('usage', Icons.auto_awesome_outlined),
    ('security', Icons.verified_user_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final hosted = _AdminShellHosted.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final narrow = bounds.maxWidth < 960;
        final rail = _AdminSidebar(section: section, state: state);
        return Scaffold(
          backgroundColor: roles.canvas,
          drawer: narrow && !hosted ? Drawer(child: rail) : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!narrow && !hosted) SizedBox(width: 224, child: rail),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 76,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 38),
                          child: Row(
                            children: [
                              if (narrow && !hosted)
                                Builder(
                                  builder: (context) => IconButton(
                                    tooltip: strings.mockAdminOpenNavigation,
                                    onPressed: () => Scaffold.of(context).openDrawer(),
                                    icon: const Icon(Icons.menu),
                                  ),
                                ),
                              Text(
                                strings.mockAdminAudience,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(
                                narrow ? 20 : 34,
                                25,
                                narrow ? 20 : 34,
                                80,
                              ),
                              children: [
                                Text(
                                  state.canSection(section)
                                      ? _sectionLabel(strings, section)
                                      : strings.authNoAdminPermission,
                                  style: Theme.of(context).textTheme.headlineLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 25),
                                if (!state.canSection(section))
                                  _AdminCard(child: Text(strings.authNoAdminPermission))
                                else
                                  AnimatedSwitcher(
                                    layoutBuilder: (currentChild, previousChildren) => Stack(
                                      alignment: Alignment.topLeft,
                                      children: [...previousChildren, ?currentChild],
                                    ),
                                    duration:
                                        HarukaMotion.reduced(
                                          context,
                                          reducedMotion: _adminReducedMotion(context),
                                        )
                                        ? Duration.zero
                                        : const Duration(milliseconds: 230),
                                    child: KeyedSubtree(
                                      key: ValueKey(section),
                                      child: switch (section) {
                                        'overview' => _AdminOverview(state: state),
                                        'users' => _AdminUsers(state: state),
                                        'roles' => _AdminRoles(state: state),
                                        'menus' => const _AdminMenus(),
                                        'policy' => _AdminPolicy(state: state),
                                        'jobs' => _AdminJobs(state: state),
                                        'audit' => const _AdminAudit(),
                                        'usage' => const _AdminUsage(),
                                        'security' => _AdminSecurity(state: state),
                                        _ => _AdminCard(child: Text(strings.authNoAdminPermission)),
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({required this.section, required this.state, this.onNavigate});
  final String section;
  final AdminPreviewState state;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    void navigate(String path) {
      if (onNavigate != null) {
        onNavigate!(path);
      } else {
        context.go(path);
      }
    }

    return Material(
      color: roles.content,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 18),
        child: Column(
          children: [
            Align(alignment: Alignment.centerLeft, child: _AdminBrand(onPrimary: false)),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                strings.mockAdminRibbon,
                style: TextStyle(color: scheme.primary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 29),
            Expanded(
              child: ListView(
                children: [
                  for (final (id, icon) in _AdminShell.sections)
                    if (state.canSection(id))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: section == id ? roles.selected : roles.content,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            minTileHeight: 52,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                            horizontalTitleGap: 12,
                            selected: section == id,
                            selectedColor: scheme.primary,
                            textColor: scheme.onSurfaceVariant,
                            iconColor: scheme.onSurfaceVariant,
                            onTap: () => navigate(AppRoutes.mockAdminPath(id)),
                            leading: Icon(icon, size: 19),
                            title: Text(
                              _sectionLabel(strings, id),
                              style: TextStyle(
                                fontWeight: section == id ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            trailing: section == id
                                ? CircleAvatar(radius: 3, backgroundColor: scheme.primary)
                                : null,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: roles.signal,
                child: Text(strings.mockAdminAvatar, style: TextStyle(color: roles.onSignal)),
              ),
              title: Text(strings.mockAdminAccountName),
              subtitle: Text(strings.mockAdminAccountLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => navigate(AppRoutes.mockAdminPath('security')),
            ),
          ],
        ),
      ),
    );
  }
}

String _sectionLabel(AppLocalizations strings, String section) => switch (section) {
  'overview' => strings.mockAdminOverview,
  'users' => strings.mockAdminUsers,
  'roles' => strings.mockAdminRoles,
  'menus' => strings.mockAdminMenus,
  'policy' => strings.mockAdminPolicy,
  'jobs' => strings.mockAdminJobs,
  'audit' => strings.mockAdminAudit,
  'usage' => strings.mockAdminUsage,
  'security' => strings.mockAdminSecurityNav,
  _ => strings.mockAdminOverview,
};

class _AdminBrand extends StatelessWidget {
  const _AdminBrand({required this.onPrimary});
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 35,
          height: 35,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPrimary ? Color.lerp(scheme.primary, scheme.onPrimary, .15) : scheme.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            'h',
            style: TextStyle(color: scheme.onPrimary, fontSize: 25, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'haruka',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 23,
            color: onPrimary ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _AdminEyebrow extends StatelessWidget {
  const _AdminEyebrow(this.label, {this.onPrimary = false});
  final String label;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final roles = HarukaColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 6,
          decoration: BoxDecoration(color: roles.signal, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: onPrimary
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child, this.padding = const EdgeInsets.all(26)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: HarukaColors.of(context).content,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _AdminStat extends StatelessWidget {
  const _AdminStat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => _AdminCard(
    padding: const EdgeInsets.all(23),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

class _AdminTag extends StatelessWidget {
  const _AdminTag(this.label, {this.positive = false, this.warning = false});
  final String label;
  final bool positive;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final roles = HarukaColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = positive
        ? roles.positive
        : warning
        ? roles.warning
        : scheme.primary;
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

Widget _adminTable(BuildContext context, List<DataColumn> columns, List<DataRow> rows) =>
    _AdminCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: columns,
              rows: rows,
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

void _showAdminItem(
  BuildContext context,
  String title,
  AdminPreviewState state,
  String requiredPermission,
) {
  if (!state.can(requiredPermission)) return;
  final strings = AppLocalizations.of(context);
  unawaited(
    showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(
        context,
        reducedMotion: _adminReducedMotion(context),
      ),
      builder: (context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) => AlertDialog(
          title: Text(strings.mockAdminSummary),
          content: SizedBox(
            width: 440,
            child: !state.can(requiredPermission)
                ? Text(strings.authNoAdminPermission)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 14),
                      Text(strings.mockAdminSummaryStatus),
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
    ),
  );
}

class _AdminOverview extends StatelessWidget {
  const _AdminOverview({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _AdminStat('128', strings.mockAdminAccountCount)),
            const SizedBox(width: 20),
            Expanded(child: _AdminStat('4', strings.mockAdminPendingJobs)),
            const SizedBox(width: 20),
            Expanded(child: _AdminStat('99.2%', strings.mockAdminRequestSuccess)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AdminEyebrow(strings.mockAdminNeedsAttention),
                    const SizedBox(height: 15),
                    Text(
                      strings.mockAdminQueueAlert,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    if (state.can('admin.job.read'))
                      OutlinedButton(
                        onPressed: () => context.go(AppRoutes.mockAdminPath('jobs')),
                        child: Text(strings.mockAdminViewJobs),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AdminEyebrow(strings.mockAdminPermissionChanges),
                    const SizedBox(height: 15),
                    Text(strings.mockAdminRoleAlert, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    if (state.can('admin.role.read'))
                      OutlinedButton(
                        onPressed: () => context.go(AppRoutes.mockAdminPath('roles')),
                        child: Text(strings.mockAdminViewRoles),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdminUsers extends StatelessWidget {
  const _AdminUsers({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final data = <(String, String, String, String)>[
      (
        strings.mockAdminLearnerA,
        'learner-a@example.test',
        strings.mockAdminNormal,
        strings.mockAdminClientAudience,
      ),
      (
        strings.mockAdminLearnerB,
        'learner-b@example.test',
        strings.mockAdminPendingApproval,
        strings.mockAdminInactive,
      ),
      (
        strings.mockAdminOperator,
        'operator@example.test',
        strings.mockAdminNormal,
        strings.mockAdminAudience,
      ),
    ];
    final filtered = data
        .where(
          (row) => '${row.$1} ${row.$2} ${row.$3} ${row.$4}'.toLowerCase().contains(
            state.search.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(strings.mockAdminUserList, style: Theme.of(context).textTheme.titleLarge),
            ),
            SizedBox(
              width: 260,
              child: TextFormField(
                initialValue: state.search,
                onChanged: state.setSearch,
                decoration: InputDecoration(
                  hintText: strings.mockAdminSearchUsers,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        if (filtered.isEmpty)
          _AdminCard(child: Text(strings.mockAdminNoUsers))
        else
          _adminTable(
            context,
            [
              DataColumn(label: Text(strings.mockAdminUserColumn)),
              DataColumn(label: Text(strings.mockAdminEmailColumn)),
              DataColumn(label: Text(strings.mockAdminStatusColumn)),
              DataColumn(label: Text(strings.mockAdminAudienceColumn)),
              DataColumn(label: Text(strings.mockAdminActionColumn)),
            ],
            [
              for (final row in filtered)
                DataRow(
                  cells: [
                    DataCell(Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(row.$2)),
                    DataCell(
                      _AdminTag(
                        row.$3,
                        positive: row.$3 == strings.mockAdminNormal,
                        warning: row.$3 != strings.mockAdminNormal,
                      ),
                    ),
                    DataCell(Text(row.$4)),
                    DataCell(
                      TextButton(
                        onPressed: () => _showAdminItem(context, row.$1, state, 'admin.user.read'),
                        child: Text(strings.mockAdminViewOperationalSummary),
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _AdminRoles extends StatelessWidget {
  const _AdminRoles({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final roles = <(String, String, int, String)>[
      (
        strings.mockAdminLearnerRole,
        strings.mockAdminClientAudience,
        126,
        strings.mockAdminDefault,
      ),
      (strings.mockAdminSupportRole, strings.mockAdminAudience, 2, strings.mockAdminRestricted),
      (strings.mockAdminSuperRole, strings.mockAdminAudience, 1, strings.mockAdminProtected),
    ];
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: _adminTable(
          context,
          [
            DataColumn(label: Text(strings.mockAdminRoleColumn)),
            DataColumn(label: Text(strings.mockAdminAudienceColumn)),
            DataColumn(label: Text(strings.mockAdminMembersColumn)),
            DataColumn(label: Text(strings.mockAdminStatusColumn)),
            const DataColumn(label: SizedBox.shrink()),
          ],
          [
            for (final role in roles)
              DataRow(
                cells: [
                  DataCell(Text(role.$1)),
                  DataCell(Text(role.$2)),
                  DataCell(Text('${role.$3}')),
                  DataCell(_AdminTag(role.$4, warning: role.$4 == strings.mockAdminProtected)),
                  DataCell(
                    TextButton(
                      onPressed: () => _showAdminItem(
                        context,
                        strings.mockAdminRoleSummary(role.$1),
                        state,
                        'admin.role.read',
                      ),
                      child: Text(strings.mockAdminPreview),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminMenus extends StatelessWidget {
  const _AdminMenus();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final client = [
      strings.mockAdminMenuLibrary,
      strings.mockAdminMenuNotebooks,
      strings.mockAdminMenuExercises,
      strings.mockAdminMenuMistakes,
      strings.mockAdminMenuQuery,
      strings.mockAdminMenuDiagnosis,
      strings.mockAdminMenuSettings,
    ];
    final admin = [
      strings.mockAdminUsers,
      strings.mockAdminRoles,
      strings.mockAdminPolicy,
      strings.mockAdminJobs,
      strings.mockAdminAudit,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _AdminMenuCard(title: strings.mockAdminClientNavigation, items: client),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _AdminMenuCard(title: strings.mockAdminAdminNavigation, items: admin),
        ),
      ],
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  const _AdminMenuCard({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 17),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item)),
                  _AdminTag(strings.mockAdminVisibleWhenAuthorized),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
          ],
        ],
      ),
    );
  }
}

class _AdminPolicy extends StatelessWidget {
  const _AdminPolicy({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.can('admin.auth_policy.update'))
            Expanded(
              flex: 3,
              child: _AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dropdown(
                      context,
                      label: strings.mockAdminRegistrationMode,
                      value: state.registration,
                      choices: {
                        'approval': strings.mockAdminApprovalExample,
                        'closed': strings.mockAdminClosedExample,
                      },
                      onChanged: state.setRegistration,
                    ),
                    const SizedBox(height: 18),
                    _dropdown(
                      context,
                      label: strings.mockAdminEmailVerification,
                      value: state.verification,
                      choices: {
                        'pending': strings.mockAdminChooseLater,
                        'enabled': strings.mockAdminVerifyWhenEnabled,
                      },
                      onChanged: state.setVerification,
                    ),
                    const SizedBox(height: 18),
                    _dropdown(
                      context,
                      label: strings.mockAdminAccountRecovery,
                      value: state.recovery,
                      choices: {
                        'pending': strings.mockAdminChooseLater,
                        'email': strings.mockAdminEmailRecovery,
                        'manual': strings.mockAdminManualRecovery,
                      },
                      onChanged: state.setRecovery,
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: state.hasPolicyChanges
                            ? () => _showPolicyPreview(context, state)
                            : null,
                        child: Text(strings.mockAdminPreviewPolicy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (state.can('admin.auth_policy.update')) const SizedBox(width: 22),
          Expanded(
            flex: 2,
            child: _AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.mockAdminCurrentPolicy,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  Text(_registrationLabel(strings, state.appliedRegistration)),
                  const SizedBox(height: 11),
                  Text(_verificationLabel(strings, state.appliedVerification)),
                  const SizedBox(height: 11),
                  Text(_recoveryLabel(strings, state.appliedRecovery)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    BuildContext context, {
    required String label,
    required String value,
    required Map<String, String> choices,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    key: ValueKey(label),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    items: [
      for (final choice in choices.entries)
        DropdownMenuItem(value: choice.key, child: Text(choice.value)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

String _registrationLabel(AppLocalizations strings, String value) =>
    value == 'closed' ? strings.mockAdminClosedExample : strings.mockAdminApprovalExample;

String _verificationLabel(AppLocalizations strings, String value) =>
    value == 'enabled' ? strings.mockAdminVerifyWhenEnabled : strings.mockAdminChooseLater;

String _recoveryLabel(AppLocalizations strings, String value) => switch (value) {
  'email' => strings.mockAdminEmailRecovery,
  'manual' => strings.mockAdminManualRecovery,
  _ => strings.mockAdminChooseLater,
};

void _showPolicyPreview(BuildContext context, AdminPreviewState state) {
  if (!state.can('admin.auth_policy.read') || !state.can('admin.auth_policy.update')) return;
  final strings = AppLocalizations.of(context);
  unawaited(
    showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(
        context,
        reducedMotion: _adminReducedMotion(context),
      ),
      builder: (context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) => AlertDialog(
          title: Text(strings.mockAdminPolicyPreviewTitle),
          content: SizedBox(
            width: 440,
            child: !state.can('admin.auth_policy.read') || !state.can('admin.auth_policy.update')
                ? Text(strings.authNoAdminPermission)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${strings.mockAdminRegistrationMode}: ${_registrationLabel(strings, state.registration)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${strings.mockAdminEmailVerification}: ${_verificationLabel(strings, state.verification)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${strings.mockAdminAccountRecovery}: ${_recoveryLabel(strings, state.recovery)}',
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.mockAdminClose),
            ),
            FilledButton(
              onPressed:
                  state.can('admin.auth_policy.read') &&
                      state.can('admin.auth_policy.update') &&
                      state.hasPolicyChanges
                  ? () {
                      final applied = state.applyPolicy();
                      Navigator.pop(context);
                      if (applied) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(strings.mockAdminPolicyApplied)));
                      }
                    }
                  : null,
              child: Text(strings.mockAdminApplyPolicy),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AdminJobs extends StatelessWidget {
  const _AdminJobs({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final jobs = <(String, String, String, String)>[
      (
        'JOB-D100',
        strings.mockAdminMaterialParse,
        strings.mockAdminPublishAfterValidation,
        strings.mockAdminCompleted,
      ),
      (
        'JOB-D101',
        strings.mockAdminModelCall,
        strings.mockAdminWaitingOwnCredential,
        strings.mockAdminNeedsConfiguration,
      ),
      (
        'JOB-D102',
        strings.mockAdminAudioGeneration,
        strings.mockAdminRetryCheck,
        strings.mockAdminNeedsAction,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.mockAdminJobSummary, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 18),
        _adminTable(
          context,
          [
            DataColumn(label: Text(strings.mockAdminJobReferenceColumn)),
            DataColumn(label: Text(strings.mockAdminTypeColumn)),
            DataColumn(label: Text(strings.mockAdminStageColumn)),
            DataColumn(label: Text(strings.mockAdminStatusColumn)),
            const DataColumn(label: SizedBox.shrink()),
          ],
          [
            for (final job in jobs)
              DataRow(
                cells: [
                  DataCell(Text(job.$1)),
                  DataCell(Text(job.$2)),
                  DataCell(Text(job.$3)),
                  DataCell(
                    _AdminTag(
                      job.$4,
                      positive: job.$4 == strings.mockAdminCompleted,
                      warning: job.$4 != strings.mockAdminCompleted,
                    ),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: () => _showAdminItem(context, job.$1, state, 'admin.job.read'),
                      child: Text(strings.mockAdminViewSummary),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _AdminAudit extends StatelessWidget {
  const _AdminAudit();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final audit = <(String, String, String, String)>[
      (
        '09:42',
        strings.mockAdminRoleGrantPreview,
        strings.mockAdminManagementPermissions,
        strings.mockAdminAwaitingSubmission,
      ),
      (
        '09:16',
        strings.mockAdminSessionRevocation,
        strings.mockAdminOwnDevice,
        strings.mockAdminSubmittedExample,
      ),
      (
        strings.mockAdminYesterday,
        strings.mockAdminReadRegistrationPolicy,
        strings.mockAdminRegistrationEntry,
        strings.mockAdminReadExample,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminTable(
          context,
          [
            DataColumn(label: Text(strings.mockAdminTimeColumn)),
            DataColumn(label: Text(strings.mockAdminActionKindColumn)),
            DataColumn(label: Text(strings.mockAdminTargetScopeColumn)),
            DataColumn(label: Text(strings.mockAdminResultColumn)),
          ],
          [
            for (final record in audit)
              DataRow(
                cells: [
                  DataCell(Text(record.$1)),
                  DataCell(Text(record.$2)),
                  DataCell(Text(record.$3)),
                  DataCell(Text(record.$4)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _AdminUsage extends StatelessWidget {
  const _AdminUsage();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final usage = <(String, String, String, String)>[
      (
        strings.mockAdminTextModel,
        '210',
        strings.mockAdminTokenCount('1,284,000'),
        strings.mockAdminAttempts(8),
      ),
      (
        strings.mockAdminVisionModel,
        '38',
        strings.mockAdminTokenCount('184,000'),
        strings.mockAdminAttempts(3),
      ),
      (
        strings.mockAdminTts,
        '36',
        strings.mockAdminPartialAudioSeconds,
        strings.mockAdminAttempt(1),
      ),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _AdminStat('284', strings.mockAdminProviderAttempts)),
            const SizedBox(width: 20),
            Expanded(child: _AdminStat('12', strings.mockAdminUnknownUsageAttempts)),
            const SizedBox(width: 20),
            Expanded(child: _AdminStat('3', strings.mockAdminVisibleProviderCategories)),
          ],
        ),
        const SizedBox(height: 20),
        _adminTable(
          context,
          [
            DataColumn(label: Text(strings.mockAdminCapabilityColumn)),
            DataColumn(label: Text(strings.mockAdminActualCallsColumn)),
            DataColumn(label: Text(strings.mockAdminKnownUsageColumn)),
            DataColumn(label: Text(strings.mockAdminUnknownUsageColumn)),
          ],
          [
            for (final record in usage)
              DataRow(
                cells: [
                  DataCell(Text(record.$1)),
                  DataCell(Text(record.$2)),
                  DataCell(Text(record.$3)),
                  DataCell(Text(record.$4)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _AdminSecurity extends StatelessWidget {
  const _AdminSecurity({required this.state});
  final AdminPreviewState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.mockAdminCurrentSession, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(strings.mockAdminOnlineDemoSession),
          const SizedBox(height: 19),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(
                onPressed: () => unawaited(
                  showHarukaDialog<void>(
                    context: context,
                    animationStyle: HarukaMotion.dialogStyle(
                      context,
                      reducedMotion: _adminReducedMotion(context),
                    ),
                    builder: (_) =>
                        _AdminChangePasswordDialog(state: state, router: GoRouter.of(context)),
                  ),
                ),
                child: Text(strings.mockAdminChangePassword),
              ),
              TextButton(
                onPressed: () {
                  state.signOut();
                  context.go(AppRoutes.mockAdminLogin);
                },
                style: TextButton.styleFrom(foregroundColor: HarukaColors.of(context).danger),
                child: Text(strings.mockAdminLogout),
              ),
            ],
          ),
        ],
      ),
    );
    final client = _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.mockAdminSwitchToClient, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () {
              state.signOut();
              context.go(AppRoutes.mockLogin);
            },
            child: Text(strings.mockAdminClientLogin),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [session, const SizedBox(height: 16), client],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: session),
            const SizedBox(width: 22),
            Expanded(flex: 2, child: client),
          ],
        );
      },
    );
  }
}

class _AdminChangePasswordDialog extends StatefulWidget {
  const _AdminChangePasswordDialog({required this.state, required this.router});
  final AdminPreviewState state;
  final GoRouter router;

  @override
  State<_AdminChangePasswordDialog> createState() => _AdminChangePasswordDialogState();
}

class _AdminChangePasswordDialogState extends State<_AdminChangePasswordDialog> {
  final formKey = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onAccessChanged);
  }

  void _onAccessChanged() {
    if (!widget.state.can('admin.login')) {
      current.clear();
      next.clear();
      confirmation.clear();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAccessChanged);
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void submit() {
    if (!widget.state.can('admin.login')) return;
    if (formKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).mockAdminPasswordUpdated;
    if (!widget.state.changePassword(current.text, next.text)) return;
    Navigator.of(context).pop();
    widget.router.go(AppRoutes.mockAdminLogin);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.mockAdminChangePassword),
      content: SizedBox(
        width: 430,
        child: !widget.state.can('admin.login')
            ? Text(strings.authNoAdminPermission)
            : Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: current,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: strings.mockAdminCurrentPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || !widget.state.matchesCurrentPassword(value)
                          ? strings.mockAdminCurrentPasswordIncorrect
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: next,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: strings.mockAdminNewPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 8) {
                          return strings.mockAdminPasswordTooShort;
                        }
                        if (value == current.text) return strings.mockAdminPasswordUnchanged;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmation,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: strings.mockAdminConfirmPassword,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value != next.text ? strings.mockAdminPasswordMismatch : null,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
        FilledButton(
          onPressed: widget.state.can('admin.login') ? submit : null,
          child: Text(strings.mockAdminSavePassword),
        ),
      ],
    );
  }
}

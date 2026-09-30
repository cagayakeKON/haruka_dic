import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/routes.dart';
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

/// Live menu layout inside the confirmed admin shell.
class AdminMenuGovernance extends StatefulWidget {
  const AdminMenuGovernance({required this.auth, super.key});

  final AuthController auth;

  @override
  State<AdminMenuGovernance> createState() => _AdminMenuGovernanceState();
}

class _MenuScope {
  const _MenuScope({
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

  static _MenuScope? capture(AuthController auth) {
    final access = auth.access;
    if (!auth.isAuthenticated || !auth.admin || access == null || access.audience != 'admin') {
      return null;
    }
    final rights = [
      'admin.menu.read',
      'admin.menu.update',
      'admin.user.read',
      'admin.role.read',
    ].map((code) => auth.access?.allows(code) == true ? code : '').join('|');
    return _MenuScope(
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

  bool same(_MenuScope? other) =>
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
        next.rights == rights;
  }
}

class _AdminMenuGovernanceState extends State<AdminMenuGovernance> {
  _MenuScope? _scope;
  List<MenuRead>? _menus;
  MenuCatalogRead? _catalog;
  List<GovernedAccountRead>? _accounts;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    _capture();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    final next = _MenuScope.capture(widget.auth);
    if (_scope?.same(next) ?? next == null) return;
    setState(_capture);
  }

  void _capture() {
    final scope = _MenuScope.capture(widget.auth);
    _scope = scope;
    _menus = null;
    _catalog = null;
    _accounts = null;
    _error = null;
    if (scope != null && scope.allows('admin.menu.read')) unawaited(_load(scope));
  }

  Future<void> _load(_MenuScope scope) async {
    try {
      final menus = await widget.auth.adminMenus();
      final catalog = await widget.auth.adminMenuCatalog();
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _menus = menus;
        _catalog = catalog;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted || !scope.isCurrent) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  void _replace(List<MenuRead> menus) {
    final scope = _scope;
    if (!mounted || scope == null || !scope.isCurrent) return;
    setState(() => _menus = menus);
  }

  Future<void> _edit(MenuRead menu) async {
    final scope = _scope;
    final menus = _menus;
    final catalog = _catalog;
    if (scope == null || menus == null || catalog == null || !scope.isCurrent) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _MenuDialog(
          scope: scope,
          menu: menu,
          menus: menus,
          catalog: catalog,
          onMenus: _replace,
        ),
      ),
    );
  }

  Future<void> _create(String audience) async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _GroupDialog(scope: scope, audience: audience, onMenus: _replace),
      ),
    );
  }

  Future<void> _preview(String audience) async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    if (_accounts == null && scope.allows('admin.user.read')) {
      try {
        final accounts = await widget.auth.adminAccounts();
        if (!mounted || !scope.isCurrent) return;
        setState(() => _accounts = accounts);
      } on ApiFailure catch (error) {
        if (!mounted) return;
        setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
        return;
      }
    }
    if (!mounted) return;
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _PreviewDialog(scope: scope, audience: audience, accounts: _accounts ?? const []),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scope = _scope;
    final menus = _menus;
    if (scope == null || menus == null) {
      return _error == null ? const CircularProgressIndicator() : Text(_error!);
    }
    return Identified(
      id: UiTestIds.adminMenusPage,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _MenuColumn(
              title: strings.mockAdminClientNavigation,
              audience: 'client',
              menus: menus,
              scope: scope,
              onEdit: _edit,
              onCreate: _create,
              onPreview: _preview,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: _MenuColumn(
              title: strings.mockAdminAdminNavigation,
              audience: 'admin',
              menus: menus,
              scope: scope,
              onEdit: _edit,
              onCreate: _create,
              onPreview: _preview,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuColumn extends StatelessWidget {
  const _MenuColumn({
    required this.title,
    required this.audience,
    required this.menus,
    required this.scope,
    required this.onEdit,
    required this.onCreate,
    required this.onPreview,
  });

  final String title;
  final String audience;
  final List<MenuRead> menus;
  final _MenuScope scope;
  final Future<void> Function(MenuRead menu) onEdit;
  final Future<void> Function(String audience) onCreate;
  final Future<void> Function(String audience) onPreview;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rows = menus.where((menu) => menu.audience == audience).toList();
    return Material(
      color: HarukaColors.of(context).content,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            for (final menu in rows) ...[
              InkWell(
                onTap: scope.allows('admin.menu.update') ? () => onEdit(menu) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 17),
                      const SizedBox(width: 12),
                      Expanded(child: Text(menu.title)),
                      _MenuTag(
                        menu.enabled
                            ? strings.mockAdminVisibleWhenAuthorized
                            : strings.adminMenuHidden,
                        hidden: !menu.enabled,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: scheme.outline),
            ],
            if (scope.allows('admin.menu.update'))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onCreate(audience),
                  child: Text(strings.adminMenuGroup),
                ),
              ),
            if (scope.allows('admin.user.read'))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onPreview(audience),
                  child: Text(strings.adminMenuPreview),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuTag extends StatelessWidget {
  const _MenuTag(this.label, {required this.hidden});

  final String label;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final color = hidden ? HarukaColors.of(context).warning : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _MenuDialog extends StatefulWidget {
  const _MenuDialog({
    required this.scope,
    required this.menu,
    required this.menus,
    required this.catalog,
    required this.onMenus,
  });

  final _MenuScope scope;
  final MenuRead menu;
  final List<MenuRead> menus;
  final MenuCatalogRead catalog;
  final ValueChanged<List<MenuRead>> onMenus;

  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  late final TextEditingController _title;
  late final TextEditingController _order;
  late String? _icon;
  late String? _parent;
  late bool _hidden;
  late Set<String> _extras;
  var _busy = false;
  var _conflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.menu.title);
    _order = TextEditingController(text: '${widget.menu.sortOrder}');
    _icon = widget.menu.iconKey;
    _parent = widget.menu.parentMenuId;
    _hidden = !widget.menu.enabled;
    _extras = widget.menu.permissionCodes.toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final order = int.tryParse(_order.text.trim());
    if (order == null || order < 0 || order > 100000) {
      setState(() => _error = AppLocalizations.of(context).adminMenuOrderError);
      return;
    }
    setState(() => _busy = true);
    try {
      final next = MenuRead(
        id: widget.menu.id,
        code: widget.menu.code,
        audience: widget.menu.audience,
        routeKey: widget.menu.routeKey,
        componentKey: widget.menu.componentKey,
        parentMenuId: _parent,
        title: _title.text.trim(),
        iconKey: _icon,
        sortOrder: order,
        permissionMatch: widget.menu.permissionMatch,
        enabled: !_hidden,
        floor: widget.menu.floor,
        permissionCodes: _extras.toList(),
        revision: widget.menu.revision,
      );
      final result = await widget.scope.auth.replaceAdminMenuLayout([next]);
      if (!mounted || !widget.scope.isCurrent) return;
      widget.onMenus(result.menus);
      Navigator.of(context).pop();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiCatalog.message(AppLocalizations.of(context), error.code);
        _conflict = error.code == 'REVISION_CONFLICT';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final menus = await widget.scope.auth.adminMenus();
      if (!mounted || !widget.scope.isCurrent) return;
      widget.onMenus(menus);
      Navigator.of(context).pop();
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
    final parents = [
      for (final menu in widget.menus)
        if (menu.audience == widget.menu.audience && menu.id != widget.menu.id) menu,
    ];
    final choices = [
      for (final choice in widget.catalog.permissionCodes)
        if (choice.audience == widget.menu.audience && !widget.menu.floor.contains(choice.code))
          choice.code,
    ];
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    return Identified(
      id: UiTestIds.adminMenuDialog,
      child: AlertDialog(
        title: Text(widget.menu.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: strings.mockAdminMenus),
              ),
              const SizedBox(height: 8),
              Identified(
                id: UiTestIds.adminMenuOrder,
                child: TextField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: strings.adminMenuOrder),
                ),
              ),
              Identified(
                id: UiTestIds.adminMenuIcon,
                child: DropdownButtonFormField<String>(
                  initialValue: _icon,
                  decoration: InputDecoration(labelText: strings.adminMenuIcon),
                  items: [
                    for (final icon in widget.catalog.icons)
                      DropdownMenuItem(value: icon, child: Text(icon)),
                  ],
                  onChanged: _busy ? null : (value) => setState(() => _icon = value),
                ),
              ),
              DropdownButton<String?>(
                value: _parent,
                items: [
                  DropdownMenuItem(value: null, child: Text(strings.adminMenuTop)),
                  for (final menu in parents)
                    DropdownMenuItem(value: menu.id, child: Text(menu.title)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _parent = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hidden,
                onChanged: _busy ? null : (value) => setState(() => _hidden = value),
                title: Text(strings.adminMenuHide),
              ),
              Text(strings.adminMenuHideNote),
              const SizedBox(height: 8),
              Text(strings.adminMenuFeatureNote),
              if (widget.scope.allows('admin.role.read'))
                TextButton(
                  onPressed: () =>
                      GoRouter.maybeOf(context)?.go(AppRoutes.adminSectionPath('roles')),
                  child: Text(strings.adminMenuOpenRoles),
                ),
              if (choices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(strings.adminMenuExtra),
                for (final code in choices)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _extras.contains(code),
                    onChanged: _busy
                        ? null
                        : (selected) => setState(() {
                            if (selected ?? false) {
                              _extras.add(code);
                            } else {
                              _extras.remove(code);
                            }
                          }),
                    title: Text(code),
                    controlAffinity: ListTileControlAffinity.leading,
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
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(strings.mockAdminClose),
          ),
          Identified(
            id: UiTestIds.adminMenuSave,
            merge: true,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(strings.adminMenuSave),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.scope, required this.audience, required this.onMenus});

  final _MenuScope scope;
  final String audience;
  final ValueChanged<List<MenuRead>> onMenus;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final _code = TextEditingController();
  final _title = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.scope.auth.createAdminMenuGroup(
        _code.text.trim(),
        widget.audience,
        _title.text.trim(),
      );
      if (!mounted || !widget.scope.isCurrent) return;
      widget.onMenus(result.menus);
      Navigator.of(context).pop();
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
    return AlertDialog(
      title: Text(strings.adminMenuGroup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            decoration: InputDecoration(labelText: strings.adminMenuCode),
          ),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: strings.mockAdminMenus),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(strings.mockAdminClose),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(strings.adminMenuGroup)),
      ],
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.scope, required this.audience, required this.accounts});

  final _MenuScope scope;
  final String audience;
  final List<GovernedAccountRead> accounts;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  List<NavigationItem>? _navigation;
  String? _error;

  Future<void> _open(GovernedAccountRead account) async {
    try {
      final preview = await widget.scope.auth.previewAdminMenus(account.userId, widget.audience);
      if (!mounted || !widget.scope.isCurrent) return;
      setState(() {
        _navigation = preview.navigation;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (!widget.scope.isCurrent) return _closedGovernanceDialog(context);
    return AlertDialog(
      title: Text(strings.adminMenuPreview),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final account in widget.accounts)
              TextButton(
                onPressed: () => _open(account),
                child: Text(
                  account.displayName?.isNotEmpty == true ? account.displayName! : account.email,
                ),
              ),
            if (_navigation != null)
              for (final item in _navigation!) Text(item.title),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.mockAdminClose),
        ),
      ],
    );
  }
}

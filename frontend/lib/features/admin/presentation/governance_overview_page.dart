import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/generated/api_catalog.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/identified.dart';

/// Rebuilds an open dialog when the captured authorization scope stops matching.
class GovernanceDialogGate extends StatefulWidget {
  const GovernanceDialogGate({
    required this.auth,
    required this.current,
    required this.child,
    super.key,
  });

  final Listenable auth;
  final bool Function() current;
  final Widget child;

  @override
  State<GovernanceDialogGate> createState() => _GovernanceDialogGateState();
}

class _GovernanceDialogGateState extends State<GovernanceDialogGate> {
  var _open = true;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    _open = widget.current();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final open = widget.current();
    if (!mounted || open == _open) return;
    setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.child;
    final strings = AppLocalizations.of(context);
    return AlertDialog(
      content: Text(strings.authNoAdminPermission),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
      ],
    );
  }
}

/// Identity counts inside the confirmed admin shell. Jobs and usage stay closed.
class AdminGovernanceOverview extends StatefulWidget {
  const AdminGovernanceOverview({required this.auth, super.key});

  final AuthController auth;

  @override
  State<AdminGovernanceOverview> createState() => _AdminGovernanceOverviewState();
}

class _SummaryScope {
  const _SummaryScope({
    required this.auth,
    required this.endpoint,
    required this.instanceId,
    required this.userId,
    required this.sessionRef,
    required this.actionEpoch,
    required this.userVersion,
    required this.securityEpoch,
    required this.allowed,
  });

  final AuthController auth;
  final Uri endpoint;
  final String instanceId;
  final String userId;
  final String sessionRef;
  final int actionEpoch;
  final int userVersion;
  final int? securityEpoch;
  final bool allowed;

  static _SummaryScope? capture(AuthController auth) {
    final access = auth.access;
    if (!auth.isAuthenticated || !auth.admin || access == null || access.audience != 'admin') {
      return null;
    }
    return _SummaryScope(
      auth: auth,
      endpoint: auth.repository.api.endpoint,
      instanceId: auth.boundInstanceId,
      userId: access.userId,
      sessionRef: access.sessionRef,
      actionEpoch: auth.actionEpoch,
      userVersion: access.authzVersion.user,
      securityEpoch: access.securityEpoch,
      allowed: access.allows('admin.dashboard.view'),
    );
  }

  bool same(_SummaryScope? other) =>
      other != null &&
      identical(auth, other.auth) &&
      endpoint == other.endpoint &&
      instanceId == other.instanceId &&
      userId == other.userId &&
      sessionRef == other.sessionRef &&
      actionEpoch == other.actionEpoch &&
      userVersion == other.userVersion &&
      securityEpoch == other.securityEpoch &&
      allowed == other.allowed;

  bool get isCurrent {
    final next = capture(auth);
    return next != null && same(next);
  }
}

class _AdminGovernanceOverviewState extends State<AdminGovernanceOverview> {
  _SummaryScope? _scope;
  GovernanceSummaryRead? _summary;
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
    final next = _SummaryScope.capture(widget.auth);
    if (_scope?.same(next) ?? next == null) return;
    setState(_capture);
  }

  void _capture() {
    final scope = _SummaryScope.capture(widget.auth);
    _scope = scope;
    _summary = null;
    _error = null;
    if (scope != null && scope.allowed) unawaited(_load(scope));
  }

  Future<void> _load(_SummaryScope scope) async {
    try {
      final summary = await scope.auth.adminGovernanceSummary();
      if (!mounted || !scope.isCurrent) return;
      setState(() {
        _summary = summary;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted || !scope.isCurrent) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final summary = _summary;
    final allowed = _scope?.allowed == true;
    return Identified(
      id: UiTestIds.adminGovernancePage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!allowed)
            _GovernanceCard(child: Text(strings.authNoAdminPermission))
          else if (_error != null)
            _GovernanceCard(child: Text(_error!))
          else if (summary == null)
            const _GovernanceCard(child: LinearProgressIndicator())
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _GovernanceStat('${summary.accountsActive}', strings.adminGovernanceActive),
                _GovernanceStat('${summary.approvalsPending}', strings.adminGovernanceApprovals),
                _GovernanceStat('${summary.rolesEnabled}', strings.adminGovernanceRoles),
                _GovernanceStat('${summary.accountsPending}', strings.adminGovernancePending),
                _GovernanceStat('${summary.accountsDisabled}', strings.adminGovernanceDisabled),
                _GovernanceStat(
                  '${summary.openManualRecoveries}',
                  strings.adminGovernanceRecoveries,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GovernanceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${strings.adminGovernanceRevision} ${summary.authorizationRevision}'),
                  const SizedBox(height: 8),
                  Text(strings.adminGovernanceLater),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Append-only audit chronology. The detail dialog uses the loaded row.
class AdminAuditEvents extends StatefulWidget {
  const AdminAuditEvents({required this.auth, super.key});

  final AuthController auth;

  @override
  State<AdminAuditEvents> createState() => _AdminAuditEventsState();
}

class _AuditScope {
  const _AuditScope({
    required this.auth,
    required this.endpoint,
    required this.instanceId,
    required this.userId,
    required this.sessionRef,
    required this.actionEpoch,
    required this.userVersion,
    required this.securityEpoch,
    required this.allowed,
  });

  final AuthController auth;
  final Uri endpoint;
  final String instanceId;
  final String userId;
  final String sessionRef;
  final int actionEpoch;
  final int userVersion;
  final int? securityEpoch;
  final bool allowed;

  static _AuditScope? capture(AuthController auth) {
    final access = auth.access;
    if (!auth.isAuthenticated || !auth.admin || access == null || access.audience != 'admin') {
      return null;
    }
    return _AuditScope(
      auth: auth,
      endpoint: auth.repository.api.endpoint,
      instanceId: auth.boundInstanceId,
      userId: access.userId,
      sessionRef: access.sessionRef,
      actionEpoch: auth.actionEpoch,
      userVersion: access.authzVersion.user,
      securityEpoch: access.securityEpoch,
      allowed: access.allows('admin.audit.read'),
    );
  }

  bool same(_AuditScope? other) =>
      other != null &&
      identical(auth, other.auth) &&
      endpoint == other.endpoint &&
      instanceId == other.instanceId &&
      userId == other.userId &&
      sessionRef == other.sessionRef &&
      actionEpoch == other.actionEpoch &&
      userVersion == other.userVersion &&
      securityEpoch == other.securityEpoch &&
      allowed == other.allowed;

  bool get isCurrent => same(capture(auth));
}

class _AdminAuditEventsState extends State<AdminAuditEvents> {
  _AuditScope? _scope;
  List<AuditEventRead>? _events;
  String? _cursor;
  String? _result;
  String? _error;
  var _generation = 0;
  final _filterFields = {
    for (final key in [
      'action',
      'actor_user_id',
      'target_type',
      'target_id',
      'target_code',
      'created_from',
      'created_to',
    ])
      key: TextEditingController(),
  };
  Map<String, String> _filters = const {};

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuth);
    _capture();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuth);
    for (final controller in _filterFields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onAuth() {
    if (!mounted) return;
    final next = _AuditScope.capture(widget.auth);
    if (_scope?.same(next) ?? next == null) return;
    setState(_capture);
  }

  void _capture() {
    final scope = _AuditScope.capture(widget.auth);
    _scope = scope;
    _events = null;
    _cursor = null;
    _error = null;
    if (scope != null && scope.allowed) unawaited(_load(scope, append: false));
  }

  Future<void> _load(_AuditScope scope, {required bool append}) async {
    final generation = ++_generation;
    final cursor = append ? _cursor : null;
    final result = _result;
    try {
      final page = await scope.auth.adminAuditEvents(
        cursor: cursor,
        result: result,
        filters: _filters,
      );
      if (!mounted || !scope.isCurrent || generation != _generation) return;
      setState(() {
        _events = append ? [...?_events, ...page.data] : page.data;
        _cursor = page.nextCursor;
        _error = null;
      });
    } on ApiFailure catch (error) {
      if (!mounted || !scope.isCurrent || generation != _generation) return;
      setState(() => _error = ApiCatalog.message(AppLocalizations.of(context), error.code));
    }
  }

  Future<void> _open(AuditEventRead event) async {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    await showDialog<void>(
      context: context,
      builder: (context) => GovernanceDialogGate(
        auth: scope.auth,
        current: () => scope.isCurrent,
        child: _AuditDetail(event: event),
      ),
    );
  }

  void _applyFilters() {
    final scope = _scope;
    if (scope == null || !scope.isCurrent) return;
    final filters = <String, String>{
      for (final entry in _filterFields.entries)
        if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
    };
    DateTime? from;
    DateTime? to;
    for (final key in ['created_from', 'created_to']) {
      final value = filters[key];
      if (value == null) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value)) {
        setState(() => _error = AppLocalizations.of(context).adminAuditTimeError);
        return;
      }
      filters[key] = parsed.toUtc().toIso8601String();
      if (key == 'created_from') {
        from = parsed;
      } else {
        to = parsed;
      }
    }
    if (from != null && to != null && from.isAfter(to)) {
      setState(() => _error = AppLocalizations.of(context).adminAuditTimeError);
      return;
    }
    setState(() {
      _filters = filters;
      _cursor = null;
      _error = null;
    });
    unawaited(_load(scope, append: false));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final events = _events;
    final allowed = _scope?.allowed == true;
    return Identified(
      id: UiTestIds.adminAuditPage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!allowed)
            _GovernanceCard(child: Text(strings.authNoAdminPermission))
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in {
                  'action': strings.adminAuditAction,
                  'actor_user_id': strings.adminAuditActor,
                  'target_type': strings.adminAuditTargetType,
                  'target_id': strings.adminAuditTargetId,
                  'target_code': strings.adminAuditTargetCode,
                  'created_from': strings.adminAuditFrom,
                  'created_to': strings.adminAuditTo,
                }.entries)
                  Identified(
                    id: switch (entry.key) {
                      'action' => UiTestIds.adminAuditAction,
                      'actor_user_id' => UiTestIds.adminAuditActor,
                      'target_type' => UiTestIds.adminAuditTargetType,
                      'target_id' => UiTestIds.adminAuditTargetId,
                      'target_code' => UiTestIds.adminAuditTargetCode,
                      'created_from' => UiTestIds.adminAuditFrom,
                      _ => UiTestIds.adminAuditTo,
                    },
                    child: SizedBox(
                      width: 230,
                      child: TextField(
                        controller: _filterFields[entry.key],
                        decoration: InputDecoration(labelText: entry.value),
                        onSubmitted: (_) => _applyFilters(),
                      ),
                    ),
                  ),
                Identified(
                  id: UiTestIds.adminAuditFilter,
                  merge: true,
                  child: FilledButton(
                    onPressed: _applyFilters,
                    child: Text(strings.adminAuditFilter),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButton<String?>(
              value: _result,
              items: [
                DropdownMenuItem(value: null, child: Text(strings.adminAuditResultAll)),
                DropdownMenuItem(value: 'committed', child: Text(strings.adminAuditCommitted)),
                DropdownMenuItem(value: 'accepted', child: Text(strings.adminAuditAccepted)),
                DropdownMenuItem(value: 'denied', child: Text(strings.adminAuditDenied)),
                DropdownMenuItem(value: 'failed', child: Text(strings.adminAuditFailed)),
              ],
              onChanged: (value) {
                final scope = _scope;
                if (scope == null || !scope.isCurrent || value == _result) return;
                setState(() {
                  _result = value;
                  _events = null;
                  _cursor = null;
                });
                unawaited(_load(scope, append: false));
              },
            ),
            const SizedBox(height: 12),
            if (_error != null)
              _GovernanceCard(child: Text(_error!))
            else if (events == null)
              const _GovernanceCard(child: LinearProgressIndicator())
            else if (events.isEmpty)
              _GovernanceCard(child: Text(strings.adminAuditEmpty))
            else
              _GovernanceCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: Text(strings.mockAdminTimeColumn)),
                      DataColumn(label: Text(strings.mockAdminActionKindColumn)),
                      DataColumn(label: Text(strings.mockAdminTargetScopeColumn)),
                      DataColumn(label: Text(strings.mockAdminResultColumn)),
                    ],
                    rows: [
                      for (final event in events)
                        DataRow(
                          onSelectChanged: (_) => unawaited(_open(event)),
                          cells: [
                            DataCell(Text(_stamp(event.createdAt))),
                            DataCell(Text(event.action)),
                            DataCell(Text(event.targetCode ?? event.targetType ?? '—')),
                            DataCell(Text(_resultLabel(strings, event.result))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_cursor != null)
              TextButton(
                onPressed: () {
                  final scope = _scope;
                  if (scope != null && scope.isCurrent) unawaited(_load(scope, append: true));
                },
                child: Text(strings.adminAuditMore),
              ),
          ],
        ],
      ),
    );
  }
}

class _AuditDetail extends StatelessWidget {
  const _AuditDetail({required this.event});

  final AuditEventRead event;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final summary = event.changeSummary;
    return Identified(
      id: UiTestIds.adminAuditDialog,
      child: AlertDialog(
        title: Text(strings.adminAuditDetail),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(event.action),
              Text(_stamp(event.createdAt)),
              Text('${strings.adminAuditActor}: ${event.actorUserId ?? event.actor}'),
              if (event.targetType != null)
                Text('${strings.adminAuditTargetType}: ${event.targetType}'),
              if (event.targetId != null) Text('${strings.adminAuditTargetId}: ${event.targetId}'),
              if (event.targetCode != null)
                Text('${strings.adminAuditTargetCode}: ${event.targetCode}'),
              Text(_resultLabel(strings, event.result)),
              Text('${strings.adminGovernanceRevision} ${event.authorizationRevision}'),
              if (event.reasonCode != null) Text('${strings.adminAuditReason} ${event.reasonCode}'),
              if (event.requestId != null) Text('${strings.adminAuditRequest} ${event.requestId}'),
              if (event.operationId != null) Text(event.operationId!),
              if (summary != null)
                for (final entry in summary.entries) Text('${entry.key}: ${entry.value}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings.mockAdminClose)),
        ],
      ),
    );
  }
}

class _GovernanceCard extends StatelessWidget {
  const _GovernanceCard({required this.child, this.padding = const EdgeInsets.all(26)});

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

class _GovernanceStat extends StatelessWidget {
  const _GovernanceStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => _GovernanceCard(
    padding: const EdgeInsets.all(23),
    child: SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    ),
  );
}

String _stamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _resultLabel(AppLocalizations strings, String? result) => switch (result) {
  'committed' => strings.adminAuditCommitted,
  'accepted' => strings.adminAuditAccepted,
  'denied' => strings.adminAuditDenied,
  'failed' => strings.adminAuditFailed,
  _ => '—',
};

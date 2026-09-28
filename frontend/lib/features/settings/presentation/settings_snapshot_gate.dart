import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';

import '../data/cached_settings_repository.dart';
import '../domain/settings_snapshot.dart';
import 'settings_repository_scope.dart';

/// Keeps settings pages behind the scoped source read while retaining their
/// independent form drafts during revalidation.
final class SettingsSnapshotGate extends StatefulWidget {
  const SettingsSnapshotGate({required this.groups, required this.builder, super.key});

  final Set<SettingsGroup> groups;
  final WidgetBuilder builder;

  @override
  State<SettingsSnapshotGate> createState() => _SettingsSnapshotGateState();
}

final class _SettingsSnapshotGateState extends State<SettingsSnapshotGate>
    with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: _syncVisibility,
    onReturned: _syncVisibility,
  );
  CachedSettingsRepository? _repository;
  int? _scopeGeneration;
  Timer? _refreshTimer;
  bool _foreground = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageActivity.bind(context);
    final repository = SettingsRepositoryScope.of(context);
    if (identical(repository, _repository) && _scopeGeneration == repository.scopeGeneration) {
      _syncVisibility();
      return;
    }
    _repository = repository;
    _scopeGeneration = repository.scopeGeneration;
    _syncVisibility(force: true);
  }

  void _refreshVisible(CachedSettingsRepository repository, {bool periodic = false}) {
    if (!mounted ||
        !_foreground ||
        !_pageActivity.isCurrent ||
        !identical(repository, _repository)) {
      return;
    }
    for (final group in widget.groups) {
      if (periodic &&
          (repository.busy(group) ||
              repository.status(group) == SettingsReadStatus.loading ||
              repository.status(group) == SettingsReadStatus.refreshing)) {
        continue;
      }
      unawaited(repository.refresh(group, force: true));
    }
  }

  void _syncVisibility({bool force = false}) {
    final visible = _pageActivity.isCurrent;
    if (!force && visible == _active) return;
    _active = visible;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!visible) return;
    final repository = _repository;
    if (repository == null) return;
    scheduleMicrotask(() => _refreshVisible(repository));
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshVisible(repository, periodic: true),
    );
  }

  @override
  void didUpdateWidget(covariant SettingsSnapshotGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.groups, widget.groups)) _syncVisibility(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _pageActivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = SettingsRepositoryScope.of(context);
    final statuses = [for (final group in widget.groups) repository.status(group)];
    if (statuses.every(
      (status) =>
          status == SettingsReadStatus.ready ||
          status == SettingsReadStatus.refreshing ||
          status == SettingsReadStatus.stale,
    )) {
      // Keep the form subtree mounted during same-account reads and saves.
      // Its controllers own unsubmitted edits; a refresh must not dispose them.
      final stale = statuses.contains(SettingsReadStatus.stale);
      return Stack(
        children: [
          AbsorbPointer(
            absorbing: statuses.contains(SettingsReadStatus.refreshing),
            child: widget.builder(context),
          ),
          if (stale)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                child: Row(
                  children: [
                    Expanded(child: Text(AppLocalizations.of(context).apiUnknownError)),
                    TextButton(
                      onPressed: () {
                        for (final group in widget.groups) {
                          if (repository.status(group) == SettingsReadStatus.stale) {
                            unawaited(repository.refresh(group, force: true));
                          }
                        }
                      },
                      child: Text(AppLocalizations.of(context).referenceRetry),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (statuses.any(
      (status) => status == SettingsReadStatus.failed || status == SettingsReadStatus.blocked,
    )) {
      return Center(
        child: TextButton(
          onPressed: () {
            for (final group in widget.groups) {
              if (repository.status(group) != SettingsReadStatus.ready) {
                unawaited(repository.refresh(group, force: true));
              }
            }
          },
          child: Text(AppLocalizations.of(context).referenceRetry),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

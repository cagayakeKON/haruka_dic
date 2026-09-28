import 'dart:async';

import 'package:flutter/material.dart';

import 'package:haruka/generated/l10n/app_localizations.dart';

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

final class _SettingsSnapshotGateState extends State<SettingsSnapshotGate> {
  CachedSettingsRepository? _repository;
  int? _scopeGeneration;
  final Set<SettingsGroup> _requested = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = SettingsRepositoryScope.of(context);
    if (!identical(repository, _repository) || _scopeGeneration != repository.scopeGeneration) {
      _repository = repository;
      _scopeGeneration = repository.scopeGeneration;
      _requested.clear();
    }
    _scheduleMissingReads(repository);
  }

  void _scheduleMissingReads(CachedSettingsRepository repository) {
    final scope = repository.scopeGeneration;
    scheduleMicrotask(() async {
      try {
        await repository.waitForReadiness?.call();
      } on Object {
        // The repository publishes a scoped failure when its own read retries.
      }
      if (!mounted || !identical(repository, _repository) || scope != repository.scopeGeneration) {
        return;
      }
      for (final group in widget.groups) {
        final status = repository.status(group);
        if (_requested.contains(group) ||
            repository.snapshot(group) != null ||
            status == SettingsReadStatus.loading ||
            status == SettingsReadStatus.refreshing) {
          continue;
        }
        _requested.add(group);
        unawaited(repository.refresh(group));
      }
    });
  }

  @override
  void didUpdateWidget(covariant SettingsSnapshotGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups) {
      final repository = _repository;
      if (repository != null) _scheduleMissingReads(repository);
    }
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
          widget.builder(context),
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
                            _requested.add(group);
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
                _requested.add(group);
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

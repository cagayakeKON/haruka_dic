import 'package:flutter/widgets.dart';

import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';

/// Carries a selection to the query draft without placing private text in a URL.
/// The value lives only in the current navigation stack and is rejected after
/// the confirmed account or its authorization projection changes.
final class QueryPrefill {
  QueryPrefill._(
    this.text,
    this._coordinator,
    this._binding,
    this._scopeGeneration,
    this._securityEpoch,
    this._authzVersion,
    this._policyVersion,
  );

  final String text;
  final CacheCoordinator _coordinator;
  final String _binding;
  final int _scopeGeneration;
  final int _securityEpoch;
  final int _authzVersion;
  final int _policyVersion;

  static QueryPrefill? capture(CacheCoordinator coordinator, String text) {
    final scope = coordinator.scope;
    if (!coordinator.accessReady || scope == null || text.trim().isEmpty) return null;
    return QueryPrefill._(
      text,
      coordinator,
      scope.binding,
      coordinator.scopeGeneration,
      scope.securityEpoch,
      scope.authzVersion,
      scope.policyVersion,
    );
  }

  String? read(CacheCoordinator coordinator) {
    final scope = coordinator.scope;
    if (!identical(coordinator, _coordinator) ||
        !coordinator.accessReady ||
        scope == null ||
        scope.binding != _binding ||
        coordinator.scopeGeneration != _scopeGeneration ||
        scope.securityEpoch != _securityEpoch ||
        scope.authzVersion != _authzVersion ||
        scope.policyVersion != _policyVersion) {
      return null;
    }
    return text;
  }
}

/// A scope change replaces the query editor, clearing any private draft that
/// was entered under the previous account even while this route remains open.
class ScopedQueryPage extends StatelessWidget {
  const ScopedQueryPage({this.prefill, super.key});

  final QueryPrefill? prefill;

  @override
  Widget build(BuildContext context) {
    final coordinator = PreviewSettingsCacheScope.of(context).coordinator;
    final scope = coordinator.scope;
    return QueryPage(
      key: ValueKey((
        prefill,
        coordinator.scopeGeneration,
        coordinator.accessReady,
        scope?.binding,
        scope?.securityEpoch,
        scope?.authzVersion,
        scope?.policyVersion,
      )),
      initialText: prefill?.read(coordinator),
    );
  }
}

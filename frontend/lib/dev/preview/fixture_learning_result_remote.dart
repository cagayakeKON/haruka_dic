import 'package:dio/dio.dart';

import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';

import 'fixture_store.dart';

/// Development source for already completed, saved card projections.
final class FixtureLearningResultRemote implements CacheRemote<LearningCard> {
  const FixtureLearningResultRemote(this.store, this.cache);

  final PreviewFixtureStore store;
  final CacheCoordinator cache;

  String _previewBinding() {
    final scope = cache.scope;
    if (!cache.accessReady ||
        scope?.endpointKey != 'http://127.0.0.1/mock-preview' ||
        scope?.instanceId != 'preview-fixtures' ||
        scope?.userId != 'preview-user' ||
        scope?.audience != 'client') {
      throw const CacheBlocked('identity_unconfirmed');
    }
    return scope!.binding;
  }

  LearningCard? _card(String id) =>
      store.savedQueryCard(id, scopeBinding: _previewBinding()) ??
      store.cards.where((card) => card.id == id).firstOrNull;

  CacheVersion _version(LearningCard card) => CacheVersion(
    resource: '${card.id}:${card.version}',
    representation: 'learning-card-v1',
    artifact: '${card.id}:${card.version}',
  );

  @override
  Future<CachePayload<LearningCard>> fetch(CacheResource resource, CancelToken cancel) async {
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final card = _card(resource.id);
    // The preview fixture is process-local. A miss after restart says nothing
    // about whether the server still has the saved result.
    if (card == null) throw const CacheBlocked('preview_source_unconfirmed');
    return CachePayload(value: card, version: _version(card));
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final card = _card(resource.id);
    if (card == null) throw const CacheBlocked('preview_source_unconfirmed');
    final version = _version(card);
    return CacheValidation(
      state: known.resource == version.resource ? ValidationState.same : ValidationState.changed,
      version: version,
    );
  }
}

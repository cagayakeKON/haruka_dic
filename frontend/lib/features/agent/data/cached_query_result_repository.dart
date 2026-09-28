import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/cache/cache_coordinator.dart';
import '../../../core/cache/cache_models.dart';
import '../domain/learning_card.dart';
import '../domain/query_history_entry.dart';
import '../domain/query_request.dart';
import 'query_result_repository.dart';

CacheResource learningResultResource(String id) => CacheResource(
  kind: 'learning_text',
  id: id,
  projection: 'learning-card-v1',
  action: 'agent.read',
  sourceBinding: 'learning-result:$id',
);

/// A completed query is resolved from the saved source before local publication.
final class CachedQueryResultRepository extends ChangeNotifier implements QueryResultRepository {
  CachedQueryResultRepository({
    required CacheCoordinator cache,
    required this.resolveSource,
    required this.generateSource,
    required this.remote,
    this.waitForReadiness,
  }) : _cache = cache {
    cache.register(
      CachePolicy<LearningCard>(
        kind: 'learning_text',
        disposition: CacheDisposition.validatedText,
        decode: LearningCard.fromJson,
        encode: (card) => card.toJson(),
        dependencies: (resource) => {'learning-result:${resource.id}'},
      ),
    );
    _cacheChanges = cache.changes.listen((_) => _onCacheChanged());
  }

  final CacheCoordinator _cache;
  final Future<LearningCard?> Function(QueryRequest) resolveSource;
  final Future<LearningCard> Function(QueryRequest) generateSource;
  final CacheRemote<LearningCard> remote;
  final Future<void> Function()? waitForReadiness;
  final _history = <QueryHistoryEntry>[];
  late final StreamSubscription<void> _cacheChanges;
  final Set<String> _hiddenIds = {};
  final Map<String, CacheView<LearningCard>> _acceptedViews = {};
  final Map<(String, int), CachePin> _displayPins = {};
  final Map<(String, int), int> _mountedCards = {};
  final Set<(String, int)> _pinningCards = {};
  final Map<(String, int), Timer> _handoffTimers = {};
  bool _visible = false;
  bool _checkingVisible = false;
  bool _recheckVisible = false;
  int _visibleGeneration = 0;
  bool _disposed = false;
  int _seenInvalidationGeneration = 0;
  int _seenStorageRevision = 0;
  (int, int, int, int, int)? _historyIdentity;
  String? _historyBinding;

  (int, int, int, int, int)? get _currentIdentity {
    final scope = _cache.scope;
    if (!_cache.displayAuthorized || scope == null) return null;
    return (
      _cache.accountGeneration,
      _cache.scopeGeneration,
      scope.securityEpoch,
      scope.authzVersion,
      scope.policyVersion,
    );
  }

  @override
  List<QueryHistoryEntry> get history =>
      !_disposed &&
          _currentIdentity != null &&
          _historyIdentity == _currentIdentity &&
          _historyBinding == _cache.scope?.binding
      ? List.unmodifiable(_history.where((entry) => !_hiddenIds.contains(entry.card.id)))
      : const [];

  void setVisible(bool visible) {
    if (_disposed) return;
    if (_visible == visible) return;
    _visible = visible;
    _visibleGeneration++;
    if (!visible) _releaseDisplayPins();
    notifyListeners();
    if (visible) unawaited(revalidateVisible());
  }

  void mountCard(LearningCard card) {
    if (_disposed) return;
    final key = (card.id, card.version);
    _mountedCards[key] = (_mountedCards[key] ?? 0) + 1;
    _handoffTimers.remove(key)?.cancel();
    if (_visible && !_displayPins.containsKey(key)) unawaited(_pinDisplayed(card));
  }

  void unmountCard(LearningCard card) {
    final key = (card.id, card.version);
    final count = _mountedCards[key] ?? 0;
    if (count <= 1) {
      _mountedCards.remove(key);
      _handoffTimers.remove(key)?.cancel();
      _displayPins.remove(key)?.release();
    } else {
      _mountedCards[key] = count - 1;
    }
  }

  Future<void> _pinDisplayed(LearningCard card) async {
    final key = (card.id, card.version);
    final view = _acceptedViews[card.id];
    if (!_visible ||
        view == null ||
        !view.localReady ||
        view.data?.version != card.version ||
        _displayPins.containsKey(key) ||
        !_pinningCards.add(key)) {
      return;
    }
    final identity = _currentIdentity;
    final storageRevision = _cache.storageRevision;
    if (identity == null) {
      _pinningCards.remove(key);
      return;
    }
    try {
      final pin = await _cache.pinVersion(view);
      if (_disposed ||
          !_visible ||
          _currentIdentity != identity ||
          (_mountedCards[key] ?? 0) == 0 ||
          !identical(_acceptedViews[card.id], view)) {
        pin.release();
        return;
      }
      _displayPins[key] = pin;
    } on Object {
      if (_currentIdentity == identity &&
          _cache.storageRevision == storageRevision &&
          _cache.accessReady &&
          (_mountedCards[key] ?? 0) > 0) {
        _hiddenIds.add(card.id);
        notifyListeners();
      }
    } finally {
      _pinningCards.remove(key);
    }
  }

  void _releaseDisplayPins() {
    for (final timer in _handoffTimers.values) {
      timer.cancel();
    }
    _handoffTimers.clear();
    for (final pin in _displayPins.values) {
      pin.release();
    }
    _displayPins.clear();
  }

  bool get isVisible => _visible;

  void _onCacheChanged() {
    if (_disposed) return;
    final identity = _currentIdentity;
    final binding = _cache.scope?.binding;
    if (binding != null && _historyBinding != null && binding != _historyBinding) {
      _history.clear();
      _hiddenIds.clear();
      _acceptedViews.clear();
      _releaseDisplayPins();
      _historyIdentity = identity;
      _historyBinding = binding;
      notifyListeners();
      return;
    }
    if (identity == null) {
      _acceptedViews.clear();
      _releaseDisplayPins();
      notifyListeners();
      return;
    }
    if (_historyIdentity != null && identity != _historyIdentity) {
      _historyIdentity = identity;
      _hiddenIds.addAll(_history.map((entry) => entry.card.id));
      _acceptedViews.clear();
      _releaseDisplayPins();
      notifyListeners();
      if (_visible) unawaited(revalidateVisible());
      return;
    }
    if (_seenStorageRevision != _cache.storageRevision) {
      _seenStorageRevision = _cache.storageRevision;
      _acceptedViews.clear();
      _releaseDisplayPins();
      notifyListeners();
      return;
    }
    if (_seenInvalidationGeneration == _cache.invalidationGeneration) return;
    _seenInvalidationGeneration = _cache.invalidationGeneration;
    final tags = _cache.lastInvalidatedTags;
    for (final entry in _history) {
      if (tags == null ||
          tags.contains('learning-result:*') ||
          tags.contains('learning-result:${entry.card.id}')) {
        _hiddenIds.add(entry.card.id);
        for (final key in _displayPins.keys.where((key) => key.$1 == entry.card.id).toList()) {
          _displayPins.remove(key)?.release();
        }
      }
    }
    notifyListeners();
    if (_visible) unawaited(revalidateVisible());
  }

  /// Only saved cards shown by this page are checked. This never resolves or generates.
  Future<void> revalidateVisible() async {
    if (_disposed || !_visible || _currentIdentity == null) return;
    if (_checkingVisible) {
      _recheckVisible = true;
      return;
    }
    _checkingVisible = true;
    final identity = _currentIdentity;
    final binding = _cache.scope?.binding;
    final visibleGeneration = _visibleGeneration;
    bool current() =>
        !_disposed &&
        _visible &&
        _visibleGeneration == visibleGeneration &&
        _currentIdentity == identity &&
        _cache.scope?.binding == binding;
    try {
      for (final entry in _history.reversed.toList()) {
        if (!current()) return;
        try {
          final card = await _readSaved(
            entry.card.id,
            explicitUserAction: false,
            stillRelevant: current,
          );
          if (!current()) return;
          final matching = _history.where((item) => item.card.id == entry.card.id).toList();
          if (matching.isNotEmpty) {
            for (final prior in matching) {
              final index = _history.indexOf(prior);
              _history[index] = QueryHistoryEntry(
                prompt: prior.prompt,
                card: card,
                targetLanguage: prior.targetLanguage,
              );
            }
            _hiddenIds.remove(entry.card.id);
            notifyListeners();
          }
        } on CacheBlocked catch (error) {
          if (!current()) return;
          if (error.reason == 'resource_unavailable' ||
              error.reason == 'learning_result_unavailable') {
            _history.removeWhere((item) => item.card.id == entry.card.id);
            _hiddenIds.remove(entry.card.id);
            notifyListeners();
          }
        } on Object {
          // Keep a previously validated card only while access remains current.
        }
      }
    } finally {
      _checkingVisible = false;
      if (_recheckVisible) {
        _recheckVisible = false;
        if (!_disposed && _visible) unawaited(revalidateVisible());
      }
    }
  }

  @override
  Future<LearningCard> submit(QueryRequest request) async {
    await waitForReadiness?.call();
    if (_disposed) throw const CacheBlocked('repository_disposed');
    if (!_cache.accessReady) throw const CacheBlocked('identity_unconfirmed');
    if (_cache.isOffline) throw const CacheBlocked('query_requires_network');
    final generation = _cache.accountGeneration;
    final binding = _cache.scope?.binding;
    final identity = _currentIdentity;
    void requireCurrent() {
      if (_disposed ||
          !_cache.accessReady ||
          _cache.accountGeneration != generation ||
          _cache.scope?.binding != binding) {
        throw const CacheBlocked('scope_changed');
      }
    }

    final resolved = await resolveSource(request);
    requireCurrent();
    final saved = resolved ?? await generateSource(request);
    requireCurrent();
    final card = await readSaved(saved.id);
    requireCurrent();
    if (_historyIdentity != identity) {
      _history.clear();
      _hiddenIds.clear();
      _historyIdentity = identity;
      _historyBinding = binding;
    }
    _history.add(
      QueryHistoryEntry(
        prompt: request.text.trim(),
        card: card,
        targetLanguage: request.targetLanguage,
      ),
    );
    _hiddenIds.remove(card.id);
    notifyListeners();
    return card;
  }

  @override
  Future<LearningCard> readSaved(String id) => _readSaved(id, explicitUserAction: true);

  Future<LearningCard> _readSaved(
    String id, {
    required bool explicitUserAction,
    bool Function()? stillRelevant,
  }) async {
    await waitForReadiness?.call();
    if (_disposed) throw const CacheBlocked('repository_disposed');
    final identity = _currentIdentity;
    if (identity == null) throw const CacheBlocked('identity_unconfirmed');
    final resource = learningResultResource(id);
    final pin = await _cache.pin(resource);
    try {
      final view = await _cache.read<LearningCard>(
        resource: resource,
        remote: remote,
        explicitUserAction: explicitUserAction && !_cache.isOffline,
      );
      if (stillRelevant != null && !stillRelevant()) {
        throw const CacheBlocked('visible_cycle_changed');
      }
      if (_disposed || _currentIdentity != identity || view.data == null || !view.serverSaved) {
        throw const CacheBlocked('learning_result_unavailable');
      }
      if (view.resource?.id != view.data!.id) {
        throw const CacheBlocked('invalid_read_projection');
      }
      final card = view.data!;
      final cardKey = (card.id, card.version);
      if (view.localReady &&
          _visible &&
          (explicitUserAction || (_mountedCards[cardKey] ?? 0) > 0)) {
        final displayPin = await _cache.pinVersion(view);
        if (_disposed ||
            _currentIdentity != identity ||
            !_visible ||
            (stillRelevant != null && !stillRelevant())) {
          displayPin.release();
          throw const CacheBlocked('scope_changed');
        }
        _displayPins.remove(cardKey)?.release();
        _displayPins[cardKey] = displayPin;
        if ((_mountedCards[cardKey] ?? 0) == 0) {
          _handoffTimers.remove(cardKey)?.cancel();
          _handoffTimers[cardKey] = Timer(const Duration(seconds: 1), () {
            if ((_mountedCards[cardKey] ?? 0) == 0) _displayPins.remove(cardKey)?.release();
            _handoffTimers.remove(cardKey);
          });
        }
      }
      if (stillRelevant != null && !stillRelevant()) {
        throw const CacheBlocked('visible_cycle_changed');
      }
      _acceptedViews[card.id] = view;
      if (!view.localReady) _displayPins.remove(cardKey)?.release();
      if (explicitUserAction &&
          _historyIdentity == identity &&
          _historyBinding == _cache.scope?.binding) {
        var changed = false;
        for (var index = 0; index < _history.length; index++) {
          final prior = _history[index];
          if (prior.card.id != id) continue;
          _history[index] = QueryHistoryEntry(
            prompt: prior.prompt,
            card: card,
            targetLanguage: prior.targetLanguage,
          );
          changed = true;
        }
        final unhidRequested = _hiddenIds.remove(id);
        final unhidResolved = _hiddenIds.remove(card.id);
        changed = changed || unhidRequested || unhidResolved;
        if (changed) notifyListeners();
      }
      return view.data!;
    } finally {
      // The returned immutable card owns its data. Keep the disk lease only
      // while reading, rather than pinning application history indefinitely.
      pin.release();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _visible = false;
    _releaseDisplayPins();
    unawaited(_cacheChanges.cancel());
    super.dispose();
  }
}

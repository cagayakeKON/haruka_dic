import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_database.dart';
import 'package:haruka/core/cache/cache_models.dart';

/// Isolated preview storage. No mock identity or result is passed to the real
/// authenticated application's cache coordinator.
final class PreviewSettingsCacheAdapter extends ChangeNotifier {
  PreviewSettingsCacheAdapter({CacheCoordinator? coordinator})
    : _coordinator = coordinator ?? CacheCoordinator() {
    _changes = _coordinator.changes.listen((_) {
      if (_disposed) return;
      if (!_coordinator.accessReady) {
        _usage = null;
        _usageScopeGeneration = null;
        _notify();
      } else if (!_busy) {
        unawaited(refresh());
      }
    });
  }

  final CacheCoordinator _coordinator;
  CacheCoordinator get coordinator => _coordinator;
  late final StreamSubscription<void> _changes;
  Future<void>? _initialization;
  CacheUsage? _usage;
  int? _usageScopeGeneration;
  Object? _lastError;
  CacheClearResult? _lastClear;
  bool _busy = false;
  bool _disposed = false;

  CacheUsage? get usage => ready ? _usage : null;
  Object? get lastError => _lastError;
  String? get blockingReason => _coordinator.degradedReason;
  CacheClearResult? get lastClear => _lastClear;
  bool get busy => _busy;
  bool get ready =>
      _usage != null &&
      !_disposed &&
      _coordinator.accessReady &&
      _usageScopeGeneration == _coordinator.scopeGeneration;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> retry() async {
    if (_disposed || _busy) return;
    _initialization = null;
    await initialize();
  }

  Future<void> _initialize() async {
    try {
      // The explicit preview endpoint and identity isolate fixture data from
      // authenticated cache partitions while allowing local cache inspection.
      await _coordinator.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('http://127.0.0.1/mock-preview'),
          instanceId: 'preview-fixtures',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      );
      _usage = await _coordinator.usage();
      _usageScopeGeneration = _coordinator.scopeGeneration;
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
    }
    _notify();
  }

  Future<void> refresh() async {
    await initialize();
    if (_disposed || _coordinator.scope == null) return;
    try {
      _usage = await _coordinator.usage();
      _usageScopeGeneration = _coordinator.scopeGeneration;
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
    }
    _notify();
  }

  Future<bool> saveLimits({required int textMb, required int audioMb}) async {
    await initialize();
    if (_disposed || _busy || !ready) return false;
    _busy = true;
    _notify();
    try {
      _usage = await _coordinator.setQuotas(
        textBytes: textMb * 1000000,
        audioBytes: audioMb * 1000000,
      );
      _usageScopeGeneration = _coordinator.scopeGeneration;
      _lastError = null;
      return true;
    } on Object catch (error) {
      _lastError = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<CacheClearResult?> clear() async {
    await initialize();
    if (_disposed || _busy || !ready) return null;
    _busy = true;
    _notify();
    try {
      final result = await _coordinator.clearScope();
      _lastClear = result;
      _usage = await _coordinator.usage();
      _usageScopeGeneration = _coordinator.scopeGeneration;
      _lastError = null;
      return result;
    } on Object catch (error) {
      _lastError = error;
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    unawaited(_shutdown());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _initialization;
    await _coordinator.closeScope();
  }
}

class PreviewSettingsCacheScope extends InheritedNotifier<PreviewSettingsCacheAdapter> {
  const PreviewSettingsCacheScope({
    required PreviewSettingsCacheAdapter adapter,
    required super.child,
    super.key,
  }) : super(notifier: adapter);

  static PreviewSettingsCacheAdapter of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PreviewSettingsCacheScope>();
    assert(scope != null, 'PreviewSettingsCacheScope is missing');
    return scope!.notifier!;
  }
}

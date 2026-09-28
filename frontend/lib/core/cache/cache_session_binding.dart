import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../app/lifecycle_visibility.dart';
import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'cache_coordinator.dart';
import 'cache_models.dart';

final cacheCoordinatorProvider = Provider<CacheCoordinator>(
  (ref) => throw StateError('Cache coordinator missing'),
);

/// Keeps the cache attached only to a confirmed client access projection.
/// Every identity change blocks reads synchronously, before disk cleanup runs.
final class CacheSessionBinding with WidgetsBindingObserver {
  CacheSessionBinding(
    this.auth,
    this.config,
    this.cache, {
    Uri Function()? endpoint,
    String Function()? instanceId,
  }) : _endpoint = endpoint ?? (() => config.apiBaseUrl),
       _instanceId = instanceId ?? (() => config.instanceId) {
    auth.addListener(_onIdentityChanged);
    WidgetsBinding.instance.addObserver(this);
    _onIdentityChanged();
    _startForegroundChecks();
  }

  final AuthController auth;
  final AppConfig config;
  final CacheCoordinator cache;
  final Uri Function() _endpoint;
  final String Function() _instanceId;
  Future<void> _tail = Future<void>.value();
  String? _target;
  int _transition = 0;
  bool _disposed = false;
  bool _foreground = true;
  Timer? _foregroundTimer;
  bool _checkingAccess = false;
  Completer<void>? _checkDone;
  final ValueNotifier<bool> foregroundRevalidating = ValueNotifier(false);

  Future<void> get settled => _tail;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = foregroundAfterLifecycle(state, wasForeground: wasForeground);
    if (state == AppLifecycleState.resumed && !_disposed) {
      // A platform may stop its monotonic clock during sleep, or omit the
      // background notification altogether. Keep the online page mounted but
      // require a new online resource response before any offline lease works.
      cache.setOfflineLeaseForeground(true);
    } else if (!_foreground && !_disposed) {
      cache.setOfflineLeaseForeground(false);
    }
    if (!wasForeground && _foreground && !_disposed) {
      auth.resumeAccessDeadline();
      // An expired validation has already closed private UI through the auth
      // listener. A still-valid projection stays mounted while identity is
      // checked in the background.
      if (auth.phase == AuthPhase.unavailable) {
        foregroundRevalidating.value = true;
      }
      _startForegroundChecks();
      unawaited(_checkForeground(forceFresh: true));
    } else if (!_foreground && state != AppLifecycleState.inactive) {
      auth.pauseAccessDeadline();
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
    }
  }

  void _startForegroundChecks() {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_checkForeground());
    });
  }

  Future<void> _checkForeground({bool forceFresh = false}) async {
    if (_disposed) return;
    if (_checkingAccess) {
      if (!forceFresh) return;
      await _checkDone?.future;
      if (!_disposed) {
        await _checkForeground(forceFresh: true);
      }
      return;
    }
    _checkingAccess = true;
    final done = Completer<void>();
    _checkDone = done;
    try {
      final verified = await auth.verifyCurrentAccess();
      if (verified && !_disposed) {
        await _tail;
        if (!_disposed) await cache.synchronizeStorage();
      }
      if (!_disposed &&
          foregroundRevalidating.value &&
          (cache.terminalReason != null ||
              !auth.isAuthenticated ||
              (verified && (auth.admin || cache.accessReady)))) {
        foregroundRevalidating.value = false;
      }
    } on Object {
      // Auth/cache owners publish their blocked state; a timer cannot fail UI.
      if (!_disposed && cache.terminalReason != null && foregroundRevalidating.value) {
        foregroundRevalidating.value = false;
      }
    } finally {
      _checkingAccess = false;
      _checkDone = null;
      done.complete();
    }
  }

  void _onIdentityChanged() {
    if (_disposed) return;
    final access = auth.isAuthenticated && !auth.admin ? auth.access : null;
    final target = access == null
        ? null
        : jsonEncode([
            _endpoint().toString(),
            access.instanceId,
            access.userId,
            access.audience,
            access.sessionRef,
            access.securityEpoch,
            access.authzVersion.user,
            access.authzVersion.policy,
          ]);
    final signedOut = auth.phase == AuthPhase.anonymous || auth.phase == AuthPhase.pendingEmail;
    if (target == _target && !signedOut) return;
    _target = target;
    final transition = ++_transition;
    cache.blockForAuthorizationFailure();
    // Authentication refresh is uncertain until /me/access succeeds. Keep the
    // old partition closed to reads, but preserve its bytes for a valid offline
    // grant or a same-session reattachment after connectivity returns.
    if (auth.phase == AuthPhase.starting || auth.phase == AuthPhase.unavailable) return;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (_disposed || transition != _transition) return;
      final confirmed =
          access != null && access.instanceId == _instanceId() && access.audience == 'client'
          ? CacheScope.confirmed(
              endpoint: _endpoint(),
              instanceId: access.instanceId,
              userId: access.userId,
              audience: access.audience,
              sessionRef: access.sessionRef,
              // Missing is distinct from the valid initial security epoch 0.
              securityEpoch: access.securityEpoch ?? -1,
              authzVersion: access.authzVersion.user,
              policyVersion: access.authzVersion.policy,
            )
          : null;
      final current = cache.scope;
      if (confirmed != null &&
          current?.binding == confirmed.binding &&
          current?.securityEpoch == confirmed.securityEpoch &&
          current?.authzVersion == confirmed.authzVersion &&
          current?.policyVersion == confirmed.policyVersion) {
        cache.completeOnlineRevalidation(confirmed);
        return;
      }
      if (confirmed != null && current?.binding == confirmed.binding) {
        await cache.updateConfirmedAuthorization(confirmed);
        return;
      }
      final samePartitionRebind = confirmed != null && current?.partition == confirmed.partition;
      if (current != null && !samePartitionRebind) {
        try {
          await cache.clearScope(afterIdentityChange: true);
        } on Object {
          // The old partition remains isolated; a later attachment retries
          // pending byte deletion instead of exposing it to the new identity.
        }
      }
      await cache.closeScope();
      if (_disposed || transition != _transition || confirmed == null) return;
      await cache.attach(confirmed, revokePreviousGrants: samePartitionRebind);
      if (_disposed || transition != _transition) await cache.closeScope();
    });
    // Storage failure keeps the cache blocked and must never fail login.
    unawaited(_tail.catchError((Object _) {}));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    auth.removeListener(_onIdentityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _foregroundTimer?.cancel();
    cache.blockForAuthorizationFailure();
    await _checkDone?.future;
    await _tail.catchError((Object _) {});
    await cache.closeScope();
    foregroundRevalidating.dispose();
  }
}

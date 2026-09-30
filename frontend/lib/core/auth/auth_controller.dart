import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../api/responses.dart';
import '../api/auth_models.dart';
import '../config/app_config.dart';
import 'auth_repository.dart';
import 'auth_sync.dart';
import 'credential_vault.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw StateError('Auth repository missing'),
);
final appConfigProvider = Provider<AppConfig>((ref) => throw StateError('App config missing'));
final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(ref.read(authRepositoryProvider), ref.read(appConfigProvider));
});

enum AuthPhase { starting, anonymous, pendingEmail, authenticated, unavailable }

/// Shared identity use cases. Only credentials and wire transport differ by platform.
/// Every async identity transition checks its account epoch before publishing state.
final class AuthController extends ChangeNotifier {
  AuthController(this.repository, this.config, {CredentialVault? vault, AuthSync? sync})
    : _boundInstanceId = config.instanceId,
      _vault = vault ?? CredentialVault(config.apiBaseUrl, config.instanceId, 'client') {
    repository.api.onSessionBindingLost = () {
      if (_disposed) return;
      ++_epoch;
      _clearMemory();
      _setPhase(AuthPhase.starting);
      unawaited(start(admin: _preferredAdmin));
    };
    _sync =
        sync ??
        AuthSync(config.instanceId, (event) {
          if (_disposed) return;
          if (event == AuthSyncEvent.started) {
            ++_epoch;
            _clearMemory();
            _setPhase(AuthPhase.starting);
          } else {
            unawaited(start(admin: _preferredAdmin));
          }
        });
  }

  final AuthRepository repository;
  final AppConfig config;
  String _boundInstanceId;
  CredentialVault _vault;

  String get boundInstanceId => _boundInstanceId;

  /// Swaps the credential partition after the old session is already cleared.
  void adoptInstance(Uri endpoint, String instanceId) {
    if (isAuthenticated || _access != null || _accessToken != null) {
      throw StateError('Adopt requires a signed-out session');
    }
    if (!RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(instanceId)) {
      throw const FormatException('Invalid instance');
    }
    if (repository.api.endpoint != endpoint || repository.api.instanceId != instanceId) {
      throw StateError('Transport must be retargeted before adopting credentials');
    }
    ++_epoch;
    _clearMemory();
    _policy = null;
    _boundInstanceId = instanceId;
    _vault = CredentialVault(endpoint, instanceId, 'client');
    if (_phase != AuthPhase.anonymous) {
      _setPhase(AuthPhase.anonymous);
    } else {
      notifyListeners();
    }
  }

  late final AuthSync _sync;
  bool _preferredAdmin = false;
  bool _disposed = false;
  bool _switchingInstance = false;
  Future<void> _identityTail = Future<void>.value();
  int _epoch = 0;
  String? _accessToken;
  String? _csrfClient;
  String? _csrfAdmin;
  String? _sessionRef;
  String? _continuationToken;
  DateTime? _continuationExpiresAt;
  Future<void>? _refreshFlight;
  int? _refreshFlightEpoch;
  String? _refreshFlightSession;
  AuthPolicy? _policy;
  AccessRead? _access;
  AuthPhase _phase = AuthPhase.starting;
  bool _admin = false;
  int? _lastLocalSignOutEpoch;
  String? _lastLocalSignOutSession;

  AuthPhase get phase => _phase;
  AuthPolicy? get policy => _policy;
  AccessRead? get access => _access;
  Stopwatch? _accessValidationAge;
  Timer? _accessDeadline;
  bool get admin => _admin;
  bool get isAuthenticated => _phase == AuthPhase.authenticated && _access != null;
  int get actionEpoch => _epoch;

  /// Fence public and queued identity actions before the first await of a switch.
  /// The current session is retained long enough for its explicit remote revoke.
  void invalidateForInstanceSwitch() {
    if (_disposed) return;
    _switchingInstance = true;
    ++_epoch;
    _continuationToken = null;
    _continuationExpiresAt = null;
  }

  void finishInstanceSwitch() {
    if (_disposed) return;
    _switchingInstance = false;
  }

  void _assertCurrent(int epoch, Uri endpoint) {
    if (_disposed || _switchingInstance || epoch != _epoch || repository.api.endpoint != endpoint) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
  }

  void _assertNotSwitching() {
    if (_disposed || _switchingInstance) throw const ApiFailure(code: 'SESSION_INVALID');
  }

  bool wasLocallySignedOutBy(int startedEpoch, String sessionRef) =>
      !_disposed &&
      _lastLocalSignOutEpoch == startedEpoch &&
      _lastLocalSignOutSession == sessionRef &&
      _epoch == startedEpoch + 1 &&
      !isAuthenticated;

  Future<ActivationStatus> activationStatus() async {
    if (_switchingInstance) throw const ApiFailure(code: 'SESSION_INVALID');
    final token = _continuationToken;
    final expiry = _continuationExpiresAt;
    if (token == null || expiry == null || !DateTime.now().toUtc().isBefore(expiry)) {
      _continuationToken = null;
      _continuationExpiresAt = null;
      throw const ApiFailure(code: 'RESOURCE_EXPIRED');
    }
    final current = _epoch;
    final status = await repository.activationStatus(token);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    if (status.active) {
      _continuationToken = null;
      _continuationExpiresAt = null;
      _setPhase(AuthPhase.anonymous);
    }
    return status;
  }

  Future<void> reloadPolicy() async {
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    if (_disposed || current != _epoch || repository.api.endpoint != endpoint) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    final policy = await repository.policy();
    if (current != _epoch || _disposed) return;
    _policy = policy;
    notifyListeners();
  }

  Future<void> register(String email, String password, {String? operationId}) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    final receipt = await repository.register(email, password, operationId: operationId);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    if (receipt.nextStep != 'verify_email') throw const ApiFailure(code: 'INVALID_RESPONSE');
  }

  Future<void> resend(String email) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    final receipt = await repository.resend(email);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    if (receipt.nextStep != 'check_email') throw const ApiFailure(code: 'INVALID_RESPONSE');
  }

  Future<void> requestRecovery(String email) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    final receipt = await repository.requestRecovery(email);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    if (receipt.nextStep != 'check_email') throw const ApiFailure(code: 'INVALID_RESPONSE');
  }

  Future<void> requestManualRecovery(String email) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    final receipt = await repository.requestManualRecovery(email);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    if (receipt.nextStep != 'await_review') throw const ApiFailure(code: 'INVALID_RESPONSE');
  }

  Future<void> verifyEmail(String token) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    await repository.verifyEmail(token);
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    _sync.publishChanged();
  }

  Future<bool> completeRecovery(String token, String password) async {
    _assertNotSwitching();
    final current = _epoch;
    final endpoint = repository.api.endpoint;
    final session = _sessionRef;
    final admin = _admin;
    await repository.verifyInstance();
    _assertCurrent(current, endpoint);
    try {
      await repository.completeRecovery(token, password);
    } on ApiFailure catch (error) {
      if (!const {
            'INPUT_INVALID',
            'BAD_REQUEST',
            'RESOURCE_EXPIRED',
            'RATE_LIMITED',
            'STATE_CONFLICT',
          }.contains(error.code) &&
          current == _epoch &&
          session != null) {
        await _clearIfCurrent(current, session);
      }
      rethrow;
    } on Object {
      if (current == _epoch && session != null) await _clearIfCurrent(current, session);
      rethrow;
    }
    if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
    var clearedByRecovery = false;
    if (session != null && isAuthenticated) {
      try {
        final active = await repository.access(admin: admin, headers: _readHeaders());
        if (current == _epoch && active.sessionRef == session && active.userId == _access?.userId) {
          _acceptAccess(active, admin: admin);
        } else if (current == _epoch) {
          clearedByRecovery = await _clearIfCurrent(current, session);
        }
      } on Object {
        clearedByRecovery = await _clearIfCurrent(current, session);
      }
    }
    if (_disposed || (current != _epoch && !(clearedByRecovery && _epoch == current + 1))) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    _sync.publishChanged();
    return true;
  }

  void _setPhase(AuthPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  Future<T> _identityWrite<T>(Future<T> Function() action) async {
    final previous = _identityTail;
    final done = Completer<void>();
    _identityTail = done.future;
    await previous;
    try {
      return await _sync.withIdentityLock(() async {
        _sync.publishStarted();
        try {
          return await action();
        } finally {
          _sync.publishChanged();
        }
      });
    } finally {
      done.complete();
    }
  }

  Future<void> start({bool admin = false}) async {
    if (_disposed) return;
    final current = ++_epoch;
    _preferredAdmin = admin;
    _clearMemory();
    _policy = null;
    _setPhase(AuthPhase.starting);
    try {
      await repository.verifyInstance();
      if (current != _epoch || _disposed) return;
      _policy = await repository.policy();
      if (current != _epoch || _disposed) return;
      if (config.platform == AppPlatform.web) {
        await _restoreWeb(current, admin: admin);
      } else {
        await _restoreNative(current);
      }
    } on ApiFailure catch (error) {
      if (current != _epoch || _disposed) return;
      if (error.code == 'AUTH_REQUIRED' ||
          error.code == 'SESSION_INVALID' ||
          error.code == 'SESSION_REVOKED' ||
          error.code == 'ACCESS_EXPIRED') {
        _setPhase(AuthPhase.anonymous);
      } else {
        _setPhase(AuthPhase.unavailable);
      }
    } on Object {
      if (current == _epoch && !_disposed) _setPhase(AuthPhase.unavailable);
    }
  }

  Future<void> _restoreWeb(int current, {required bool admin}) async {
    if (_sync.locallySignedOut(admin ? 'admin' : 'client')) {
      if (current == _epoch && !_disposed) _setPhase(AuthPhase.anonymous);
      return;
    }
    try {
      final access = await repository.access(admin: admin, headers: const {});
      if (current != _epoch || _disposed) return;
      final csrf = await repository.csrf(admin: admin);
      if (current != _epoch || _disposed || _sync.locallySignedOut(admin ? 'admin' : 'client')) {
        return;
      }
      if (csrf.sessionRef != access.sessionRef) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      if (admin) {
        _csrfAdmin = csrf.token;
      } else {
        _csrfClient = csrf.token;
      }
      _acceptAccess(access, admin: admin);
    } on ApiFailure catch (error) {
      if (!_isUnauthenticated(error)) rethrow;
      if (current == _epoch && !_disposed) _setPhase(AuthPhase.anonymous);
    }
  }

  Future<void> _restoreNative(int current) async {
    final credential = await _vault.read();
    if (current != _epoch || _disposed) return;
    if (credential == null) {
      _setPhase(AuthPhase.anonymous);
      return;
    }
    try {
      await _refreshNative(expectedSession: credential.sessionRef);
      if (current != _epoch || _disposed) return;
      final refreshed = await _vault.read();
      if (current != _epoch || _disposed) return;
      if (refreshed?.sessionRef != credential.sessionRef) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      _sessionRef = credential.sessionRef;
      final access = await repository.access(admin: false, headers: _readHeaders());
      if (current == _epoch && !_disposed) _acceptAccess(access, admin: false);
    } on ApiFailure catch (error) {
      if (error.code == 'REFRESH_SUPERSEDED') {
        // Another process may have committed the new generation. Keep its vault
        // entry intact and let a later explicit restore rebind this process.
        rethrow;
      }
      if (!_isUnauthenticated(error)) rethrow;
      if (current == _epoch && !_disposed) {
        await _vault.clear(sessionRef: credential.sessionRef);
        if (current == _epoch && !_disposed) _setPhase(AuthPhase.anonymous);
      }
    }
  }

  bool _isUnauthenticated(ApiFailure error) => const {
    'AUTH_REQUIRED',
    'SESSION_INVALID',
    'SESSION_REVOKED',
    'ACCESS_EXPIRED',
  }.contains(error.code);

  void _acceptAccess(AccessRead access, {required bool admin}) {
    if (access.instanceId != _boundInstanceId ||
        access.audience != (admin ? 'admin' : 'client') ||
        (_sessionRef != null && _sessionRef != access.sessionRef)) {
      throw const ApiFailure(code: 'INSTANCE_MISMATCH');
    }
    _access = access;
    _accessValidationAge = Stopwatch()..start();
    _accessDeadline?.cancel();
    _accessDeadline = Timer(const Duration(seconds: 30), () {
      if (!_disposed && _access != null) _setPhase(AuthPhase.unavailable);
    });
    _sessionRef = access.sessionRef;
    _admin = admin;
    repository.api.bindConfirmedAccess(access);
    _setPhase(AuthPhase.authenticated);
  }

  /// Periodic foreground identity check. A missing successful check for thirty
  /// seconds closes private UI; a later successful access may reopen it.
  Future<bool> verifyCurrentAccess() async {
    final prior = _access;
    final session = _sessionRef;
    final captured = _epoch;
    if (prior == null || session == null || _disposed) return false;
    try {
      late AccessRead active;
      try {
        active = await repository.access(admin: _admin, headers: _readHeaders());
      } on ApiFailure catch (error) {
        if (error.code != 'ACCESS_EXPIRED' || config.platform == AppPlatform.web) rethrow;
        await _refreshNativeSingleFlight();
        if (_disposed || captured != _epoch) return false;
        active = await repository.access(admin: _admin, headers: _readHeaders());
      }
      if (_disposed || captured != _epoch) return false;
      if (active.sessionRef != session || active.userId != prior.userId) {
        final wasAdmin = _admin;
        _clearMemory();
        _setPhase(AuthPhase.unavailable);
        unawaited(start(admin: wasAdmin));
        return false;
      }
      _acceptAccess(active, admin: _admin);
      return true;
    } on ApiFailure catch (error) {
      if (!_disposed &&
          captured == _epoch &&
          const {
            'AUTH_REQUIRED',
            'ACCESS_EXPIRED',
            'SESSION_REVOKED',
            'SESSION_INVALID',
            'AUTH_SCOPE_CHANGED',
            'PERMISSION_DENIED',
          }.contains(error.code)) {
        _setPhase(AuthPhase.unavailable);
        if (error.code == 'AUTH_SCOPE_CHANGED' || error.code == 'SESSION_INVALID') {
          final wasAdmin = _admin;
          _clearMemory();
          unawaited(start(admin: wasAdmin));
        }
      }
      return false;
    } on Object {
      if (!_disposed &&
          captured == _epoch &&
          (_accessValidationAge?.elapsed ?? Duration.zero) >= const Duration(seconds: 30)) {
        _setPhase(AuthPhase.unavailable);
      }
      return false;
    }
  }

  void pauseAccessDeadline() => _accessDeadline?.cancel();

  void resumeAccessDeadline() {
    if (_disposed || _access == null) return;
    _accessDeadline?.cancel();
    final remaining =
        const Duration(seconds: 30) -
        (_accessValidationAge?.elapsed ?? const Duration(seconds: 30));
    if (remaining <= Duration.zero) {
      _setPhase(AuthPhase.unavailable);
    } else {
      _accessDeadline = Timer(remaining, () {
        if (!_disposed && _access != null) _setPhase(AuthPhase.unavailable);
      });
    }
  }

  Future<bool> login(
    String email,
    String password, {
    bool admin = false,
    String? operationId,
  }) async {
    if (_disposed || _switchingInstance) throw const ApiFailure(code: 'SESSION_INVALID');
    if (admin && config.platform != AppPlatform.web) {
      throw const ApiFailure(code: 'PERMISSION_DENIED');
    }
    final current = ++_epoch;
    _preferredAdmin = admin;
    _clearMemory();
    _setPhase(AuthPhase.starting);
    final audience = admin ? 'admin' : 'client';
    _sync.setLocallySignedOut(audience, true);
    try {
      return await _identityWrite(() async {
        if (current != _epoch || _disposed) return false;
        await _vault.clear();
        if (current != _epoch || _disposed) return false;
        await repository.verifyInstance();
        if (current != _epoch || _disposed) return false;
        final result = await repository.login(
          email,
          password,
          admin: admin,
          operationId: operationId,
        );
        if (current != _epoch || _disposed) return false;
        if (result.pending) {
          _continuationToken = result.continuationToken;
          _continuationExpiresAt = result.continuationExpiresAt;
          _setPhase(AuthPhase.pendingEmail);
          return false;
        }
        _sessionRef = result.sessionRef;
        if (config.platform == AppPlatform.web) {
          final csrf = await repository.csrf(admin: admin);
          if (current != _epoch || _disposed) return false;
          if (csrf.sessionRef != result.sessionRef) {
            throw const ApiFailure(code: 'SESSION_INVALID');
          }
          if (admin) {
            _csrfAdmin = csrf.token;
          } else {
            _csrfClient = csrf.token;
          }
        } else {
          final credential = RefreshCredential(
            sessionRef: result.sessionRef!,
            generation: result.generation!,
            secret: result.refreshToken!,
          );
          if (!await _vault.replace(null, credential)) {
            throw const ApiFailure(code: 'SESSION_INVALID');
          }
          if (current != _epoch || _disposed) return false;
          _accessToken = result.accessToken;
        }
        late final AccessRead access;
        try {
          access = await repository.access(admin: admin, headers: _readHeaders());
        } on ApiFailure catch (error) {
          if (error.code == 'SESSION_INVALID' && current != _epoch) return false;
          rethrow;
        }
        if (current != _epoch || _disposed) return false;
        _sync.setLocallySignedOut(audience, false);
        _acceptAccess(access, admin: admin);
        return true;
      });
    } on Object {
      if (current == _epoch && !_disposed) {
        final failedSession = _sessionRef;
        _clearMemory();
        if (failedSession != null) await _vault.clear(sessionRef: failedSession);
        if (current == _epoch && !_disposed) _setPhase(AuthPhase.anonymous);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    await _clearIfCurrent(_epoch, _sessionRef);
  }

  Future<bool> _clearIfCurrent(int capturedEpoch, String? capturedSession) async {
    if (_disposed || _epoch != capturedEpoch || _sessionRef != capturedSession) return false;
    ++_epoch;
    _sync.setLocallySignedOut(_admin ? 'admin' : 'client', true);
    _clearMemory();
    await _vault.clear(sessionRef: capturedSession);
    if (!_disposed && _epoch == capturedEpoch + 1) _setPhase(AuthPhase.anonymous);
    _sync.publishChanged();
    return !_disposed && _epoch == capturedEpoch + 1;
  }

  @override
  void dispose() {
    _disposed = true;
    _accessDeadline?.cancel();
    ++_epoch;
    repository.api.onSessionBindingLost = null;
    repository.api.clearSessionBinding();
    _sync.dispose();
    super.dispose();
  }

  Future<void> signOut({String? operationId}) async {
    final id = _sessionRef;
    final audienceAdmin = _admin;
    final headers = _writeHeaders();
    final captured = _epoch;
    final requestBinding = repository.api.sessionBinding;
    if (!isAuthenticated || id == null) {
      await logout();
      return;
    }
    _sync.setLocallySignedOut(audienceAdmin ? 'admin' : 'client', true);
    if (await _clearIfCurrent(captured, id)) {
      _lastLocalSignOutEpoch = captured;
      _lastLocalSignOutSession = id;
    }
    if (requestBinding == null) throw const ApiFailure(code: 'SESSION_INVALID');
    try {
      await repository.api.withRetiredSignOutBinding(
        requestBinding,
        () => _identityWrite(() async {
          await repository.verifyInstance();
          if (config.platform == AppPlatform.web) {
            // A different tab may have signed in while this operation waited for
            // the cross-tab lock. Never log out that newer cookie identity.
            final current = await repository.access(admin: audienceAdmin, headers: const {});
            if (current.sessionRef != id) {
              _sync.setLocallySignedOut(audienceAdmin ? 'admin' : 'client', false);
              return;
            }
            await repository.logout(
              admin: audienceAdmin,
              headers: headers,
              operationId: operationId,
            );
          } else {
            await repository.revoke(id, admin: false, headers: headers, operationId: operationId);
          }
        }),
      );
    } on ApiFailure catch (error) {
      if (error.code != 'SESSION_INVALID' || captured + 1 == _epoch) rethrow;
    }
  }

  void _clearMemory() {
    _accessDeadline?.cancel();
    _accessValidationAge = null;
    repository.api.clearSessionBinding();
    _accessToken = null;
    _continuationToken = null;
    _continuationExpiresAt = null;
    _csrfClient = null;
    _csrfAdmin = null;
    _access = null;
    _sessionRef = null;
    _admin = false;
  }

  Map<String, String> _readHeaders() => config.platform == AppPlatform.web
      ? const {}
      : {'Authorization': 'Bearer ${_accessToken ?? ''}'};

  Map<String, String> _writeHeaders() => config.platform == AppPlatform.web
      ? {'X-CSRF-Token': (_admin ? _csrfAdmin : _csrfClient) ?? ''}
      : _readHeaders();

  Future<T> authorizedRead<T>(Future<T> Function(Map<String, String>) action) =>
      _authorized(action);

  Future<T> authorizedWrite<T>(Future<T> Function(Map<String, String>) action) =>
      _authorized(action, write: true);

  Future<T> _authorized<T>(
    Future<T> Function(Map<String, String>) action, {
    bool write = false,
  }) async {
    if (!isAuthenticated) throw const ApiFailure(code: 'AUTH_REQUIRED');
    final current = _epoch;
    final session = _sessionRef;
    final userId = _access!.userId;
    final operationId = AuthRepository.newRequestId();
    try {
      final result = await action({
        ...(write ? _writeHeaders() : _readHeaders()),
        'X-Operation-ID': operationId,
      });
      if (current != _epoch || _access?.userId != userId) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      if (write) unawaited(verifyCurrentAccess());
      return result;
    } on ApiFailure catch (error) {
      if (error.code == 'ACCESS_EXPIRED' && config.platform != AppPlatform.web) {
        if (current != _epoch || _disposed || _sessionRef != session) {
          throw const ApiFailure(code: 'SESSION_INVALID');
        }
        try {
          // ACCESS_EXPIRED is a definitive pre-handler rejection. A single
          // refresh and resubmission is safe; unknown results are never replayed.
          await _refreshNativeSingleFlight();
          if (current != _epoch || _access?.userId != userId) {
            throw const ApiFailure(code: 'SESSION_INVALID');
          }
          final result = await action({
            ...(write ? _writeHeaders() : _readHeaders()),
            'X-Operation-ID': operationId,
          });
          if (current != _epoch || _access?.userId != userId) {
            throw const ApiFailure(code: 'SESSION_INVALID');
          }
          if (write) unawaited(verifyCurrentAccess());
          return result;
        } on ApiFailure catch (refreshError) {
          if (_isUnauthenticated(refreshError)) {
            await _clearIfCurrent(current, session);
          }
          rethrow;
        }
      }
      if (_isUnauthenticated(error)) {
        await _clearIfCurrent(current, session);
      }
      rethrow;
    }
  }

  Future<void> _refreshNativeSingleFlight() {
    final flight = _refreshFlight;
    if (flight != null && _refreshFlightEpoch == _epoch && _refreshFlightSession == _sessionRef) {
      return flight;
    }
    final epoch = _epoch;
    final session = _sessionRef;
    if (session == null) throw const ApiFailure(code: 'SESSION_INVALID');
    final next = _refreshNative(expectedSession: session);
    _refreshFlight = next;
    _refreshFlightEpoch = epoch;
    _refreshFlightSession = session;
    void release() {
      if (identical(_refreshFlight, next)) {
        _refreshFlight = null;
        _refreshFlightEpoch = null;
        _refreshFlightSession = null;
      }
    }

    unawaited(
      next.then<void>((_) => release(), onError: (Object error, StackTrace stack) => release()),
    );
    return next;
  }

  Future<void> _refreshNative({required String expectedSession}) async {
    final current = _epoch;
    for (var attempt = 0; attempt < 2; attempt++) {
      var prior = await _vault.read();
      if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
      if (prior == null) throw const ApiFailure(code: 'SESSION_INVALID');
      if (prior.sessionRef != expectedSession) {
        throw const ApiFailure(code: 'REFRESH_SUPERSEDED');
      }
      if (prior.pendingRequestId == null) {
        final pending = RefreshCredential(
          sessionRef: prior.sessionRef,
          generation: prior.generation,
          secret: prior.secret,
          pendingRequestId: AuthRepository.newRequestId(),
          pendingAt: DateTime.now().toUtc(),
        );
        if (await _vault.replace(prior, pending)) {
          prior = pending;
        } else {
          // A competing process may have published a newer generation. Read its
          // durable value on the next bounded attempt; never reuse this request.
          continue;
        }
      }
      if (current != _epoch || _disposed) throw const ApiFailure(code: 'SESSION_INVALID');
      if (prior.sessionRef != expectedSession) throw const ApiFailure(code: 'REFRESH_SUPERSEDED');
      // The server only retains an encrypted same-request receipt for 10 seconds.
      // Beyond this conservative window, a retry with the old secret is unsafe.
      if (DateTime.now().toUtc().difference(prior.pendingAt!) >= const Duration(seconds: 8)) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      final result = await repository.nativeRefresh(prior.secret, prior.pendingRequestId!);
      if (current != _epoch ||
          _disposed ||
          result.pending ||
          result.sessionRef != expectedSession ||
          result.generation != prior.generation + 1) {
        throw const ApiFailure(code: 'SESSION_INVALID');
      }
      final next = RefreshCredential(
        sessionRef: result.sessionRef!,
        generation: result.generation!,
        secret: result.refreshToken!,
      );
      if (!await _vault.replace(prior, next)) {
        continue;
      }
      if (current != _epoch || _disposed) return;
      _accessToken = result.accessToken;
      return;
    }
    throw const ApiFailure(code: 'REFRESH_SUPERSEDED');
  }

  Future<PageResponse<SessionSummary>> sessions({String? cursor}) => _authorized(
    (headers) => repository.sessions(admin: _admin, headers: headers, cursor: cursor),
  );

  Future<AccountRead> account() => _authorized((headers) => repository.account(headers));

  Future<void> revoke(String id, {String? operationId}) async {
    if (id == _sessionRef) {
      await signOut(operationId: operationId);
      return;
    }
    await _authorized(
      (headers) => repository.revoke(id, admin: _admin, headers: headers, operationId: operationId),
      write: true,
    );
  }

  Future<bool> revokeAll() async {
    final captured = _epoch;
    final session = _sessionRef;
    await _identityWrite(
      () => _authorized(
        (headers) => repository.revokeAll(admin: _admin, headers: headers),
        write: true,
      ),
    );
    return _clearIfCurrent(captured, session);
  }

  Future<void> changePassword(
    String currentPassword,
    String nextPassword, {
    String? operationId,
  }) async {
    final captured = _epoch;
    final session = _sessionRef;
    try {
      await _identityWrite(
        () => _authorized(
          (headers) => repository.changePassword(
            currentPassword,
            nextPassword,
            admin: _admin,
            headers: headers,
            operationId: operationId,
          ),
          write: true,
        ),
      );
    } on ApiFailure catch (error) {
      // Known pre-commit rejection can be corrected in the current session.
      if (!const {
        'INPUT_INVALID',
        'BAD_REQUEST',
        'AUTH_LOGIN_FAILED',
        'REVISION_CONFLICT',
        'CSRF_FAILED',
        'PERMISSION_DENIED',
        'RATE_LIMITED',
        'STATE_CONFLICT',
      }.contains(error.code)) {
        // A lost response may follow a committed change. Never auto-replay.
        await _clearIfCurrent(captured, session);
      }
      rethrow;
    } on Object {
      await _clearIfCurrent(captured, session);
      rethrow;
    }
    await _clearIfCurrent(captured, session);
  }

  Future<AdminPolicy> adminPolicy() => _authorized((headers) => repository.adminPolicy(headers));

  Future<AdminPolicy> updateAdminPolicy(
    String registrationMode,
    int revision, {
    String? recoveryMode,
  }) => _authorized(
    (headers) => repository.updateAdminPolicy(
      registrationMode,
      revision,
      headers,
      recoveryMode: recoveryMode,
    ),
    write: true,
  );

  Future<List<RoleRead>> adminRoles() =>
      authorizedRead((headers) => repository.adminRoles(headers));

  Future<RoleRead> adminRole(String roleId) =>
      authorizedRead((headers) => repository.adminRole(roleId, headers));

  Future<List<PermissionCatalogRead>> adminPermissions() =>
      authorizedRead((headers) => repository.adminPermissions(headers));

  Future<List<GrantBoundaryRead>> adminGrantBoundaries(String roleId) =>
      authorizedRead((headers) => repository.adminGrantBoundaries(roleId, headers));

  Future<AuthorizationWriteResult> createAdminRole(String code, String name, String? description) =>
      authorizedWrite((headers) => repository.createAdminRole(code, name, description, headers));

  Future<AuthorizationWriteResult> updateAdminRole(
    String roleId,
    int revision,
    String name,
    String? description,
  ) => authorizedWrite(
    (headers) => repository.updateAdminRole(roleId, revision, name, description, headers),
  );

  Future<AuthorizationWriteResult> setAdminRoleEnabled(String roleId, int revision, bool enabled) =>
      authorizedWrite(
        (headers) => repository.setAdminRoleEnabled(roleId, revision, enabled, headers),
      );

  Future<AuthorizationWriteResult> replaceAdminRoleGrants(
    String roleId,
    int revision,
    List<RoleGrantRead> grants,
  ) => authorizedWrite(
    (headers) => repository.replaceAdminRoleGrants(roleId, revision, grants, headers),
  );

  Future<AuthorizationWriteResult> replaceAdminRoleParents(
    String roleId,
    int revision,
    List<String> parentRoleIds,
  ) => authorizedWrite(
    (headers) => repository.replaceAdminRoleParents(roleId, revision, parentRoleIds, headers),
  );

  Future<AuthorizationWriteResult> deleteAdminRole(String roleId, int revision) =>
      authorizedWrite((headers) => repository.deleteAdminRole(roleId, revision, headers));

  Future<AuthorizationWriteResult> replaceAdminGrantBoundaries(
    String roleId,
    int revision,
    List<GrantBoundaryRead> boundaries,
  ) => authorizedWrite(
    (headers) => repository.replaceAdminGrantBoundaries(roleId, revision, boundaries, headers),
  );

  Future<List<GovernedAccountRead>> adminAccounts() =>
      authorizedRead((headers) => repository.adminAccounts(headers));

  Future<GovernedAccountRead> adminAccount(String userId) =>
      authorizedRead((headers) => repository.adminAccount(userId, headers));

  Future<AccountCeilingsRead> adminAccountCeilings() =>
      authorizedRead((headers) => repository.adminAccountCeilings(headers));

  Future<GovernanceSummaryRead> adminGovernanceSummary() =>
      authorizedRead((headers) => repository.adminGovernanceSummary(headers));

  Future<PageResponse<AuditEventRead>> adminAuditEvents({String? cursor, String? result}) =>
      authorizedRead(
        (headers) => repository.adminAuditEvents(headers, cursor: cursor, result: result),
      );

  Future<AccountWriteResult> createAdminAccount(
    String email,
    String? displayName,
    List<String> roleIds,
  ) => authorizedWrite(
    (headers) => repository.createAdminAccount(email, displayName, roleIds, headers),
  );

  Future<AccountWriteResult> setAdminAccountStatus(String userId, int revision, String status) =>
      authorizedWrite(
        (headers) => repository.setAdminAccountStatus(userId, revision, status, headers),
      );

  Future<AccountWriteResult> decideAdminApproval(String userId, int revision, String decision) =>
      authorizedWrite(
        (headers) => repository.decideAdminApproval(userId, revision, decision, headers),
      );

  Future<AccountWriteResult> replaceAdminAccountRoles(
    String userId,
    int revision,
    List<String> roleIds,
  ) => authorizedWrite(
    (headers) => repository.replaceAdminAccountRoles(userId, revision, roleIds, headers),
  );

  Future<List<ManualRecoveryRead>> adminRecoveryRequests(String userId) =>
      authorizedRead((headers) => repository.adminRecoveryRequests(userId, headers));

  Future<ManualRecoveryDecisionResult> decideAdminRecovery(
    String userId,
    String challengeId,
    int revision,
    String decision,
    String? verificationMethod,
  ) => authorizedWrite(
    (headers) => repository.decideAdminRecovery(
      userId,
      challengeId,
      revision,
      decision,
      verificationMethod,
      headers,
    ),
  );

  Future<List<AccountSessionRead>> adminAccountSessions(String userId) =>
      authorizedRead((headers) => repository.adminAccountSessions(userId, headers));

  Future<List<MenuRead>> adminMenus() =>
      authorizedRead((headers) => repository.adminMenus(headers));

  Future<MenuCatalogRead> adminMenuCatalog() =>
      authorizedRead((headers) => repository.adminMenuCatalog(headers));

  Future<MenuWriteResult> createAdminMenuGroup(String code, String audience, String title) =>
      authorizedWrite((headers) => repository.createAdminMenuGroup(code, audience, title, headers));

  Future<MenuWriteResult> replaceAdminMenuLayout(List<MenuRead> items) =>
      authorizedWrite((headers) => repository.replaceAdminMenuLayout(items, headers));

  Future<MenuPreviewRead> previewAdminMenus(String userId, String audience) =>
      authorizedWrite((headers) => repository.previewAdminMenus(userId, audience, headers));

  Future<AccountWriteResult> revokeAdminAccountSessions(
    String userId,
    int revision,
    Map<String, Object?> body,
  ) => authorizedWrite(
    (headers) => repository.revokeAdminAccountSessions(userId, revision, body, headers),
  );
}

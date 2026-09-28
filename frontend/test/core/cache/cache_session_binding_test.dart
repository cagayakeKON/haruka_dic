import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_session_binding.dart';
import 'package:haruka/core/config/app_config.dart';

import '../../../test_support/sample_adapter.dart';

final class _NoSync implements AuthSync {
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  void dispose() {}
}

final class _NoVault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

final class _CacheRemote implements CacheRemote<Map<String, Object?>> {
  int fetches = 0;
  int validations = 0;
  CacheGrant? grant;

  @override
  Future<CachePayload<Map<String, Object?>>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    fetches++;
    return CachePayload(
      value: {'text': 'stored'},
      version: const CacheVersion(resource: 'r1', representation: 'p1', artifact: 'a1'),
      grant: grant,
    );
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    validations++;
    return CacheValidation(state: ValidationState.same, version: known, grant: grant);
  }
}

ResponseBody _jsonBody(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('access distinguishes absent security epoch from valid zero', () {
    final samples = jsonDecode(
      File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sample = samples['auth_client_access_login_only'] as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(sample['data'] as Map);
    data.remove('security_epoch');
    expect(AccessRead.fromJson(data).securityEpoch, isNull);
    data['security_epoch'] = 0;
    expect(AccessRead.fromJson(data).securityEpoch, 0);
    data['security_epoch'] = -1;
    expect(() => AccessRead.fromJson(data), throwsFormatException);
  });
  test('confirmed client access attaches cache; sign-out blocks and closes it', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    final samples = jsonDecode(
      File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final access = samples['auth_client_access_login_only'] as Map<String, dynamic>;
    (access['data'] as Map<String, dynamic>)['security_epoch'] = 0;
    final login = samples['auth_web_authenticated'] as Map<String, dynamic>;
    final sessionRef = (access['data'] as Map<String, dynamic>)['session_ref'] as String;
    var accessRequests = 0;
    var accessReplies = 0;
    var revokeAccess = false;
    Completer<void>? accessGate;
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return _jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          });
        case '/api/v1/auth/policy':
          return _jsonBody({
            'data': {
              'registration_enabled': false,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': true,
              'recovery_mode': 'email',
              'action_link_base_url': 'https://localhost:18443',
              'password_min_length': 15,
              'password_max_length': 128,
            },
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          });
        case '/api/v1/auth/login':
          return _jsonBody(login);
        case '/api/v1/auth/csrf':
          return _jsonBody({
            'data': {
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'session_ref': sessionRef,
            },
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          });
        case '/api/v1/me/access':
          accessRequests++;
          final gate = accessGate;
          if (gate != null) await gate.future;
          accessReplies++;
          if (revokeAccess) {
            return ResponseBody.fromString(
              jsonEncode({
                'error': {'code': 'SESSION_REVOKED'},
                'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
              }),
              401,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          return _jsonBody(access);
        case '/api/v1/auth/logout':
          return ResponseBody.fromString('', 204);
      }
      throw StateError('Unexpected path ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _NoVault(),
      sync: _NoSync(),
    );
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    cache.register(
      CachePolicy<Map<String, Object?>>(
        kind: 'material_content',
        disposition: CacheDisposition.validatedText,
        decode: (json) => json,
        encode: (data) => data,
        dependencies: (_) => {'material:one'},
      ),
    );
    final binding = CacheSessionBinding(auth, config, cache);
    addTearDown(() async {
      final pendingAccess = accessGate;
      if (pendingAccess != null && !pendingAccess.isCompleted) pendingAccess.complete();
      await binding.dispose();
      auth.dispose();
      api.close();
    });

    expect(cache.scope, isNull);
    expect(await auth.login('reader@example.test', 'sample-password'), isTrue);
    await binding.settled;
    expect(cache.scope?.userId, (access['data'] as Map<String, dynamic>)['user_id']);
    expect(cache.scope?.sessionRef, sessionRef);
    expect(cache.scope?.audience, 'client');
    expect(cache.scope?.securityEpoch, 0);
    expect(cache.storageMode, CacheStorageMode.persistent);

    const resource = CacheResource(
      kind: 'material_content',
      id: 'chapter-one',
      projection: 'novel-reading-v1',
      action: 'material.read',
      sourceBinding: 'material-one',
    );
    final remote = _CacheRemote();
    expect((await cache.read(resource: resource, remote: remote)).localReady, isTrue);
    await auth.start();
    await binding.settled;
    expect(auth.phase, AuthPhase.authenticated);
    expect(cache.scope?.sessionRef, sessionRef);
    expect((await cache.read(resource: resource, remote: remote)).data?['text'], 'stored');
    expect(remote.fetches, 1, reason: 'A transient access recheck must not erase local cache');
    expect(remote.validations, 1);

    final priorAccessRequests = accessRequests;
    final priorFetches = remote.fetches;
    final priorValidations = remote.validations;
    binding.didChangeAppLifecycleState(AppLifecycleState.hidden);
    binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(cache.accessReady, isTrue, reason: 'Return keeps a still-valid projection mounted');
    expect(binding.foregroundRevalidating.value, isFalse);
    for (var attempt = 0; accessRequests == priorAccessRequests && attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(accessRequests, priorAccessRequests + 1);
    expect(auth.phase, AuthPhase.authenticated);
    expect(cache.accessReady, isTrue);
    expect(remote.fetches, priorFetches);
    expect(remote.validations, priorValidations);

    CacheGrant newGrant([CacheResource? target]) {
      final owner = cache.scope!;
      final now = DateTime.now().toUtc();
      return CacheGrant(
        scopeBinding: owner.binding,
        resourceKey: (target ?? resource).keyFor(owner),
        version: const CacheVersion(resource: 'r1', representation: 'p1', artifact: 'a1'),
        serverTime: now,
        expiresAt: now.add(const Duration(minutes: 5)),
        securityEpoch: owner.securityEpoch,
        authzVersion: owner.authzVersion,
        policyVersion: owner.policyVersion,
      );
    }

    remote.grant = newGrant();
    await cache.read(resource: resource, remote: remote, forceRefresh: true);
    cache.enterOfflineForUnreachableNetwork();
    expect(
      (await cache.read(resource: resource, remote: remote)).freshness,
      CacheFreshness.offline,
    );

    final waitingAccess = Completer<void>();
    accessGate = waitingAccess;
    final requestsBeforeReturn = accessRequests;
    final repliesBeforeReturn = accessReplies;
    const backgroundResource = CacheResource(
      kind: 'material_content',
      id: 'chapter-two',
      projection: 'novel-reading-v1',
      action: 'material.read',
      sourceBinding: 'material-one',
    );
    final fetchesBeforeBackground = remote.fetches;
    binding.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(cache.accessReady, isTrue, reason: 'Backgrounding keeps the online page mounted');
    expect(cache.isOffline, isFalse, reason: 'A sleeping clock cannot retain offline mode');
    cache.enterOfflineForUnreachableNetwork();
    expect(cache.isOffline, isFalse, reason: 'A background page cannot re-enter offline mode');
    remote.grant = newGrant(backgroundResource);
    final backgroundRead = await cache.read(resource: backgroundResource, remote: remote);
    expect(backgroundRead.freshness, isNot(CacheFreshness.offline));
    expect(remote.fetches, fetchesBeforeBackground + 1);
    final fetchesBeforeReturn = remote.fetches;
    final validationsBeforeReturn = remote.validations;
    binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
    for (var attempt = 0; accessRequests == requestsBeforeReturn && attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(accessRequests, requestsBeforeReturn + 1);
    expect(accessReplies, repliesBeforeReturn, reason: 'The access response is still pending');
    expect(cache.accessReady, isTrue);
    expect(remote.fetches, fetchesBeforeReturn);
    expect(remote.validations, validationsBeforeReturn);
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: remote),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'offline_grant_unavailable'),
      ),
      reason: 'The old grant cannot survive backgrounding or a slow access response',
    );

    waitingAccess.complete();
    for (var attempt = 0; accessReplies == repliesBeforeReturn && attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    accessGate = null;
    expect(accessReplies, repliesBeforeReturn + 1);
    expect(auth.phase, AuthPhase.authenticated);
    expect(cache.accessReady, isTrue);
    await expectLater(
      cache.read(resource: resource, remote: remote),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'offline_grant_unavailable'),
      ),
      reason: 'A fresh access response does not renew a resource-specific offline grant',
    );
    expect(remote.fetches, fetchesBeforeReturn);
    expect(remote.validations, validationsBeforeReturn);

    binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
    remote.grant = newGrant();
    await cache.read(resource: resource, remote: remote, forceRefresh: true);
    cache.enterOfflineForUnreachableNetwork();
    expect(
      (await cache.read(resource: resource, remote: remote)).freshness,
      CacheFreshness.offline,
      reason: 'Only a new online resource validation can issue a usable grant',
    );
    await expectLater(
      cache.read(resource: backgroundResource, remote: remote),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'offline_grant_unavailable'),
      ),
      reason: 'A response accepted in the background cannot publish an offline grant',
    );

    revokeAccess = true;
    binding.didChangeAppLifecycleState(AppLifecycleState.hidden);
    binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
    for (var attempt = 0; auth.phase != AuthPhase.unavailable && attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(auth.phase, AuthPhase.unavailable);
    expect(cache.accessReady, isFalse, reason: 'A revoked session cannot expose old rows');

    await auth.signOut();
    await binding.settled;
    expect(cache.scope, isNull);
  });
}

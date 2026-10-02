import 'dart:async';
import 'dart:convert';

import 'support/generated/api_compatibility_samples.dart';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';

import 'support/sample_adapter.dart';

final class _MemoryVault implements CredentialVault {
  RefreshCredential? current;
  @override
  Future<RefreshCredential?> read() async => current;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    if (prior == null ? current != null : current == null || !prior.sameVersion(current!)) {
      return false;
    }
    current = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async {
    if (sessionRef == null || current?.sessionRef == sessionRef) current = null;
  }
}

final class _CompetingVault implements CredentialVault {
  RefreshCredential? current;
  bool competingCommit = true;
  bool switchingSession = false;
  @override
  Future<RefreshCredential?> read() async => current;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    if (prior == null ? current != null : current == null || !prior.sameVersion(current!)) {
      return false;
    }
    if (competingCommit &&
        prior != null &&
        prior.pendingRequestId != null &&
        next.generation == prior.generation + 1) {
      competingCommit = false;
      current = RefreshCredential(
        sessionRef: switchingSession ? '018f1234-0000-7000-8000-000000000003' : next.sessionRef,
        generation: next.generation,
        secret: 'competing-refresh',
      );
      return false;
    }
    current = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async {
    if (sessionRef == null || current?.sessionRef == sessionRef) current = null;
  }
}

final class _NoSync implements AuthSync {
  final Map<String, bool> markers = {};
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => markers[audience] ?? false;
  @override
  void setLocallySignedOut(String audience, bool value) => markers[audience] = value;
  @override
  void dispose() {}
}

ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  const csrfTest = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const csrfB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
  const sessionA = '018f1234-0000-7000-8000-000000000002';
  const sessionB = '018f1234-0000-7000-8000-000000000003';
  final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
  final config = AppConfig.parse(
    platform: AppPlatform.windows,
    environment: 'dev',
    instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
    apiBaseUrl: 'http://127.0.0.1:18081',
  );
  final requestId = '018f1234-1234-7123-8123-123456789abc';

  test('session pages reuse complete data, invalidate after revoke and reject a late old identity read', () async {
    var reads = 0;
    var block = false;
    var started = Completer<void>();
    var release = Completer<void>();
    final adapter = SampleAdapter((options, _) async {
      switch (options.uri.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/native/login':
          return jsonBody(samples['auth_native_authenticated'] as Object);
        case '/api/v1/me/access':
          return jsonBody(samples['auth_client_access_login_only'] as Object);
        case '/api/v1/auth/sessions':
          reads++;
          if (block) {
            started.complete();
            await release.future;
          }
          return jsonBody(samples['auth_sessions_page'] as Object);
        case '/api/v1/auth/sessions/$sessionB/revoke':
          return ResponseBody.fromString('', 204);
      }
      throw StateError('Unexpected ${options.method} ${options.uri.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    expect(await controller.login('a@example.test', 'private-password'), isTrue);
    final first = await controller.sessions();
    expect(await controller.sessions(), same(first));
    await controller.sessions(cursor: 'next');
    await controller.sessions(cursor: 'next');
    expect(reads, 2);
    await controller.revoke(sessionB);
    await controller.sessions();
    expect(reads, 3);
    block = true;
    final late = controller.sessions(cursor: 'late');
    await started.future;
    final mergedLate = controller.sessions(cursor: 'late');
    await controller.revoke(sessionB);
    final staleFailure = throwsA(
      isA<ApiFailure>().having((failure) => failure.code, 'code', 'SESSION_INVALID'),
    );
    final firstRejected = expectLater(late, staleFailure);
    final secondRejected = expectLater(mergedLate, staleFailure);
    release.complete();
    await Future.wait([firstRejected, secondRejected]);
    started = Completer<void>();
    release = Completer<void>();
    final oldIdentity = controller.sessions(cursor: 'old-identity');
    await started.future;
    final oldIdentityRejected = expectLater(oldIdentity, staleFailure);
    await controller.logout();
    release.complete();
    await oldIdentityRejected;
    block = false;
    expect(await controller.login('b@example.test', 'private-password'), isTrue);
    await controller.sessions();
    expect(reads, 6);
  });

  test('adopting an endpoint clears old policy until the new policy is verified', () async {
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/policy') {
        return jsonBody({
          'data': {
            'registration_enabled': options.uri.port == 18081,
            'approval_required': false,
            'email_verification_required': true,
            'recovery_enabled': true,
            'recovery_mode': 'email',
            'action_link_base_url': 'https://localhost:18443',
            'password_min_length': 15,
            'password_max_length': 128,
          },
          'meta': {'request_id': requestId},
        });
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(config, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    await controller.reloadPolicy();
    expect(controller.policy?.registrationEnabled, isTrue);
    final nextEndpoint = Uri.parse('http://127.0.0.1:18082');
    api.retarget(nextEndpoint, config.instanceId);
    controller.adoptInstance(nextEndpoint, config.instanceId);
    expect(controller.policy, isNull);
    expect(controller.phase, AuthPhase.anonymous);
    await controller.reloadPolicy();
    expect(controller.policy?.registrationEnabled, isFalse);
    controller.dispose();
    api.close();
  });

  test('a switch during meta verification never sends a pending registration password', () async {
    final metaStarted = Completer<void>();
    final releaseMeta = Completer<void>();
    var registrationRequests = 0;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        metaStarted.complete();
        await releaseMeta.future;
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/register') registrationRequests++;
      throw StateError('Unexpected path');
    });
    final api = ApiClient(config, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    final pending = controller.register('test@example.com', 'private-password');
    await metaStarted.future;
    controller.invalidateForInstanceSwitch();
    await expectLater(
      controller.requestRecovery('test@example.com'),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_INVALID')),
    );
    final nextEndpoint = Uri.parse('http://127.0.0.1:18082');
    api.retarget(nextEndpoint, config.instanceId);
    controller.adoptInstance(nextEndpoint, config.instanceId);
    releaseMeta.complete();
    await expectLater(
      pending,
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_INVALID')),
    );
    expect(registrationRequests, 0);
    controller.finishInstanceSwitch();
    controller.dispose();
    api.close();
  });

  test('resend accepts the exact 202 check_email contract receipt', () async {
    final receipt = samples['auth_mail_accepted'] as Map<String, dynamic>;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/email/resend') {
        return jsonBody(receipt['response'] as Object, receipt['status'] as int);
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(config, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await controller.resend('user@example.test');
  });

  for (final logUpload in [false, true]) {
    test(
      'native ACCESS_EXPIRED refreshes once before ${logUpload ? 'log upload' : 'business write'}',
      () async {
        var refreshCalls = 0;
        var accessCalls = 0;
        final adapter = SampleAdapter((options, _) async {
          if (options.path == '/api/v1/meta') {
            return jsonBody({
              'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
              'meta': {'request_id': requestId},
            });
          }
          if (options.path == '/api/v1/auth/native/login') {
            return jsonBody(samples['auth_native_authenticated'] as Object);
          }
          if (options.path == '/api/v1/me/access') {
            accessCalls++;
            return jsonBody(samples['auth_client_access_login_only'] as Object);
          }
          if (options.path == '/api/v1/auth/native/refresh') {
            refreshCalls++;
            final refreshed = jsonDecode(
              jsonEncode(samples['auth_native_authenticated']),
            ) as Map<String, dynamic>;
            final data = refreshed['data'] as Map<String, dynamic>;
            data['session_generation'] = 2;
            data['access_token'] = 'rotated-access';
            data['refresh_token'] = 'rotated-refresh';
            return jsonBody(refreshed);
          }
          throw StateError('Unexpected path');
        });
        final api = ApiClient(config, adapter: adapter);
        final vault = _MemoryVault();
        final controller = AuthController(
          AuthRepository(api, config),
          config,
          vault: vault,
          sync: _NoSync(),
        );
        addTearDown(() {
          controller.dispose();
          api.close();
        });
        expect(await controller.login('user@example.test', 'valid-test-password'), isTrue);
        var writes = 0;
        String? operationId;
        final send = logUpload
            ? controller.authorizedLogUpload<void>
            : controller.authorizedWrite<void>;
        await send((headers) async {
          writes++;
          operationId ??= headers['X-Operation-ID'];
          expect(headers['X-Operation-ID'], operationId);
          if (writes == 1) throw const ApiFailure(code: 'ACCESS_EXPIRED');
          expect(headers['Authorization'], 'Bearer rotated-access');
        });
        expect(writes, 2);
        expect(operationId, isNotNull);
        expect(refreshCalls, 1);
        expect(vault.current?.generation, 2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(accessCalls, logUpload ? 1 : 2);
      },
    );
  }

  test('native refresh rereads a competing committed credential once', () async {
    var refreshCalls = 0;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/native/login') {
        return jsonBody(samples['auth_native_authenticated'] as Object);
      }
      if (options.path == '/api/v1/me/access') {
        return jsonBody(samples['auth_client_access_login_only'] as Object);
      }
      if (options.path == '/api/v1/auth/native/refresh') {
        refreshCalls++;
        final refreshed =
            jsonDecode(jsonEncode(samples['auth_native_authenticated'])) as Map<String, dynamic>;
        final data = refreshed['data'] as Map<String, dynamic>;
        data['session_generation'] = refreshCalls + 1;
        data['access_token'] = 'rotated-$refreshCalls';
        data['refresh_token'] = 'new-refresh-$refreshCalls';
        return jsonBody(refreshed);
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(config, adapter: adapter);
    final vault = _CompetingVault();
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: vault,
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    expect(await controller.login('user@example.test', 'valid-test-password'), isTrue);
    var writes = 0;
    await controller.authorizedWrite((headers) async {
      if (++writes == 1) throw const ApiFailure(code: 'ACCESS_EXPIRED');
      expect(headers['Authorization'], 'Bearer rotated-2');
    });
    expect(refreshCalls, 2);
    expect(vault.current?.generation, 3);
  });

  test('same-epoch native vault switch never refreshes the other account', () async {
    var refreshCalls = 0;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/native/login') {
        return jsonBody(samples['auth_native_authenticated'] as Object);
      }
      if (options.path == '/api/v1/me/access') {
        return jsonBody(samples['auth_client_access_login_only'] as Object);
      }
      if (options.path == '/api/v1/auth/native/refresh') {
        refreshCalls++;
        final refreshed =
            jsonDecode(jsonEncode(samples['auth_native_authenticated'])) as Map<String, dynamic>;
        (refreshed['data'] as Map<String, dynamic>)['session_generation'] = 2;
        return jsonBody(refreshed);
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(config, adapter: adapter);
    final vault = _CompetingVault()..switchingSession = true;
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: vault,
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    expect(await controller.login('a@example.test', 'valid-test-password'), isTrue);
    await expectLater(
      controller.authorizedWrite((headers) async {
        throw const ApiFailure(code: 'ACCESS_EXPIRED');
      }),
      throwsA(isA<ApiFailure>()),
    );
    expect(refreshCalls, 1);
    expect(vault.current?.sessionRef, sessionB);
    expect(vault.current?.secret, 'competing-refresh');
    expect(controller.access?.sessionRef, sessionA);
  });

  test('late login A access cannot republish after account B takes the vault', () async {
    final firstAccess = Completer<ResponseBody>();
    final firstAccessReached = Completer<void>();
    final paths = <String>[];
    var accessCalls = 0;
    final adapter = SampleAdapter((options, Stream<Uint8List>? _) async {
      paths.add(options.path);
      if (options.path == '/api/v1/meta') {
        return jsonBody({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/policy') {
        return jsonBody({
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
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/native/login') {
        final email = (options.data as Map<String, Object?>)['email'];
        final value =
            jsonDecode(jsonEncode(samples['auth_native_authenticated'])) as Map<String, dynamic>;
        if (email == 'b@example.test') {
          (value['data'] as Map<String, dynamic>)['session_ref'] =
              '018f1234-0000-7000-8000-000000000003';
        }
        return jsonBody(value);
      }
      if (options.path == '/api/v1/me/access') {
        accessCalls++;
        if (accessCalls == 1) {
          firstAccessReached.complete();
          return firstAccess.future;
        }
        final value = jsonDecode(
          jsonEncode(samples['auth_client_access_login_only']),
        ) as Map<String, dynamic>;
        (value['data'] as Map<String, dynamic>)['session_ref'] =
            '018f1234-0000-7000-8000-000000000003';
        (value['data'] as Map<String, dynamic>)['user_id'] = '018f1234-0000-7000-8000-000000000004';
        return jsonBody(value);
      }
      throw StateError('Unexpected test path');
    });
    final api = ApiClient(config, adapter: adapter);
    final vault = _MemoryVault();
    final controller = AuthController(
      AuthRepository(api, config),
      config,
      vault: vault,
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await controller.start();
    expect(controller.phase, AuthPhase.anonymous);
    final loginA = controller.login('a@example.test', 'password-a');
    await firstAccessReached.future;
    final loginB = controller.login('b@example.test', 'password-b');
    // B begins while A's response is pending. Identity writes are serialized,
    // so A is discarded and then B can bind the final cookie/vault identity.
    firstAccess.complete(jsonBody(samples['auth_client_access_login_only'] as Object));
    expect(await loginA, isFalse);
    await loginB;
    expect(controller.access?.userId, '018f1234-0000-7000-8000-000000000004');
    expect(controller.access?.sessionRef, '018f1234-0000-7000-8000-000000000003');
    expect(vault.current?.sessionRef, '018f1234-0000-7000-8000-000000000003');
    expect(paths.where((path) => path == '/api/v1/auth/native/login'), hasLength(2));
  });

  for (final operation in ['logout', 'password', 'revoke_all']) {
    test('late $operation A completion cannot clear a newer Web login B', () async {
      final webConfig = AppConfig.parse(
        platform: AppPlatform.web,
        environment: 'dev',
        instanceId: config.instanceId,
        apiBaseUrl: 'https://localhost:18443',
      );
      final operationReached = Completer<void>();
      final finishOperation = Completer<ResponseBody>();
      var loginCount = 0;
      final sync = _NoSync();
      final adapter = SampleAdapter((options, _) async {
        if (options.path == '/api/v1/meta') {
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        }
        if (options.path == '/api/v1/auth/login') {
          loginCount++;
          final value =
              jsonDecode(jsonEncode(samples['auth_web_authenticated'])) as Map<String, dynamic>;
          if (loginCount == 2) {
            (value['data'] as Map<String, dynamic>)['session_ref'] =
                '018f1234-0000-7000-8000-000000000003';
          }
          return jsonBody(value);
        }
        if (options.path == '/api/v1/auth/csrf') {
          return jsonBody({
            'data': {'csrf_token': csrfTest, 'session_ref': loginCount == 2 ? sessionB : sessionA},
            'meta': {'request_id': requestId},
          });
        }
        if (options.path == '/api/v1/me/access') {
          final value = jsonDecode(
            jsonEncode(samples['auth_client_access_login_only']),
          ) as Map<String, dynamic>;
          if (loginCount == 2) {
            (value['data'] as Map<String, dynamic>)['session_ref'] =
                '018f1234-0000-7000-8000-000000000003';
            (value['data'] as Map<String, dynamic>)['user_id'] =
                '018f1234-0000-7000-8000-000000000004';
          }
          return jsonBody(value);
        }
        if (options.path ==
            (operation == 'logout'
                ? '/api/v1/auth/logout'
                : operation == 'password'
                ? '/api/v1/auth/password/change'
                : '/api/v1/auth/sessions/revoke-all')) {
          expect(options.headers['X-CSRF-Token'], csrfTest);
          operationReached.complete();
          return finishOperation.future;
        }
        throw StateError('Unexpected test path ${options.path}');
      });
      final api = ApiClient(webConfig, adapter: adapter);
      final controller = AuthController(
        AuthRepository(api, webConfig),
        webConfig,
        vault: _MemoryVault(),
        sync: sync,
      );
      addTearDown(() {
        controller.dispose();
        api.close();
      });
      expect(await controller.login('a@example.test', 'valid-test-password'), isTrue);
      expect(api.sessionBinding?.sessionRef, sessionA);
      final oldAction = operation == 'logout'
          ? controller.signOut()
          : operation == 'password'
          ? controller.changePassword('old-password-123', 'new-password-123')
          : controller.revokeAll();
      await operationReached.future;
      final loginB = controller.login('b@example.test', 'valid-test-password');
      finishOperation.complete(ResponseBody.fromString('', 204));
      if (operation != 'logout') {
        await expectLater(oldAction, throwsA(isA<ApiFailure>()));
      } else {
        await oldAction;
      }
      expect(await loginB, isTrue);
      expect(controller.access?.sessionRef, '018f1234-0000-7000-8000-000000000003');
      expect(controller.access?.userId, '018f1234-0000-7000-8000-000000000004');
      expect(api.sessionBinding?.sessionRef, sessionB);
      expect(sync.locallySignedOut('client'), isFalse);
    });
  }

  test('late Web CSRF A cannot overwrite authenticated B write token', () async {
    final webConfig = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: config.instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final csrfAReached = Completer<void>();
    final csrfA = Completer<ResponseBody>();
    var csrfCalls = 0;
    var loginCount = 0;
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
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
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          loginCount++;
          final value =
              jsonDecode(jsonEncode(samples['auth_web_authenticated'])) as Map<String, dynamic>;
          (value['data'] as Map<String, dynamic>)['session_ref'] =
              '018f1234-0000-7000-8000-000000000003';
          return jsonBody(value);
        case '/api/v1/me/access':
          final value = jsonDecode(
            jsonEncode(samples['auth_client_access_login_only']),
          ) as Map<String, dynamic>;
          if (loginCount > 0) {
            (value['data'] as Map<String, dynamic>)['session_ref'] =
                '018f1234-0000-7000-8000-000000000003';
          }
          return jsonBody(value);
        case '/api/v1/auth/csrf':
          csrfCalls++;
          if (csrfCalls == 1) {
            csrfAReached.complete();
            return csrfA.future;
          }
          return jsonBody({
            'data': {'csrf_token': csrfB, 'session_ref': sessionB},
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected test path');
    });
    final api = ApiClient(webConfig, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, webConfig),
      webConfig,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    final restoringA = controller.start();
    await csrfAReached.future;
    expect(controller.isAuthenticated, isFalse);
    expect(await controller.login('b@example.test', 'valid-test-password'), isTrue);
    csrfA.complete(
      jsonBody({
        'data': {'csrf_token': csrfTest, 'session_ref': sessionA},
        'meta': {'request_id': requestId},
      }),
    );
    await restoringA;
    expect(controller.access?.sessionRef, '018f1234-0000-7000-8000-000000000003');
    await controller.authorizedWrite((headers) async {
      expect(headers['X-CSRF-Token'], csrfB);
    });
  });

  test('Web restore rejects CSRF from a different cookie session', () async {
    final webConfig = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: config.instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
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
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return jsonBody(samples['auth_client_access_login_only'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {'csrf_token': csrfB, 'session_ref': sessionB},
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(webConfig, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, webConfig),
      webConfig,
      vault: _MemoryVault(),
      sync: _NoSync(),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await controller.start();
    expect(controller.isAuthenticated, isFalse);
    expect(controller.phase, AuthPhase.anonymous);
  });

  test('successful recovery rechecks and drops an invalidated old session', () async {
    final webConfig = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: config.instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    var accessCalls = 0;
    final sync = _NoSync();
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          return jsonBody(samples['auth_web_authenticated'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {'csrf_token': csrfTest, 'session_ref': sessionA},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          accessCalls++;
          if (accessCalls == 2) {
            return jsonBody({
              'error': {'code': 'SESSION_REVOKED', 'message': 'revoked', 'retryable': false},
              'meta': {'request_id': requestId},
            }, 401);
          }
          return jsonBody(samples['auth_client_access_login_only'] as Object);
        case '/api/v1/auth/recovery/complete':
          return ResponseBody.fromString('', 204);
      }
      throw StateError('Unexpected path');
    });
    final api = ApiClient(webConfig, adapter: adapter);
    final controller = AuthController(
      AuthRepository(api, webConfig),
      webConfig,
      vault: _MemoryVault(),
      sync: sync,
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    expect(await controller.login('user@example.test', 'valid-test-password'), isTrue);
    await controller.completeRecovery('A' * 43, 'new-valid-password');
    expect(controller.isAuthenticated, isFalse);
    expect(sync.locallySignedOut('client'), isTrue);
  });

  test('failed Web logout persists a local stop marker across controller reload', () async {
    final webConfig = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: config.instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final sync = _NoSync();
    var accessCalls = 0;
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
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
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          return jsonBody(samples['auth_web_authenticated'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {'csrf_token': csrfTest, 'session_ref': sessionA},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          accessCalls++;
          return jsonBody(samples['auth_client_access_login_only'] as Object);
        case '/api/v1/auth/logout':
          return jsonBody({
            'error': {'code': 'SERVICE_UNAVAILABLE', 'message': 'safe', 'retryable': true},
            'meta': {'request_id': requestId},
          }, 503);
      }
      throw StateError('Unexpected test path');
    });
    final api = ApiClient(webConfig, adapter: adapter);
    final first = AuthController(
      AuthRepository(api, webConfig),
      webConfig,
      vault: _MemoryVault(),
      sync: sync,
    );
    expect(await first.login('a@example.test', 'valid-test-password'), isTrue);
    await expectLater(first.signOut(), throwsA(isA<ApiFailure>()));
    expect(first.isAuthenticated, isFalse);
    expect(sync.locallySignedOut('client'), isTrue);
    first.dispose();
    final second = AuthController(
      AuthRepository(api, webConfig),
      webConfig,
      vault: _MemoryVault(),
      sync: sync,
    );
    addTearDown(() {
      second.dispose();
      api.close();
    });
    await second.start();
    expect(second.phase, AuthPhase.anonymous);
    expect(accessCalls, 2); // login access and logout preflight; no reload access
  });
}

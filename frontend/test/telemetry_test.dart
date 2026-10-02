import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/request_ids.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/telemetry/telemetry.dart';
import 'package:haruka/core/telemetry/telemetry_store.dart';

import 'support/sample_adapter.dart';
import 'support/generated/api_compatibility_samples.dart';

final class _MemoryStore implements TelemetryStore {
  final snapshots = <String, TelemetrySnapshot>{};
  @override
  Future<TelemetrySnapshot?> read(String scope) async => snapshots[scope];
  @override
  Future<void> write(String scope, TelemetrySnapshot snapshot) async => snapshots[scope] = snapshot;
  @override
  Future<void> clear(String scope) async => snapshots.remove(scope);
}

final class _FailReadStore implements TelemetryStore {
  TelemetrySnapshot? snapshot;
  bool failNextRead = true;
  @override
  Future<TelemetrySnapshot?> read(String scope) async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('unavailable');
    }
    return snapshot;
  }

  @override
  Future<void> write(String scope, TelemetrySnapshot value) async => snapshot = value;
  @override
  Future<void> clear(String scope) async => snapshot = null;
}

final class _EmptyVault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

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

void main() {
  test('material events admit only signed-in safe type and result attributes', () async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://localhost:18443',
    );
    final received = <Map<String, dynamic>>[];
    ResponseBody body(Object data) => ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    Object envelope(Object data) => {
      'data': data,
      'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
    };
    final api = ApiClient(
      config,
      adapter: SampleAdapter((request, stream) async {
        switch (request.path) {
          case '/api/v1/meta':
            return body(
              envelope({'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'}),
            );
          case '/api/v1/auth/login':
            return body(samples['auth_web_authenticated'] as Object);
          case '/api/v1/auth/csrf':
            return body(
              envelope({
                'session_ref': '018f1234-0000-7000-8000-000000000002',
                'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              }),
            );
          case '/api/v1/me/access':
            return body(samples['auth_client_access_login_only'] as Object);
          case '/api/v1/auth/logout':
            return ResponseBody.fromString('', 204);
          case '/api/v1/frontend-logs':
            final payload = jsonDecode(
              utf8.decode((await stream!.toList()).expand((part) => part).toList()),
            ) as Map;
            final events = (payload['events'] as List).cast<Map<String, dynamic>>();
            received.addAll(events);
            return body(
              envelope({
                'results': [
                  for (var i = 0; i < events.length; i++)
                    {'index': i, 'event_id': events[i]['event_id'], 'status': 'accepted'},
                ],
              }),
            );
        }
        throw StateError('Unexpected synthetic endpoint');
      }),
    );
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    expect(await auth.login('fixture@example.test', 'synthetic-password'), isTrue);
    final telemetry = Telemetry(config, api, auth, store: _MemoryStore());
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    const events = ['material.import.submitted', 'material.metadata.updated', 'material.deleted'];
    const types = ['novel', 'textbook', 'exam'];
    for (var i = 0; i < events.length; i++) {
      telemetry.track(events[i], attributes: {'material_type': types[i], 'result': 'success'});
      telemetry.track(
        events[i],
        attributes: {
          'material_type': types[i],
          'result': 'success',
          'title': 'private synthetic title',
        },
      );
      telemetry.track(events[i], attributes: {'material_type': 'other', 'result': 'success'});
    }
    await telemetry.flush();
    final materialEvents = received.where((e) => events.contains(e['event'])).toList();
    expect(materialEvents, hasLength(3));
    for (var i = 0; i < events.length; i++) {
      expect(materialEvents[i]['event'], events[i]);
      expect(materialEvents[i]['attributes'], {'material_type': types[i], 'result': 'success'});
    }
    await auth.logout();
    for (final event in events) {
      telemetry.track(event, attributes: {'material_type': 'novel', 'result': 'success'});
    }
    await telemetry.flush();
    expect(received.where((e) => events.contains(e['event'])), hasLength(3));
    expect(telemetry.queuedCount, 0);
  });
  test('authenticated log uploads drain without generating access requests or more logs', () async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    var accessCalls = 0;
    var uploads = 0;
    var uploadedEvents = 0;
    ResponseBody jsonBody(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final api = ApiClient(
      config,
      adapter: SampleAdapter((options, stream) async {
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
              'data': {
                'session_ref': '018f1234-0000-7000-8000-000000000002',
                'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              },
              'meta': {'request_id': requestId},
            });
          case '/api/v1/me/access':
            accessCalls++;
            return jsonBody(samples['auth_client_access_login_only'] as Object);
          case '/api/v1/frontend-logs':
            uploads++;
            expect(options.headers['X-CSRF-Token'], 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
            expect(options.headers['X-Operation-ID'], isNotEmpty);
            final body = jsonDecode(
              utf8.decode((await stream!.toList()).expand((part) => part).toList()),
            ) as Map<String, dynamic>;
            final events = (body['events'] as List<dynamic>).cast<Map<String, dynamic>>();
            uploadedEvents += events.length;
            return jsonBody({
              'data': {
                'results': [
                  for (var index = 0; index < events.length; index++)
                    {'index': index, 'event_id': events[index]['event_id'], 'status': 'accepted'},
                ],
              },
              'meta': {'request_id': requestId},
            });
        }
        throw StateError('Unexpected endpoint ${options.path}');
      }),
    );
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    expect(await auth.login('user@example.test', 'valid-test-password'), isTrue);
    final telemetry = Telemetry(config, api, auth, store: _MemoryStore());
    final writeAccessObserved = Completer<void>();
    api.beginRequestObservation = (operationId, clientRequestId) {
      final observe = telemetry.beginHttpObservation(operationId, clientRequestId);
      return (success, statusCode, elapsed, serverRequestId) {
        observe?.call(success, statusCode, elapsed, serverRequestId);
        if (accessCalls == 2 && !writeAccessObserved.isCompleted) {
          writeAccessObserved.complete();
        }
      };
    };
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    // More than one batch exercises the immediate drain path with observation
    // wired exactly as in the application, rather than hiding transport logs.
    for (var index = 0; index < 45; index++) {
      telemetry.log('http.completed', attributes: {'status_code': 200});
    }
    await telemetry.flush();
    for (var index = 0; index < 100 && telemetry.queuedCount != 0; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(telemetry.queuedCount, 0);
    expect(uploads, 3);
    expect(accessCalls, 1); // Login only; delivery is not an access mutation.
    await telemetry.flush();
    expect(uploads, 3);
    // Ordinary writes must retain their existing post-success access validation.
    await auth.authorizedWrite((headers) async => true);
    await writeAccessObserved.future.timeout(const Duration(seconds: 10));
    // A browser timer may already deliver the access event before a queue
    // snapshot. Explicitly drain and inspect the accepted events instead.
    await telemetry.flush();
    expect(accessCalls, 2);
    expect(uploadedEvents, greaterThan(45));
    expect(telemetry.queuedCount, 0);
  });

  test('restored authenticated queue reports storage recovery without claiming a drop', () async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    ResponseBody jsonBody(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
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
            'data': {
              'session_ref': '018f1234-0000-7000-8000-000000000002',
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return jsonBody(samples['auth_client_access_login_only'] as Object);
      }
      throw StateError('Unexpected endpoint ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    expect(await auth.login('user@example.test', 'valid-test-password'), isTrue);
    final store = _FailReadStore();
    final telemetry = Telemetry(config, api, auth, store: store);
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    await Future<void>.delayed(Duration.zero);
    telemetry.track('access.snapshot.updated', attributes: {'result': 'success'});
    for (
      var attempt = 0;
      attempt < 30 &&
          !(store.snapshot?.events.any(
                (event) => event['event'] == 'telemetry.delivery.recovered',
              ) ??
              false);
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final recovered = store.snapshot!.events.singleWhere(
      (event) => event['event'] == 'telemetry.delivery.recovered',
    );
    expect((recovered['attributes'] as Map<String, Object?>)['dropped_count'], 0);
    expect((recovered['attributes'] as Map<String, Object?>)['drop_reason'], 'storage_unavailable');
  });

  test('resident crash events and pending burst share the byte budget', () async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    ResponseBody jsonBody(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
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
            'data': {
              'session_ref': '018f1234-0000-7000-8000-000000000002',
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return jsonBody(samples['auth_client_access_login_only'] as Object);
      }
      throw StateError('No telemetry receiver in bounded queue test');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    expect(await auth.login('user@example.test', 'valid-test-password'), isTrue);
    final access = auth.access!;
    final scope = [
      config.instanceId,
      access.userId,
      access.audience,
      access.sessionRef,
      access.authzVersion.user,
      access.authzVersion.policy,
    ].join(':');
    final frames = List<String>.filled(20, '${'A' * 64}:12345678:12345678');
    Map<String, Object?> crash() => {
      'schema_version': 1,
      'event_id': newRequestId(),
      'record_type': 'crash',
      'event': 'app.crash.capture',
      'level': 'error',
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'client_platform': 'web',
      'release': '0.1.0',
      'build': '1',
      'operation_id': requestId,
      'request_id': requestId,
      'client_request_id': requestId,
      'safe_stack_frames': frames,
      'attributes': {'error_category': 'other'},
    };
    final store = _MemoryStore();
    store.snapshots[scope] = TelemetrySnapshot(
      clientSessionId: requestId,
      events: List.generate(4400, (_) => crash()),
    );
    final telemetry = Telemetry(config, api, auth, store: store);
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    for (var attempt = 0; attempt < 40 && telemetry.queuedCount < 4400; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(telemetry.bufferedBytes, greaterThan(8 * 1024 * 1024));
    for (var index = 0; index < 1000; index++) {
      telemetry.track(
        'app.crash.capture',
        recordType: 'crash',
        level: 'error',
        attributes: {'error_category': 'other'},
        operationId: requestId,
        requestId: requestId,
        clientRequestId: requestId,
        safeFrames: frames,
      );
    }
    expect(telemetry.bufferedBytes, lessThanOrEqualTo(10 * 1024 * 1024));
    expect(telemetry.bufferedCount, lessThan(5000));
  });

  test('burst allocation shares one bounded resident and pending queue', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    final api = ApiClient(config);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final telemetry = Telemetry(config, api, auth, store: _MemoryStore());
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 5100; i++) {
      telemetry.track('app.started');
    }
    expect(telemetry.bufferedCount, lessThanOrEqualTo(5000));
  });

  test('single rejected upload cannot remove a newer event after queue eviction', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    final reached = Completer<void>();
    final finish = Completer<ResponseBody>();
    final adapter = SampleAdapter((options, _) async {
      expect(options.path, '/api/v1/frontend-logs/anonymous');
      if (!reached.isCompleted) reached.complete();
      return finish.future;
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final store = _MemoryStore();
    var current = DateTime.utc(2026, 9, 26);
    final telemetry = Telemetry(config, api, auth, store: store, now: () => current);
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    telemetry.track('app.started');
    final rejected = telemetry.flush();
    await reached.future;
    final firstId = store.snapshots.values.single.events.single['event_id'];
    current = current.add(const Duration(hours: 25));
    telemetry.track('app.started');
    for (
      var attempt = 0;
      attempt < 30 && store.snapshots.values.single.events.single['event_id'] == firstId;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final newId = store.snapshots.values.single.events.single['event_id'];
    expect(newId, isNot(firstId));
    finish.complete(
      ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'PAYLOAD_TOO_LARGE', 'message': 'large', 'field_errors': <Object?>[]},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        413,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await rejected;
    expect(telemetry.queuedCount, 1);
    expect(store.snapshots.values.single.events.single['event_id'], newId);
  });

  test('empty response links server request ID from its header', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    final adapter = SampleAdapter(
      (_, _) async => ResponseBody.fromString(
        '',
        204,
        headers: {
          'X-Request-ID': [requestId],
        },
      ),
    );
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    String? observed;
    api.beginRequestObservation = (_, _) => (success, status, _, serverRequestId) {
      expect(success, isTrue);
      expect(status, 204);
      observed = serverRequestId;
    };
    await api.postEmpty('/api/v1/auth/logout', const <String, Object?>{});
    expect(observed, requestId);
  });

  test('API retry delay is read from a bounded Retry-After response', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    final adapter = SampleAdapter(
      (_, _) async => ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'RATE_LIMITED', 'message': 'retry', 'field_errors': <Object?>[]},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        429,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'Retry-After': ['4'],
        },
      ),
    );
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    await expectLater(
      api.getJson('/api/v1/meta', MetaRead.fromJson),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.retryAfter,
          'retryAfter',
          const Duration(seconds: 4),
        ),
      ),
    );
  });

  for (final outcome in ['success', 'payload', 'invalid', 'timeout']) {
    test('late account A telemetry $outcome cannot alter account B queue', () async {
      final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
      final config = AppConfig.parse(
        platform: AppPlatform.web,
        environment: 'dev',
        instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
        apiBaseUrl: 'https://localhost:18443',
      );
      const sessionA = '018f1234-0000-7000-8000-000000000002';
      const sessionB = '018f1234-0000-7000-8000-000000000003';
      const requestId = '018f1234-1234-7123-8123-123456789abc';
      final logReached = Completer<void>();
      final finishLog = Completer<ResponseBody>();
      var loginCount = 0;
      ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
        jsonEncode(value),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
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
          (value['data'] as Map<String, dynamic>)['session_ref'] = loginCount == 1
              ? sessionA
              : sessionB;
          return jsonBody(value);
        }
        if (options.path == '/api/v1/me/access') {
          final value = jsonDecode(
            jsonEncode(samples['auth_client_access_login_only']),
          ) as Map<String, dynamic>;
          (value['data'] as Map<String, dynamic>)['session_ref'] = loginCount == 1
              ? sessionA
              : sessionB;
          (value['data'] as Map<String, dynamic>)['user_id'] = loginCount == 1
              ? '018f1234-0000-7000-8000-000000000003'
              : '018f1234-0000-7000-8000-000000000004';
          return jsonBody(value);
        }
        if (options.path == '/api/v1/auth/csrf') {
          return jsonBody({
            'data': {
              'session_ref': loginCount == 1 ? sessionA : sessionB,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        }
        if (options.path == '/api/v1/frontend-logs') {
          if (!logReached.isCompleted) logReached.complete();
          return finishLog.future;
        }
        throw StateError('Unexpected path ${options.path}');
      });
      final api = ApiClient(config, adapter: adapter);
      final auth = AuthController(
        AuthRepository(api, config),
        config,
        vault: _EmptyVault(),
        sync: _NoSync(),
      );
      final store = _MemoryStore();
      final telemetry = Telemetry(config, api, auth, store: store);
      addTearDown(() async {
        await telemetry.dispose();
        auth.dispose();
        api.close();
      });
      expect(await auth.login('a@example.test', 'valid-test-password'), isTrue);
      telemetry.track('http.completed', attributes: {'status_code': 200});
      final oldFlush = telemetry.flush();
      await logReached.future;
      expect(await auth.login('b@example.test', 'valid-test-password'), isTrue);
      telemetry.track('http.completed', attributes: {'status_code': 201});
      await Future<void>.delayed(Duration.zero);
      final before = telemetry.queuedCount;
      expect(before, greaterThanOrEqualTo(1));
      if (outcome == 'timeout') {
        finishLog.completeError(StateError('timeout'));
      } else if (outcome == 'success') {
        finishLog.complete(
          jsonBody({
            'data': {'results': <Object?>[]},
            'meta': {'request_id': requestId},
          }),
        );
      } else {
        finishLog.complete(
          jsonBody({
            'error': {
              'code': outcome == 'payload' ? 'PAYLOAD_TOO_LARGE' : 'INPUT_INVALID',
              'message': 'rejected',
              'field_errors': <Object?>[],
            },
            'meta': {'request_id': requestId},
          }, outcome == 'payload' ? 413 : 422),
        );
      }
      await oldFlush;
      expect(telemetry.queuedCount, before);
      expect(
        store.snapshots.values
            .expand((snapshot) => snapshot.events)
            .any((event) => (event['attributes'] as Map<String, dynamic>?)?['status_code'] == 201),
        isTrue,
      );
      expect(
        store.snapshots.values
            .expand((snapshot) => snapshot.events)
            .any((event) => event['event'] == 'telemetry.delivery.recovered'),
        isFalse,
      );
      if (outcome == 'success') {
        await auth.logout();
        telemetry.track('app.started');
        await Future<void>.delayed(Duration.zero);
        expect(store.snapshots.keys.any((scope) => scope.contains(':anonymous:')), isTrue);
      }
    });
  }

  test('crash frames retain only bounded symbols and line numbers', () {
    final frames = safeStackFrames(
      StackTrace.fromString(
        '#0 PasswordFlow.submit (file:///C:/Users/private/mail/token.dart:42:7)\n'
        '#1 main.<anonymous closure> (https://secret.example/path.dart:9:3)\n'
        '#2 noLocation (hidden)',
      ),
    );
    expect(frames, ['PasswordFlow.submit:42:7', 'main._anonymous_closure_:9:3']);
    expect(frames.join(), isNot(contains('secret')));
  });

  test('telemetry sends only whitelisted anonymous events and retries the same event ID', () async {
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    final ids = <String>[];
    var attempts = 0;
    final adapter = SampleAdapter((options, requestStream) async {
      expect(options.path, '/api/v1/frontend-logs/anonymous');
      final chunks = await requestStream!.toList();
      final body =
          jsonDecode(utf8.decode(chunks.expand((part) => part).toList())) as Map<String, dynamic>;
      final events = body['events'] as List<dynamic>;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['event'], 'app.started');
      expect(event, isNot(contains('message')));
      ids.add(event['event_id'] as String);
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'results': [
              {'index': 0, 'event_id': ids.last, 'status': 'accepted'},
            ],
          },
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final store = _MemoryStore();
    final telemetry = Telemetry(config, api, auth, store: store);
    addTearDown(() async {
      await telemetry.dispose();
      auth.dispose();
      api.close();
    });
    telemetry.track('collection.saved', attributes: {'card_type': 'word'});
    telemetry.track('app.started', attributes: {'email': 'private@example.test'});
    telemetry.track('app.started');
    await telemetry.flush();
    expect(telemetry.queuedCount, 1);
    // The retry timer is internal; waiting only as long as the bounded first backoff.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    await telemetry.flush();
    expect(ids, hasLength(2));
    expect(ids.first, ids.last);
    expect(telemetry.queuedCount, 0);
  });
}

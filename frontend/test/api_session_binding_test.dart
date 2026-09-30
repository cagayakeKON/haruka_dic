import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/cache/cache_read_retry.dart';

import '../test_support/sample_adapter.dart';

const _userA = '018f1234-0000-7000-8000-000000000001';
const _userB = '018f1234-0000-7000-8000-000000000002';
const _sessionA = '018f1234-0000-7000-8000-000000000011';
const _sessionB = '018f1234-0000-7000-8000-000000000022';
const _requestId = '018f1234-1234-7123-8123-123456789abc';

final _config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');

AccessRead _access(String user, String session) => AccessRead(
  userId: user,
  instanceId: _config.instanceId,
  audience: 'client',
  sessionRef: session,
  permissions: const [],
  authzVersion: const AuthorizationVersion(user: 1, policy: 1),
  navigation: const [],
  featureFlags: const [],
);

ResponseBody _jsonResponse(int status, {required Object body, String? instance, String? session}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (instance != null) 'X-Haruka-Instance-ID': [instance],
        if (session != null) 'X-Haruka-Session-Ref': [session],
      },
    );

Object _success(Object value) => {
  'data': value,
  'meta': {'request_id': _requestId},
};

void main() {
  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
    DioExceptionType.badCertificate,
    DioExceptionType.unknown,
  ]) {
    test('transport $type keeps an explicit retry classification after API wrapping', () async {
      final api = ApiClient(
        _config,
        adapter: SampleAdapter((options, _) async {
          throw DioException(requestOptions: options, type: type);
        }),
      );
      addTearDown(api.close);
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      try {
        await api.getJson('/api/v1/users/me/account', (value) => value);
        fail('Expected transport failure');
      } on ApiFailure catch (error) {
        expect(error.code, 'NETWORK_UNAVAILABLE');
        final retry = type != DioExceptionType.badCertificate && type != DioExceptionType.unknown;
        expect(error.retryableTransport, retry);
        expect(cacheReadRetryDelay(error, 0) != null, retry);
        expect(cacheReadRetryDelay(error, 2), isNull);
      }
    });
  }
  for (final status in [200, 204, 403]) {
    test('compatibility mode rejects a late $status response after switching accounts', () async {
      final pending = Completer<ResponseBody>();
      final started = Completer<void>();
      final api = ApiClient(
        _config,
        adapter: SampleAdapter((options, _) {
          started.complete();
          return pending.future;
        }),
      );
      addTearDown(api.close);
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      final request = api.getJson('/api/v1/users/me/account', (value) => value);
      final rejected = expectLater(
        request,
        throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'SESSION_INVALID')),
      );
      await started.future;
      api.bindConfirmedAccess(_access(_userB, _sessionB));
      pending.complete(_jsonResponse(status, body: _success({'private': 'old account'})));
      await rejected;
    });
  }
  test('private requests fail closed before transport while bootstrap remains available', () async {
    final adapter = SampleAdapter((options, _) async {
      expect(
        options.headers.keys.any((key) => key.toLowerCase() == 'x-haruka-expected-session'),
        false,
      );
      return _jsonResponse(200, body: _success({'ok': true}));
    });
    final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
    addTearDown(api.close);

    await expectLater(
      api.getJson('/api/v1/users/me/account', (value) => value),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'AUTH_SCOPE_REQUIRED')),
    );
    expect(adapter.calls, 0);
    expect((await api.getJson('/api/v1/me/access', (value) => value)).data, {'ok': true});
    expect(adapter.calls, 1);
    expect(
      (await api.postJson(
        '/api/v1/auth/recovery/manual',
        const {'email': 'person@example.test'},
        (value) => value,
        expectedStatus: 200,
      )).data,
      {'ok': true},
    );
    expect(adapter.calls, 2);
    await expectLater(
      api.postJson('/api/v1/me/access', const {}, (value) => value),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'AUTH_SCOPE_REQUIRED')),
    );
    expect(adapter.calls, 2);
  });

  test('strict private JSON, 204 and binary calls use the confirmed session', () async {
    final adapter = SampleAdapter((options, _) async {
      expect(options.headers['X-Haruka-Expected-Session'], _sessionA);
      if (options.path.endsWith('/empty')) {
        return ResponseBody.fromString(
          '',
          204,
          headers: {
            'X-Haruka-Instance-ID': [_config.instanceId],
            'X-Haruka-Session-Ref': [_sessionA],
          },
        );
      }
      if (options.path.endsWith('/binary')) {
        return ResponseBody.fromBytes(
          [1, 2, 3],
          200,
          headers: {
            'X-Haruka-Instance-ID': [_config.instanceId],
            'X-Haruka-Session-Ref': [_sessionA],
          },
        );
      }
      expect(options.responseType, ResponseType.bytes);
      return _jsonResponse(
        200,
        body: _success({'owner': 'A'}),
        instance: _config.instanceId,
        session: _sessionA,
      );
    });
    final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
    addTearDown(api.close);
    final first = api.bindConfirmedAccess(_access(_userA, _sessionA));
    expect(api.bindConfirmedAccess(_access(_userA, _sessionA)).generation, first.generation);

    final result = await api.getJson(
      '/api/v1/private',
      (value) => (value as Map<String, dynamic>)['owner'] as String,
      headers: const {'x-haruka-expected-session': 'untrusted-caller'},
    );
    expect(result.data, 'A');
    await api.postEmpty('/api/v1/private/empty', const {});
    expect(await api.download('/api/v1/private/binary'), Uint8List.fromList([1, 2, 3]));
    expect(adapter.calls, 3);
  });

  test('missing response binding blocks DTO decode and closes current binding', () async {
    final adapter = SampleAdapter(
      (_, _) async => _jsonResponse(200, body: _success({'owner': 'A'})),
    );
    final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
    addTearDown(api.close);
    api.bindConfirmedAccess(_access(_userA, _sessionA));
    var decoded = false;
    var lost = 0;
    api.onSessionBindingLost = () => lost++;

    await expectLater(
      api.getJson('/api/v1/private', (value) {
        decoded = true;
        return value;
      }),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'AUTH_SCOPE_CHANGED')),
    );
    expect(decoded, false);
    expect(lost, 1);
    expect(api.sessionBinding, isNull);
    await expectLater(
      api.getJson('/api/v1/private', (value) => value),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'AUTH_SCOPE_REQUIRED')),
    );
    expect(adapter.calls, 1);
  });

  test('old response after an account switch cannot replace the new binding', () async {
    final started = Completer<void>();
    final heldResponse = Completer<ResponseBody>();
    final adapter = SampleAdapter((options, _) {
      started.complete();
      return heldResponse.future;
    });
    final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
    addTearDown(api.close);
    api.bindConfirmedAccess(_access(_userA, _sessionA));
    var lost = 0;
    var decoded = false;
    api.onSessionBindingLost = () => lost++;
    final oldRequest = api.getJson('/api/v1/private', (value) {
      decoded = true;
      return value;
    });
    await started.future;
    api.bindConfirmedAccess(_access(_userB, _sessionB));
    final assertion = expectLater(
      oldRequest,
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'SESSION_INVALID')),
    );
    heldResponse.complete(
      _jsonResponse(
        200,
        body: _success({'owner': 'A'}),
        instance: _config.instanceId,
        session: _sessionA,
      ),
    );
    await assertion;
    expect(decoded, false);
    expect(lost, 0);
    expect(api.sessionBinding!.userId, _userB);
    expect(api.sessionBinding!.sessionRef, _sessionB);
  });

  test('an account switch inside DTO decode cannot publish the old result', () async {
    for (final path in ['/json', '/page', '/post', '/patch']) {
      final adapter = SampleAdapter(
        (_, _) async => _jsonResponse(
          200,
          body: path == '/page'
              ? {
                  'data': [
                    {'owner': 'A'},
                  ],
                  'meta': {'request_id': _requestId, 'has_more': false, 'next_cursor': null},
                }
              : _success({'owner': 'A'}),
          instance: _config.instanceId,
          session: _sessionA,
        ),
      );
      final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
      addTearDown(api.close);
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      var decoded = 0;
      Object? decode(Object? value) {
        decoded++;
        api.bindConfirmedAccess(_access(_userB, _sessionB));
        return value;
      }

      Future<Object?> request() => switch (path) {
        '/json' => api.getJson('/api/v1/private', decode),
        '/page' => api.getPage('/api/v1/private', decode),
        '/post' => api.postJson('/api/v1/private', const {}, decode),
        _ => api.patchJson('/api/v1/private', const {}, decode),
      };
      await expectLater(
        request(),
        throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'SESSION_INVALID')),
        reason: path,
      );
      expect(decoded, 1, reason: path);
      expect(api.sessionBinding!.userId, _userB, reason: path);
    }
  });

  test('error response binding is checked before parsing even a malformed body', () async {
    for (final (status, instance, session) in [
      (401, _config.instanceId, _sessionB),
      (403, 'wrong-instance', _sessionA),
      (409, _config.instanceId, _sessionB),
    ]) {
      final adapter = SampleAdapter(
        (_, _) async => ResponseBody.fromString(
          '<html>private body</html>',
          status,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
            'X-Haruka-Instance-ID': [instance],
            'X-Haruka-Session-Ref': [session],
          },
        ),
      );
      final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
      addTearDown(api.close);
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      var lost = 0;
      var decoded = false;
      api.onSessionBindingLost = () => lost++;
      await expectLater(
        api.getJson('/api/v1/private', (value) {
          decoded = true;
          return value;
        }),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.code, 'code', 'AUTH_SCOPE_CHANGED')
              .having((error) => error.statusCode, 'HTTP status', status),
        ),
        reason: '$status',
      );
      expect(decoded, false);
      expect(lost, 1);
      expect(api.sessionBinding, isNull);
    }
  });

  test('an old error response cannot close a newly confirmed account', () async {
    final started = Completer<void>();
    final heldResponse = Completer<ResponseBody>();
    final adapter = SampleAdapter((_, _) {
      started.complete();
      return heldResponse.future;
    });
    final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
    addTearDown(api.close);
    api.bindConfirmedAccess(_access(_userA, _sessionA));
    var lost = 0;
    api.onSessionBindingLost = () => lost++;
    final oldRequest = api.getJson('/api/v1/private', (value) => value);
    await started.future;
    api.bindConfirmedAccess(_access(_userB, _sessionB));
    final assertion = expectLater(
      oldRequest,
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'SESSION_INVALID')),
    );
    heldResponse.complete(
      _jsonResponse(
        409,
        body: {
          'error': {'code': 'AUTH_SCOPE_CHANGED'},
          'meta': {'request_id': _requestId},
        },
        instance: _config.instanceId,
        session: _sessionA,
      ),
    );
    await assertion;
    expect(lost, 0);
    expect(api.sessionBinding!.userId, _userB);
  });

  test(
    'server scope conflict closes binding but 401 without headers retains auth handling',
    () async {
      var status = 409;
      final adapter = SampleAdapter(
        (_, _) async => _jsonResponse(
          status,
          body: status == 409
              ? {
                  'error': {'code': 'AUTH_SCOPE_CHANGED'},
                  'meta': {'request_id': _requestId},
                }
              : {
                  'error': {'code': 'ACCESS_EXPIRED'},
                  'meta': {'request_id': _requestId},
                },
          instance: status == 409 ? _config.instanceId : null,
          session: status == 409 ? _sessionA : null,
        ),
      );
      final api = ApiClient(_config, adapter: adapter, requireSessionBinding: true);
      addTearDown(api.close);
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      var lost = 0;
      api.onSessionBindingLost = () => lost++;
      await expectLater(
        api.getJson('/api/v1/private', (value) => value),
        throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'AUTH_SCOPE_CHANGED')),
      );
      expect(lost, 1);
      expect(api.sessionBinding, isNull);

      status = 401;
      api.bindConfirmedAccess(_access(_userA, _sessionA));
      await expectLater(
        api.getJson('/api/v1/private', (value) => value),
        throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'ACCESS_EXPIRED')),
      );
      expect(api.sessionBinding, isNotNull);
      expect(lost, 1);
    },
  );
}

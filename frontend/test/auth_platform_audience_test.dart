import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/collections/reference_controller.dart';

import 'support/generated/api_compatibility_samples.dart';
import 'support/sample_adapter.dart';

final _samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, Object?>;
const _request = '018f1234-1234-7123-8123-123456789abc';
ResponseBody _body(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

final class _Vault implements CredentialVault {
  RefreshCredential? value;
  @override
  Future<RefreshCredential?> read() async => value;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    if (prior == null ? value != null : value == null || !prior.sameVersion(value!)) return false;
    value = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async {
    if (sessionRef == null || value?.sessionRef == sessionRef) value = null;
  }
}

final class _Sync implements AuthSync {
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
  for (final platform in [AppPlatform.android, AppPlatform.windows]) {
    test(
      '${platform.name} rejects administrative audience without touching the current client session',
      () async {
        final config = AppConfig.parse(
          platform: platform,
          environment: 'dev',
          flavor: 'dev',
          instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
          apiBaseUrl: platform == AppPlatform.android
              ? 'http://10.0.2.2:18081'
              : 'http://127.0.0.1:18081',
        );
        final adapter = SampleAdapter((request, _) async {
          switch (request.uri.path) {
            case '/api/v1/meta':
              return _body({
                'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
                'meta': {'request_id': _request},
              });
            case '/api/v1/auth/native/login':
              return _body(_samples['auth_native_authenticated'] as Object);
            case '/api/v1/me/access':
              return _body(_samples['auth_client_access_login_only'] as Object);
          }
          fail('An administrative request must never reach transport on a native client');
        });
        final api = ApiClient(config, adapter: adapter);
        final auth = AuthController(
          AuthRepository(api, config),
          config,
          vault: _Vault(),
          sync: _Sync(),
        );
        addTearDown(() {
          auth.dispose();
          api.close();
        });
        expect(await auth.login('fixture@example.test', 'fixture-password'), isTrue);
        final beforeCalls = adapter.calls;
        final beforeAccess = auth.access;
        final beforePhase = auth.phase;
        final beforeScope = referenceScope(auth, 'audience-boundary');
        expect(auth.admin, isFalse);
        expect(auth.isAuthenticated, isTrue);
        await expectLater(
          auth.login('fixture-admin@example.test', 'fixture-password', admin: true),
          throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'PERMISSION_DENIED')),
        );
        expect(
          adapter.calls,
          beforeCalls,
          reason: 'The forbidden audience is rejected before any transport',
        );
        expect(auth.access, same(beforeAccess));
        expect(auth.phase, beforePhase);
        expect(referenceScope(auth, 'audience-boundary'), beforeScope);
        expect(auth.admin, isFalse);
        expect(auth.isAuthenticated, isTrue);
      },
    );
  }
}

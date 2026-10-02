import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/features/collections/reference_repository.dart';

import 'support/generated/api_compatibility_samples.dart';
import 'support/sample_adapter.dart';

final _samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, Object?>;
const _request = '018f1234-1234-7123-8123-123456789abc';
const _first = '018f1234-0000-7000-8000-000000000010';
const _second = '018f1234-0000-7000-8000-000000000011';
const _replacement = '018f1234-0000-7000-8000-000000000012';
final _config = AppConfig.parse(
  platform: AppPlatform.windows,
  environment: 'dev',
  instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
  apiBaseUrl: 'http://127.0.0.1:18081',
);

ResponseBody _body(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
Map<String, Object?> _row(String id) => {
  ...((_samples['learning_collection'] as Map<String, Object?>)['data'] as Map<String, Object?>),
  'id': id,
};
ResponseBody _page(List<String> ids, {String? cursor}) => _body({
  'data': ids.map(_row).toList(),
  'meta': {'request_id': _request, 'next_cursor': cursor, 'has_more': cursor != null},
});

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

final class _Fixture {
  _Fixture();
  int permissionVersion = 1;
  int pageReads = 0;
  final reached = Completer<void>();
  final pending = Completer<ResponseBody>();
  late final ApiClient api = ApiClient(
    _config,
    adapter: SampleAdapter((request, _) async {
      switch (request.uri.path) {
        case '/api/v1/meta':
          return _body({
            'data': {'instance_id': _config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': _request},
          });
        case '/api/v1/auth/native/login':
          return _body(_samples['auth_native_authenticated'] as Object);
        case '/api/v1/me/access':
          final envelope = jsonDecode(
            jsonEncode(_samples['auth_client_access_login_only']),
          ) as Map<String, Object?>;
          final data = envelope['data'] as Map<String, Object?>;
          data['permissions'] = [
            {'code': 'client.login', 'data_scope': 'self'},
            {'code': 'client.collection.read', 'data_scope': 'self'},
          ];
          data['authz_version'] = {'user': permissionVersion, 'policy': 3};
          return _body(envelope);
        case '/api/v1/collections':
          expect(request.headers['Authorization'], startsWith('Bearer '));
          expect(request.headers['X-Operation-ID'], isNotEmpty);
          expect(request.uri.queryParameters['limit'], '20');
          pageReads++;
          if (pageReads == 1) {
            expect(request.uri.queryParameters.containsKey('cursor'), isFalse);
            return _page([_first], cursor: 'opaque/cursor + 1');
          }
          if (pageReads == 2) {
            expect(request.uri.queryParameters['cursor'], 'opaque/cursor + 1');
            reached.complete();
            return pending.future;
          }
          expect(request.uri.queryParameters.containsKey('cursor'), isFalse);
          return _page([_replacement]);
      }
      throw StateError('Unexpected fixture endpoint');
    }),
  );
  late final AuthController auth = AuthController(
    AuthRepository(api, _config),
    _config,
    vault: _Vault(),
    sync: _Sync(),
  );
  late final ReferenceController controller = ReferenceController(auth, ReferenceRepository(api));
  Future<void> initialize() async {
    addTearDown(() {
      controller.dispose();
      auth.dispose();
      api.close();
    });
    expect(await auth.login('fixture@example.test', 'fixture-password'), isTrue);
    expect(auth.access!.allows('client.collection.read'), isTrue);
    expect(controller.canListCollections, isTrue);
    await controller.loadCollections();
    expect(controller.collections.map((row) => row.id), [_first]);
  }
}

void main() {
  test(
    'pending more ignores first reload, then explicit first reload replaces prior pages',
    () async {
      final fixture = _Fixture();
      await fixture.initialize();
      final more = fixture.controller.loadCollections(more: true);
      await fixture.reached.future;
      await fixture.controller.loadCollections();
      expect(
        fixture.pageReads,
        2,
        reason: 'A first-page reload is not queued behind pending pagination',
      );
      expect(fixture.controller.collections.map((row) => row.id), [_first]);
      fixture.pending.complete(_page([_first, _second]));
      await more;
      expect(fixture.controller.collections.map((row) => row.id), [_first, _second]);
      expect(fixture.controller.collectionCursor, isNull);
      await fixture.controller.loadCollections();
      expect(fixture.pageReads, 3);
      expect(
        fixture.controller.collections.map((row) => row.id),
        [_replacement],
        reason:
            'The explicit authoritative first page replaces old pages rather than appending them',
      );
    },
  );

  test('current permission scope generation discards a late more page', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    final oldScope = referenceScope(fixture.auth, 'reference');
    final more = fixture.controller.loadCollections(more: true);
    await fixture.reached.future;
    fixture.permissionVersion++;
    expect(await fixture.auth.verifyCurrentAccess(), isTrue);
    expect(referenceScope(fixture.auth, 'reference'), isNot(oldScope));
    expect(fixture.auth.access!.allows('client.collection.read'), isTrue);
    expect(fixture.controller.canListCollections, isFalse);
    fixture.pending.complete(_page([_second]));
    await more;
    expect(fixture.controller.collections.map((row) => row.id), [_first]);
    expect(fixture.controller.collectionCursor, 'opaque/cursor + 1');
    await fixture.controller.loadCollections();
    expect(
      fixture.pageReads,
      2,
      reason: 'The prior controller cannot request in the new permission generation',
    );
  });
}

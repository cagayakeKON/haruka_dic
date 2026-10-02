import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/model_settings_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/settings/data/model_configuration_repository.dart';

import 'support/generated/api_compatibility_samples.dart';
import 'support/sample_adapter.dart';

final _samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, Object?>;
const _request = '018f1234-1234-7123-8123-123456789abc';
const _session = '018f1234-0000-7000-8000-000000000002';
final _config = AppConfig.parse(
  platform: AppPlatform.windows,
  environment: 'dev',
  instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
  apiBaseUrl: 'http://127.0.0.1:18081',
);

ResponseBody _response(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
Object _success(Object data) => {
  'data': data,
  'meta': {'request_id': _request},
};
Object? _sampleData(String name) => (_samples[name] as Map<String, Object?>)['data'];
ProviderCredential _credential() => ProviderCredential.fromJson(_sampleData('model_credential'));
ModelJob _job() => ModelJob.fromJson(_sampleData('model_job'));
ModelBinding _binding() => ModelBinding(
  credentialId: _credential().id,
  provider: 'openrouter',
  modelId: 'fixture/model',
  voiceId: 'fixture-voice',
  languageTag: 'ja',
  outputFormat: 'mp3',
);

final class _Vault implements CredentialVault {
  RefreshCredential? value;
  @override
  Future<RefreshCredential?> read() async => value;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    value = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async => value = null;
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

Future<(AuthController, HttpModelConfigurationRepository)> _fixture(
  Future<ResponseBody> Function(RequestOptions) privateRequest,
) async {
  final api = ApiClient(
    _config,
    adapter: SampleAdapter((options, _) async {
      switch (options.uri.path) {
        case '/api/v1/meta':
          return _response(
            _success({'instance_id': _config.instanceId, 'api_version': 'v1', 'release': 'test'}),
          );
        case '/api/v1/auth/native/login':
          return _response(_samples['auth_native_authenticated'] as Object);
        case '/api/v1/auth/policy':
          return _response(
            _success({
              'registration_enabled': true,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': false,
              'recovery_mode': 'disabled',
              'action_link_base_url': 'https://example.test',
              'password_min_length': 15,
              'password_max_length': 128,
            }),
          );
        case '/api/v1/me/access':
          return _response(_samples['auth_client_access_login_only'] as Object);
        case '/api/v1/auth/logout':
          return ResponseBody.fromString('', 204);
      }
      expect(options.headers['Authorization'], startsWith('Bearer '));
      expect(options.headers['X-Operation-ID'], isNotEmpty);
      return privateRequest(options);
    }),
  );
  final auth = AuthController(
    AuthRepository(api, _config),
    _config,
    vault: _Vault(),
    sync: _Sync(),
  );
  addTearDown(() {
    auth.dispose();
    api.close();
  });
  await auth.start();
  expect(auth.phase, AuthPhase.anonymous);
  expect(await auth.login('fixture@example.test', 'fixture-password'), isTrue);
  expect(auth.access?.sessionRef, _session);
  return (auth, HttpModelConfigurationRepository(auth));
}

void main() {
  test(
    'material language confirmation retries the same job with the complete issue fence',
    () async {
      const revisionId = '018f1234-0000-7000-8000-0000000000aa';
      const issueId = '018f1234-0000-7000-8000-0000000000bb';
      final digest = List.filled(64, 'a').join();
      final source = <String, Object?>{
        ...(_sampleData('model_job') as Map).cast<String, Object?>(),
        'operation_kind': 'material_import',
        'run_id': null,
        'credential_id': null,
        'material_id': issueId,
        'material_revision_id': revisionId,
        'source_status': 'parsing',
        'state': 'blocked',
        'revision': 4,
        'generation': 2,
        'language_issue': {
          'id': issueId,
          'revision': 3,
          'input_digest': digest,
          'material_revision_id': revisionId,
          'declared_language': 'ja',
        },
      };
      final requests = <RequestOptions>[];
      final (_, repository) = await _fixture((request) async {
        requests.add(request);
        expect(request.uri.path, '/api/v1/jobs/${_job().id}/retry');
        return _response(
          _success({...source, 'state': 'queued', 'language_issue': null}),
          status: 202,
        );
      });
      final job = ModelJob.fromJson(source);
      final confirmed = await repository.confirmLanguage(job, 'en', issueId);
      expect(confirmed.sourceImport, isTrue);
      expect(confirmed.sourceStatus, 'parsing');
      expect(confirmed.runId, isNull);
      expect(requests.single.headers['Idempotency-Key'], issueId);
      expect(requests.single.method, 'POST');
      expect(requests.single.data, {
        'expected_revision': 4,
        'language_confirmation': {
          'language': 'en',
          'input_digest': digest,
          'expected_job_generation': 2,
          'expected_issue_revision': 3,
        },
      });
      expect(() => repository.result(job), throwsFormatException);
      expect(() => repository.confirmLanguage(job, 'zh', issueId), throwsFormatException);
      expect(() => ModelJob.fromJson({...source, 'run_id': issueId}), throwsFormatException);
      expect(
        () => ModelJob.fromJson({
          ...source,
          'language_issue': {...(source['language_issue'] as Map), 'material_revision_id': issueId},
        }),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );
  test('credential creation and rotation carry only current mutation fields and CAS', () async {
    final mutations = <RequestOptions>[];
    final (_, repository) = await _fixture((request) async {
      mutations.add(request);
      return _response(
        _samples['model_credential'] as Object,
        status: request.method == 'POST' ? 201 : 200,
      );
    });
    final created = await repository.saveCredential('openrouter', 'Fixture', 'synthetic-key');
    expect(created.maskedKey, '****demo');
    expect(mutations.single.data, {
      'provider': 'openrouter',
      'label': 'Fixture',
      'key': 'synthetic-key',
    });
    await repository.saveCredential('openrouter', 'Rotated', 'synthetic-next', previous: created);
    expect(mutations.last.method, 'PATCH');
    expect(mutations.last.uri.path, '/api/v1/provider-credentials/${created.id}');
    expect(mutations.last.data, {
      'expected_revision': created.revision,
      'key': 'synthetic-next',
      'label': 'Rotated',
    });
    expect(mutations, hasLength(2));
  });

  test('binding mutation preserves explicit nulls and server confirmed revision', () async {
    RequestOptions? mutation;
    final (_, repository) = await _fixture((request) async {
      mutation = request;
      return _response(_samples['model_settings'] as Object);
    });
    final result = await repository.saveBindings(7, {
      'text': _binding(),
      'vision': null,
      'tts': null,
    });
    expect(mutation!.method, 'PATCH');
    expect(mutation!.data, {
      'expected_revision': 7,
      'bindings': {'text': _binding().toJson(), 'vision': null, 'tts': null},
    });
    expect(result.revision, 2);
    expect(result.bindings.values, everyElement(isNull));
  });

  test('credential deletion consumes impact metadata then sends the current revision', () async {
    final requests = <RequestOptions>[];
    final (_, repository) = await _fixture((request) async {
      requests.add(request);
      return request.method == 'GET'
          ? _response(
              _success({
                'blocked_jobs': 2,
                'bindings': ['text'],
              }),
            )
          : _response(_samples['model_credential'] as Object);
    });
    final impact = await repository.deletionImpact(_credential());
    expect(impact, {
      'blocked_jobs': 2,
      'bindings': ['text'],
    });
    await repository.deleteCredential(_credential());
    expect(
      requests.first.uri.path,
      '/api/v1/provider-credentials/${_credential().id}/deletion-impact',
    );
    expect(requests.last.method, 'DELETE');
    expect(requests.last.data, {'expected_revision': 1});
    expect(requests, hasLength(2));
  });

  test('malformed accepted attempt cannot become success or trigger a second submission', () async {
    var writes = 0;
    final (_, repository) = await _fixture((request) async {
      writes++;
      return _response(_success({'state': 'queued', 'generation': 1}), status: 202);
    });
    await expectLater(
      repository.test(_credential(), 'text', _binding(), 'malformed-fixture'),
      throwsA(isA<ApiFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, 1);
  });

  test(
    'explicit TTS attempt consumes 202 once with caller idempotency and no private key',
    () async {
      final requests = <RequestOptions>[];
      final (_, repository) = await _fixture((request) async {
        requests.add(request);
        return _response(
          _success({
            'job_id': _job().id,
            'run_id': _job().runId,
            'generation': 1,
            'state': 'queued',
          }),
          status: 202,
        );
      });
      final accepted = await repository.test(_credential(), 'tts', _binding(), 'attempt-fixture');
      expect(accepted.jobId, _job().id);
      expect(accepted.state, 'queued');
      expect(requests, hasLength(1));
      expect(requests.single.headers['Idempotency-Key'], 'attempt-fixture');
      expect(requests.single.data, {
        'expected_revision': 1,
        'capability': 'tts',
        'model_id': 'fixture/model',
        'voice_id': 'fixture-voice',
        'language_tag': 'ja',
        'output_format': 'mp3',
      });
    },
  );

  test('unknown attempt transport outcome never replays POST or borrows credentials', () async {
    var writes = 0;
    final (_, repository) = await _fixture((request) async {
      writes++;
      throw DioException(requestOptions: request, type: DioExceptionType.receiveTimeout);
    });
    await expectLater(
      repository.test(_credential(), 'text', _binding(), 'unknown-fixture'),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'NETWORK_UNAVAILABLE')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, 1);
  });

  test('cancel and confirmed retry serialize independent revision fenced actions', () async {
    final writes = <RequestOptions>[];
    final (_, repository) = await _fixture((request) async {
      writes.add(request);
      return _response(
        _samples['model_job'] as Object,
        status: request.uri.path.endsWith('/retry') ? 202 : 200,
      );
    });
    final cancelled = await repository.cancel(_job());
    expect(cancelled.state, 'blocked');
    expect(writes.single.data, {'expected_revision': 3});
    expect(writes.single.uri.path, '/api/v1/jobs/${_job().id}/cancel');
    final retried = await repository.retry(_job(), true, 'retry-fixture');
    expect(retried.runId, _job().runId);
    expect(writes.last.data, {'expected_revision': 3, 'confirm_new_attempt': true});
    expect(writes.last.headers['Idempotency-Key'], 'retry-fixture');
    expect(writes, hasLength(2));
  });

  test('logout rejects a late safe projection and new private writes before transport', () async {
    final started = Completer<void>();
    final release = Completer<ResponseBody>();
    var calls = 0;
    final (auth, repository) = await _fixture((request) {
      calls++;
      started.complete();
      return release.future;
    });
    final late = repository.credentials();
    final rejection = expectLater(
      late,
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_INVALID')),
    );
    await started.future;
    await auth.logout();
    release.complete(
      _response(
        _success({
          'items': [_sampleData('model_credential')],
        }),
      ),
    );
    await rejection;
    await expectLater(
      repository.cancel(_job()),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'AUTH_REQUIRED')),
    );
    expect(calls, 1);
  });

  test(
    'usage filters are encoded without owner override and results keep unknown outcome',
    () async {
      final reads = <RequestOptions>[];
      final (_, repository) = await _fixture((request) async {
        reads.add(request);
        return _response(
          _samples[request.uri.path.endsWith('/model-usage')
                  ? 'model_usage_unknown'
                  : 'model_test_result']
              as Object,
        );
      });
      await repository.usage({'model_id': 'fixture/model + spaced', 'capability': 'text'});
      expect(reads.single.uri.queryParameters, {
        'model_id': 'fixture/model + spaced',
        'capability': 'text',
      });
      expect(reads.single.method, 'GET');
      final result = await repository.result(_job());
      expect(
        reads.last.uri.path,
        '/api/v1/provider-credentials/${_job().credentialId}/tests/${_job().runId}',
      );
      expect(result.state, 'unknown_outcome');
      expect(result.credentialId, _credential().id);
      expect(reads, hasLength(2));
    },
  );
}

import '../../../core/api/api_client.dart';
import '../../../core/api/model_settings_models.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../features/jobs/data/job_socket.dart';

abstract interface class ModelConfigurationRepository {
  Future<List<ProviderCredential>> credentials();
  Future<ModelDirectory> directory();
  Future<PersonalModelSettings> settings();
  Future<ProviderCredential> saveCredential(
    String provider,
    String label,
    String key, {
    ProviderCredential? previous,
  });
  Future<Map<String, Object?>> deletionImpact(ProviderCredential credential);
  Future<void> deleteCredential(ProviderCredential credential);
  Future<PersonalModelSettings> saveBindings(int revision, Map<String, ModelBinding?> bindings);
  Future<List<ModelJob>> jobs();
  Future<ModelJob> job(String id);
  Future<CredentialTestResult> result(ModelJob job);
  Future<CredentialTestResult> testResult(String credentialId, String runId);
  Future<AcceptedModelTest> test(
    ProviderCredential credential,
    String capability,
    ModelBinding binding,
    String idempotencyKey,
  );
  Future<ModelJob> cancel(ModelJob job);
  Future<ModelJob> retry(ModelJob job, bool confirmNewAttempt, String idempotencyKey);
  Future<ModelUsage> usage(Map<String, String> filters);
  Future<JobSocket> connect();
}

abstract interface class MaterialJobLanguageRepository {
  Future<ModelJob> confirmLanguage(ModelJob job, String language, String idempotencyKey);
}

final class HttpModelConfigurationRepository
    implements ModelConfigurationRepository, MaterialJobLanguageRepository {
  HttpModelConfigurationRepository(this.auth);
  final AuthController auth;
  ApiClient get api => auth.repository.api;
  Future<T> _get<T>(String path, T Function(Object?) decode) => auth.authorizedRead(
    (headers) async => (await api.getJson(path, decode, headers: headers)).data,
  );
  @override
  Future<List<ProviderCredential>> credentials() => _get(
    '/api/v1/provider-credentials',
    (j) => modelList(wireObject(j)['items'], ProviderCredential.fromJson),
  );
  @override
  Future<ModelDirectory> directory() => _get('/api/v1/model-capabilities', ModelDirectory.fromJson);
  @override
  Future<PersonalModelSettings> settings() =>
      _get('/api/v1/users/me/model-settings', PersonalModelSettings.fromJson);
  @override
  Future<ProviderCredential> saveCredential(
    String provider,
    String label,
    String key, {
    ProviderCredential? previous,
  }) => auth.authorizedWrite(
    (headers) async => previous == null
        ? (await api.postJson(
            '/api/v1/provider-credentials',
            {'provider': provider, 'label': label, 'key': key},
            ProviderCredential.fromJson,
            headers: headers,
            acceptedStatuses: {200, 201},
          )).data
        : (await api.patchJson(
            '/api/v1/provider-credentials/${previous.id}',
            {'expected_revision': previous.revision, 'key': key, 'label': label},
            ProviderCredential.fromJson,
            headers: headers,
          )).data,
  );
  @override
  Future<Map<String, Object?>> deletionImpact(ProviderCredential credential) =>
      _get('/api/v1/provider-credentials/${credential.id}/deletion-impact', wireObject);
  @override
  Future<void> deleteCredential(ProviderCredential credential) =>
      auth.authorizedWrite((headers) async {
        await api.deleteJson(
          '/api/v1/provider-credentials/${credential.id}',
          {'expected_revision': credential.revision},
          ProviderCredential.fromJson,
          headers: headers,
        );
      });
  @override
  Future<PersonalModelSettings> saveBindings(int revision, Map<String, ModelBinding?> bindings) =>
      auth.authorizedWrite(
        (headers) async => (await api.patchJson(
          '/api/v1/users/me/model-settings',
          {
            'expected_revision': revision,
            'bindings': bindings.map((k, v) => MapEntry(k, v?.toJson())),
          },
          PersonalModelSettings.fromJson,
          headers: headers,
        )).data,
      );
  @override
  Future<List<ModelJob>> jobs() =>
      _get('/api/v1/jobs', (j) => modelList(wireObject(j)['items'], ModelJob.fromJson));
  @override
  Future<ModelJob> job(String id) => _get('/api/v1/jobs/$id', ModelJob.fromJson);
  @override
  Future<CredentialTestResult> result(ModelJob job) {
    if (job.sourceImport || job.credentialId == null || job.runId == null) {
      throw const FormatException('No model result for source job');
    }
    return testResult(job.credentialId!, job.runId!);
  }

  @override
  Future<CredentialTestResult> testResult(String credentialId, String runId) => _get(
    '/api/v1/provider-credentials/$credentialId/tests/$runId',
    CredentialTestResult.fromJson,
  );
  @override
  Future<AcceptedModelTest> test(
    ProviderCredential credential,
    String capability,
    ModelBinding binding,
    String idempotencyKey,
  ) async {
    return auth.authorizedWrite(
      (headers) async => (await api.postJson(
        '/api/v1/provider-credentials/${credential.id}/test',
        {
          'expected_revision': credential.revision,
          'capability': capability,
          'model_id': binding.modelId,
          'voice_id': capability == 'tts' ? binding.voiceId : null,
          'language_tag': binding.languageTag,
          'output_format': binding.outputFormat,
        },
        AcceptedModelTest.fromJson,
        expectedStatus: 202,
        headers: {...headers, 'Idempotency-Key': idempotencyKey},
      )).data,
    );
  }

  @override
  Future<ModelJob> cancel(ModelJob job) => auth.authorizedWrite(
    (headers) async => (await api.postJson(
      '/api/v1/jobs/${job.id}/cancel',
      {'expected_revision': job.revision},
      ModelJob.fromJson,
      headers: headers,
    )).data,
  );
  @override
  Future<ModelJob> retry(ModelJob job, bool confirmNewAttempt, String idempotencyKey) =>
      auth.authorizedWrite(
        (headers) async => (await api.postJson(
          '/api/v1/jobs/${job.id}/retry',
          {'expected_revision': job.revision, 'confirm_new_attempt': confirmNewAttempt},
          ModelJob.fromJson,
          headers: {...headers, 'Idempotency-Key': idempotencyKey},
          acceptedStatuses: {200, 202},
        )).data,
      );
  @override
  Future<ModelJob> confirmLanguage(ModelJob job, String language, String idempotencyKey) {
    final issue = job.languageIssue;
    if (!job.sourceImport ||
        job.state != 'blocked' ||
        issue == null ||
        !const {'ja', 'en'}.contains(language)) {
      throw const FormatException('No pending language issue');
    }
    return auth.authorizedWrite(
      (headers) async => (await api.postJson(
        '/api/v1/jobs/${job.id}/retry',
        {
          'expected_revision': job.revision,
          'language_confirmation': {
            'language': language,
            'input_digest': issue.inputDigest,
            'expected_job_generation': job.generation,
            'expected_issue_revision': issue.revision,
          },
        },
        ModelJob.fromJson,
        headers: {...headers, 'Idempotency-Key': idempotencyKey},
        acceptedStatuses: {200, 202},
      )).data,
    );
  }

  @override
  Future<ModelUsage> usage(Map<String, String> filters) => _get(
    Uri(
      path: '/api/v1/users/me/model-usage',
      queryParameters: filters.isEmpty ? null : filters,
    ).toString(),
    ModelUsage.fromJson,
  );
  @override
  Future<JobSocket> connect() => authorizedJobSocket(
    (operation) => auth.authorizedRead(operation),
    (headers) => connectJobSocket(
      api.endpoint.replace(
        scheme: api.endpoint.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/v1/jobs/events',
      ),
      headers,
    ),
  );
}

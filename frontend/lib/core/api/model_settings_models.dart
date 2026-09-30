import 'wire.dart';

int modelInt(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Expected nonnegative integer');
  return value;
}

bool modelBool(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

List<T> modelList<T>(Object? value, T Function(Object?) decode) {
  if (value is! List) throw const FormatException('Expected list');
  return List.unmodifiable(value.map(decode));
}

final class ProviderCredential {
  ProviderCredential.fromJson(Object? value) {
    final j = wireObject(value);
    id = wireUuid(j['id']);
    provider = wireString(j['provider']);
    label = wireString(j['label']);
    maskedKey = wireString(j['masked_key']);
    revision = modelInt(j['revision']);
    credentialVersion = modelInt(j['credential_version']);
    status = wireString(j['status']);
  }
  late final String id, provider, label, maskedKey, status;
  late final int revision, credentialVersion;
}

final class ModelBinding {
  const ModelBinding({
    required this.credentialId,
    required this.provider,
    required this.modelId,
    this.voiceId,
    this.languageTag = 'ja',
    this.outputFormat = 'mp3',
  });
  factory ModelBinding.fromJson(Object? value) {
    final j = wireObject(value);
    return ModelBinding(
      credentialId: wireUuid(j['credential_id']),
      provider: wireString(j['provider']),
      modelId: wireString(j['model_id']),
      voiceId: j['voice_id'] == null ? null : wireString(j['voice_id']),
      languageTag: wireString(j['language_tag']),
      outputFormat: wireString(j['output_format']),
    );
  }
  final String credentialId, provider, modelId, languageTag, outputFormat;
  final String? voiceId;
  Map<String, Object?> toJson() => {
    'credential_id': credentialId,
    'provider': provider,
    'model_id': modelId,
    'voice_id': voiceId,
    'language_tag': languageTag,
    'output_format': outputFormat,
  };
}

final class PersonalModelSettings {
  PersonalModelSettings.fromJson(Object? value) {
    final j = wireObject(value);
    revision = modelInt(j['revision']);
    final b = wireObject(j['bindings']);
    bindings = Map.unmodifiable({
      for (final capability in const ['text', 'vision', 'tts'])
        capability: b[capability] == null ? null : ModelBinding.fromJson(b[capability]),
    });
  }
  late final int revision;
  late final Map<String, ModelBinding?> bindings;
}

final class CatalogModel {
  CatalogModel.fromJson(Object? value) {
    final j = wireObject(value);
    id = wireUuid(j['id']);
    provider = wireString(j['provider']);
    modelId = wireString(j['model_id']);
    displayName = wireString(j['display_name']);
    capabilities = modelList(j['capabilities'], wireString);
    enabled = modelBool(j['enabled']);
    verified = modelBool(j['verified']);
    revision = modelInt(j['revision']);
  }
  late final String id, provider, modelId, displayName;
  late final List<String> capabilities;
  late final bool enabled, verified;
  late final int revision;
}

final class CatalogVoice {
  CatalogVoice.fromJson(Object? value) {
    final j = wireObject(value);
    provider = wireString(j['provider']);
    modelId = wireString(j['model_id']);
    voiceId = wireString(j['voice_id']);
    languages = modelList(j['language_tags'], wireString);
    formats = modelList(j['output_formats'], wireString);
    verified = modelBool(j['verified']);
  }
  late final String provider, modelId, voiceId;
  late final List<String> languages, formats;
  late final bool verified;
}

final class ModelLimits {
  ModelLimits.fromJson(Object? value) {
    final j = wireObject(value);
    enabled = modelBool(j['enabled']);
    revision = modelInt(j['revision']);
    values = Map.unmodifiable({
      for (final key in const [
        'max_credentials',
        'max_concurrent_jobs',
        'instance_concurrent_jobs',
        'max_model_calls',
        'max_output_tokens',
        'timeout_seconds',
        'tts_timeout_seconds',
        'max_test_image_bytes',
        'max_tts_characters',
        'websocket_max_jobs',
      ])
        key: modelInt(j[key]),
    });
  }
  late final bool enabled;
  late final int revision;
  late final Map<String, int> values;
  Map<String, Object?> toJson() => {...values, 'enabled': enabled, 'revision': revision};
}

final class ModelDirectory {
  ModelDirectory.fromJson(Object? value) {
    final j = wireObject(value);
    revision = modelInt(j['revision']);
    models = modelList(j['models'], CatalogModel.fromJson);
    voices = modelList(j['voices'], CatalogVoice.fromJson);
    limits = ModelLimits.fromJson(j['limits']);
  }
  late final int revision;
  late final List<CatalogModel> models;
  late final List<CatalogVoice> voices;
  late final ModelLimits limits;
}

final class UsageMetric {
  UsageMetric.fromJson(Object? value) {
    final j = wireObject(value);
    knownSum = j['known_sum'] == null ? null : modelInt(j['known_sum']);
    knownAttempts = modelInt(j['known_attempt_count']);
    unknownAttempts = modelInt(j['unknown_attempt_count']);
    completeness = wireString(j['completeness']);
  }
  late final int? knownSum;
  late final int knownAttempts, unknownAttempts;
  late final String completeness;
  String get display =>
      knownSum == null ? '未提供' : '$knownSum${completeness == 'partial' ? '（部分）' : ''}';
}

final class UsageGroup {
  UsageGroup.fromJson(Object? value) {
    final j = wireObject(value);
    provider = wireString(j['provider']);
    modelId = wireString(j['model_id']);
    capability = wireString(j['capability']);
    operationKind = wireString(j['operation_kind']);
    simulated = modelBool(j['simulated']);
    attempts = modelInt(j['attempt_count']);
    started = modelInt(j['started_count']);
    succeeded = modelInt(j['succeeded_count']);
    failed = modelInt(j['failed_count']);
    unknown = modelInt(j['unknown_count']);
    final m = wireObject(j['metrics']);
    metrics = Map.unmodifiable(m.map((k, v) => MapEntry(k, UsageMetric.fromJson(v))));
  }
  late final String provider, modelId, capability, operationKind;
  late final bool simulated;
  late final int attempts, started, succeeded, failed, unknown;
  late final Map<String, UsageMetric> metrics;
}

final class ModelUsage {
  ModelUsage.fromJson(Object? value) {
    final j = wireObject(value);
    asOf = wireUtc(j['as_of']);
    aggregationRevision = j['aggregation_revision'] == null
        ? null
        : modelInt(j['aggregation_revision']);
    groups = modelList(j['groups'], UsageGroup.fromJson);
  }
  late final DateTime asOf;
  late final int? aggregationRevision;
  late final List<UsageGroup> groups;
}

final class ModelJob {
  ModelJob.fromJson(Object? value) {
    final j = wireObject(value);
    id = wireUuid(j['id']);
    runId = wireUuid(j['run_id']);
    credentialId = wireUuid(j['credential_id']);
    state = wireString(j['state']);
    revision = modelInt(j['revision']);
    generation = modelInt(j['generation']);
    sequence = modelInt(j['sequence']);
    stage = j['stage'] == null ? null : wireString(j['stage']);
    progress = j['progress_percent'] == null ? null : modelInt(j['progress_percent']);
    errorCode = j['error_code'] == null ? null : wireString(j['error_code']);
    canCancel = modelBool(j['can_cancel']);
    canRetry = modelBool(j['can_retry']);
    requiresConfirmation = modelBool(j['requires_new_attempt_confirmation']);
  }
  late final String id, runId, credentialId, state;
  late final int revision, generation, sequence;
  late final int? progress;
  late final String? stage, errorCode;
  late final bool canCancel, canRetry, requiresConfirmation;
  bool get terminal => const {
    'succeeded',
    'completed',
    'failed',
    'cancelled',
    'unknown',
    'blocked',
    'unknown_outcome',
    'superseded',
  }.contains(state);
  bool newerThan(ModelJob previous) =>
      generation > previous.generation ||
      (generation == previous.generation && sequence > previous.sequence);
}

final class CredentialTestResult {
  CredentialTestResult.fromJson(Object? value) {
    final j = wireObject(value);
    runId = wireUuid(j['run_id']);
    jobId = wireUuid(j['job_id']);
    credentialId = wireUuid(j['credential_id']);
    credentialVersion = modelInt(j['credential_version']);
    provider = wireString(j['provider']);
    modelId = wireString(j['model_id']);
    capability = wireString(j['capability']);
    state = wireString(j['state']);
    errorCode = j['error_code'] == null ? null : wireString(j['error_code']);
    testedAt = j['tested_at'] == null ? null : wireUtc(j['tested_at']);
    usage = ModelUsage.fromJson(j['usage']);
  }
  late final String runId, jobId, credentialId, provider, modelId, capability, state;
  late final int credentialVersion;
  late final String? errorCode;
  late final DateTime? testedAt;
  late final ModelUsage usage;
}

final class AcceptedModelTest {
  AcceptedModelTest.fromJson(Object? value) {
    final j = wireObject(value);
    jobId = wireUuid(j['job_id']);
    runId = wireUuid(j['run_id']);
    generation = modelInt(j['generation']);
    state = wireString(j['state']);
  }
  late final String jobId, runId, state;
  late final int generation;
}

final class ModelJobEvent {
  ModelJobEvent.fromJson(Object? value) {
    final j = wireObject(value);
    if (j['schema_version'] != 1) throw const FormatException('Unsupported job event');
    jobId = wireUuid(j['job_id']);
    type = wireString(j['type']);
    generation = modelInt(j['generation']);
    sequence = modelInt(j['sequence']);
    payload = ModelJob.fromJson(j['payload']);
    if (payload.id != jobId || payload.generation != generation || payload.sequence != sequence) {
      throw const FormatException('Inconsistent job event');
    }
  }
  late final String jobId, type;
  late final int generation, sequence;
  late final ModelJob payload;
}

final class AdminModelJob {
  AdminModelJob.fromJson(Object? value) {
    final j = wireObject(value);
    id = wireUuid(j['id']);
    operationKind = wireString(j['operation_kind']);
    state = wireString(j['state']);
    revision = modelInt(j['revision']);
    generation = modelInt(j['generation']);
    sequence = modelInt(j['sequence']);
    errorCode = j['error_code'] == null ? null : wireString(j['error_code']);
    canCancel = modelBool(j['can_cancel']);
    canRetry = modelBool(j['can_retry']);
  }
  late final String id, operationKind, state;
  late final String? errorCode;
  late final int revision, generation, sequence;
  late final bool canCancel, canRetry;
}

final class UserModelLimit {
  UserModelLimit.fromJson(Object? value) {
    final j = wireObject(value);
    userId = wireUuid(j['user_id']);
    revision = modelInt(j['revision']);
    concurrentJobs = modelInt(j['max_concurrent_jobs']);
  }
  late final String userId;
  late final int revision, concurrentJobs;
}

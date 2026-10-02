import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/core/api/model_settings_models.dart';
import 'package:haruka/features/library/domain/material_import.dart';
import 'package:haruka/features/library/domain/material_metadata.dart';
import 'package:haruka/features/library/domain/material_summary.dart';

import '../../support/generated/api_compatibility_samples.dart';

void main() {
  test('Pydantic source jobs preserve source status and language issue binding', () {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final queued = SuccessResponse.fromJson(
      samples['material_source_job_queued'],
      ModelJob.fromJson,
    ).data;
    final blocked = SuccessResponse.fromJson(
      samples['material_source_job_blocked'],
      ModelJob.fromJson,
    ).data;
    expect(queued.sourceImport, isTrue);
    expect(queued.runId, isNull);
    expect(queued.credentialId, isNull);
    expect(queued.materialId, '018f1234-5678-7123-8123-123456789abc');
    expect(queued.materialRevisionId, queued.materialId);
    expect(queued.state, 'queued');
    expect(queued.stage, 'source_validation');
    expect(queued.progress, 0);
    expect(queued.sourceStatus, 'parsing');
    expect(queued.languageIssue, isNull);
    expect(blocked.id, queued.id);
    expect(blocked.newerThan(queued), isTrue);
    expect(blocked.state, 'blocked');
    expect(blocked.stage, 'language_assessment');
    expect(blocked.progress, 50);
    expect(blocked.errorCode, 'INPUT_INVALID');
    expect(blocked.sourceStatus, 'parsing');
    final issue = blocked.languageIssue!;
    expect(issue.revision, 1);
    expect(issue.materialRevisionId, blocked.materialRevisionId);
    expect(issue.inputDigest, List.filled(64, 'a').join());
    expect(issue.declaredLanguage, 'en');
    expect(blocked.runId, isNull);
    expect(blocked.credentialId, isNull);
    expect(blocked.requiresConfirmation, isFalse);
    final blockedJson = wireObject(wireObject(samples['material_source_job_blocked'])['data']);
    expect(
      () => ModelJob.fromJson({...blockedJson, 'requires_new_attempt_confirmation': true}),
      throwsFormatException,
    );
  });
  test('Pydantic material samples preserve upload and source-readiness contracts', () {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final pending = SuccessResponse.fromJson(
      samples['material_import_pending'],
      MaterialImport.fromJson,
    ).data;
    expect(pending.status, 'awaiting_upload');
    expect(pending.type, LearningMaterialType.novel);
    expect(pending.language, 'ja');
    expect(pending.accepted, isFalse);
    expect(pending.materialId, isNull);
    expect(pending.jobId, isNull);
    final upload = pending.upload!;
    expect(upload.url.path, '/api/v1/uploads/${upload.id}/content');
    expect(upload.url.hasQuery, isFalse);
    expect(upload.headers.keys, ['X-Haruka-Upload-Capability']);
    final accepted = SuccessResponse.fromJson(
      samples['material_import_accepted'],
      MaterialImport.fromJson,
    ).data;
    expect(accepted.id, pending.id);
    expect(accepted.revision, 2);
    expect(accepted.accepted, isTrue);
    expect(accepted.materialId, pending.id);
    expect(accepted.jobId, upload.id);
    expect(accepted.upload, isNull);
    final acceptedJson = wireObject(wireObject(samples['material_import_accepted'])['data']);
    final pendingJson = wireObject(wireObject(samples['material_import_pending'])['data']);
    expect(() => MaterialImport.fromJson({...acceptedJson, 'job_id': null}), throwsFormatException);
    expect(
      () => MaterialImport.fromJson({...pendingJson, 'material_id': accepted.materialId}),
      throwsFormatException,
    );
    expect(
      () => MaterialImport.fromJson({...acceptedJson, 'upload': pendingJson['upload']}),
      throwsFormatException,
    );
    final limits = SuccessResponse.fromJson(
      samples['material_capabilities'],
      MaterialImportCapabilities.fromJson,
    ).data;
    final exam = limits.forType(LearningMaterialType.exam)!;
    expect(exam.formats, ['md', 'epub', 'pdf', 'png', 'jpeg', 'webp']);
    expect(exam.languages, ['ja', 'en']);
    expect(exam.maxSizeBytes, 32 * 1024 * 1024);
    expect(exam.limitFor('md'), 20000000);
    expect(exam.limitFor('png'), 20000000);
    expect(exam.limitFor('pdf'), 32 * 1024 * 1024);
    for (final type in [LearningMaterialType.novel, LearningMaterialType.textbook]) {
      expect(limits.forType(type)!.formats, ['md', 'epub', 'pdf']);
      expect(limits.forType(type)!.languages, ['ja', 'en']);
    }
    final sourceOnly = SuccessResponse.fromJson(
      samples['material_metadata_pending'],
      MaterialMetadata.fromJson,
    ).data;
    expect(sourceOnly.type, LearningMaterialType.exam);
    expect(sourceOnly.language, 'en');
    expect(sourceOnly.sourceFormat, 'pdf');
    expect(sourceOnly.sourceStatus, 'parsing');
    expect(sourceOnly.analysisStatus, 'not_requested');
    expect(sourceOnly.readable, isFalse);
    expect(sourceOnly.contentRevisionId, isNull);
    expect(sourceOnly.firstChapterId, isNull);
    expect(sourceOnly.progressPercent, isNull);
    final published = SuccessResponse.fromJson(
      samples['material_metadata_published'],
      MaterialMetadata.fromJson,
    ).data;
    expect(published.type, LearningMaterialType.novel);
    expect(published.sourceStatus, 'readable');
    expect(published.readable, isTrue);
    expect(published.contentRevisionId, pending.id);
    expect(published.firstChapterId, upload.id);
    expect(published.sourceFormat, isNull);
  });
}

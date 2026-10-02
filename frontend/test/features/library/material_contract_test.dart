import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/features/library/domain/material_import.dart';
import 'package:haruka/features/library/domain/material_metadata.dart';
import 'package:haruka/features/library/domain/material_summary.dart';

import '../../support/generated/api_compatibility_samples.dart';

void main() {
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
    expect(upload.headers.keys, ['X-Haruka-Upload-Grant']);
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
    expect(exam.maxSizeBytes, 80 * 1024 * 1024);
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

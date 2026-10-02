import '../../../core/api/wire.dart';
import 'material_summary.dart';

/// Metadata revisions are for CAS, not proof that learning content is ready.
final class MaterialMetadata {
  const MaterialMetadata({
    required this.id,
    required this.libraryId,
    required this.type,
    required this.title,
    required this.sourceStatus,
    required this.analysisStatus,
    required this.revision,
    required this.deleteGeneration,
    required this.readable,
    required this.createdAt,
    required this.updatedAt,
    this.language,
    this.sourceFormat,
    this.contentRevisionId,
    this.firstChapterId,
    this.jobId,
    this.progressPercent,
    this.sourceRevisionNumber,
  });
  final String id;
  final String libraryId;
  final LearningMaterialType type;
  final String title;
  final String? language;
  final String? sourceFormat;
  final String sourceStatus;
  final String analysisStatus;
  final int revision;
  final int deleteGeneration;
  final String? contentRevisionId;
  final String? firstChapterId;
  final String? jobId;
  final int? progressPercent;
  final int? sourceRevisionNumber;
  final bool readable;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MaterialMetadata.fromJson(Object? value) {
    final json = wireObject(value);
    final type = json['material_type'];
    final status = wireString(json['source_status']);
    final analysis = wireString(json['analysis_status']);
    final language = json['language'];
    final readable = json['readable'];
    final revision = json['revision'];
    final generation = json['delete_generation'];
    final progress = json['progress_percent'];
    final sourceRevision = json['source_revision_number'];
    if (!LearningMaterialType.values.any((candidate) => candidate.name == type) ||
        !const {'parsing', 'readable', 'degraded', 'failed'}.contains(status) ||
        !const {'not_requested', 'pending', 'ready', 'failed'}.contains(analysis) ||
        (language != null && !const {'ja', 'en'}.contains(language)) ||
        readable is! bool ||
        revision is! int ||
        revision < 1 ||
        generation is! int ||
        generation < 0 ||
        (progress != null && (progress is! int || progress < 0 || progress > 100)) ||
        (sourceRevision != null && (sourceRevision is! int || sourceRevision < 1))) {
      throw const FormatException('Invalid material metadata');
    }
    return MaterialMetadata(
      id: wireUuid(json['id']),
      libraryId: wireUuid(json['library_id']),
      type: LearningMaterialType.values.byName(type as String),
      title: wireString(json['title']),
      language: language as String?,
      sourceFormat: json['source_format'] == null ? null : wireString(json['source_format']),
      sourceStatus: status,
      analysisStatus: analysis,
      revision: revision,
      deleteGeneration: generation,
      contentRevisionId: json['revision_id'] == null ? null : wireUuid(json['revision_id']),
      firstChapterId: json['first_chapter_id'] == null ? null : wireUuid(json['first_chapter_id']),
      jobId: json['job_id'] == null ? null : wireUuid(json['job_id']),
      progressPercent: progress as int?,
      sourceRevisionNumber: sourceRevision as int?,
      readable: readable,
      createdAt: wireUtc(json['created_at']),
      updatedAt: wireUtc(json['updated_at']),
    );
  }
}

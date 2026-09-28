enum LearningMaterialType { novel, textbook, exam }

final class MaterialSummary {
  const MaterialSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.language,
    required this.status,
    required this.revision,
    required this.updatedAt,
    required this.description,
    required this.cover,
    this.sectionCount,
    this.activeJobProgressPercent,
  });

  final String id;
  final LearningMaterialType type;
  final String title;
  final String language;
  final String status;
  final int revision;
  final DateTime updatedAt;
  final String description;
  final String cover;
  final int? sectionCount;
  final int? activeJobProgressPercent;

  factory MaterialSummary.fromJson(Map<String, Object?> json) {
    final type = LearningMaterialType.values.byName(json['material_type'] as String);
    final summary = json['structure_summary'] as Map<String, Object?>?;
    final countKey = switch (type) {
      LearningMaterialType.novel => 'chapter_count',
      LearningMaterialType.textbook => 'unit_count',
      LearningMaterialType.exam => 'question_count',
    };
    return MaterialSummary(
      id: json['id'] as String,
      type: type,
      title: json['title'] as String,
      language: json['language'] as String,
      status: json['source_status'] as String,
      revision: json['revision'] as int,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      description: json['description'] as String,
      cover: json['cover'] as String,
      sectionCount: summary?[countKey] as int?,
      activeJobProgressPercent:
          (json['active_job'] as Map<String, Object?>?)?['progress_percent'] as int?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'material_type': type.name,
    'title': title,
    'language': language,
    'source_status': status,
    'revision': revision,
    'updated_at': updatedAt.toIso8601String(),
    'description': description,
    'cover': cover,
    'active_job': activeJobProgressPercent == null
        ? null
        : {'progress_percent': activeJobProgressPercent},
    'structure_summary': sectionCount == null
        ? null
        : {
            switch (type) {
              LearningMaterialType.novel => 'chapter_count',
              LearningMaterialType.textbook => 'unit_count',
              LearningMaterialType.exam => 'question_count',
            }: sectionCount,
          },
  };
}

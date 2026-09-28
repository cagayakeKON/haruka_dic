enum CollectionKind { word, phrase, grammar, sentence, excerpt, exercise }

final class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.kind,
    required this.displayText,
    required this.targetLanguage,
    required this.meaning,
    required this.createdAt,
    this.reading,
    this.lemma,
    this.context,
    this.sourceTitle,
    this.sourceMaterialId,
    this.tags = const [],
    this.importedStatus,
    this.exerciseControl = 'active',
    this.sourceCreatedAt,
    this.sourceUpdatedAt,
    this.notebookIds = const {},
    this.notes = '',
    this.revision = 1,
    this.learningCardId,
    this.learningCardRevision,
    this.learningCardSnapshot,
  });

  final String id;
  final CollectionKind kind;
  final String displayText;
  final String targetLanguage;
  final String meaning;
  final DateTime createdAt;
  final String? reading;
  final String? lemma;
  final String? context;
  final String? sourceTitle;
  final String? sourceMaterialId;
  final List<String> tags;
  final String? importedStatus;
  final String exerciseControl;
  final DateTime? sourceCreatedAt;
  final DateTime? sourceUpdatedAt;
  final Set<String> notebookIds;
  final String notes;
  final int revision;
  final String? learningCardId;
  final int? learningCardRevision;
  final Map<String, Object?>? learningCardSnapshot;

  CollectionEntry copyWith({
    String? displayText,
    String? meaning,
    String? notes,
    Set<String>? notebookIds,
  }) => CollectionEntry(
    id: id,
    kind: kind,
    displayText: displayText ?? this.displayText,
    targetLanguage: targetLanguage,
    meaning: meaning ?? this.meaning,
    createdAt: createdAt,
    reading: reading,
    lemma: lemma,
    context: context,
    sourceTitle: sourceTitle,
    sourceMaterialId: sourceMaterialId,
    tags: tags,
    importedStatus: importedStatus,
    exerciseControl: exerciseControl,
    sourceCreatedAt: sourceCreatedAt,
    sourceUpdatedAt: sourceUpdatedAt,
    notebookIds: notebookIds ?? this.notebookIds,
    notes: notes ?? this.notes,
    revision: revision + 1,
    learningCardId: learningCardId,
    learningCardRevision: learningCardRevision,
    learningCardSnapshot: learningCardSnapshot,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'display_text': displayText,
    'target_language': targetLanguage,
    'reading': reading,
    'lemma': lemma,
    'meaning': meaning,
    'context': context,
    'source_snapshot': sourceTitle == null && sourceMaterialId == null
        ? null
        : {'title': sourceTitle, 'material_id': sourceMaterialId},
    'notebook_ids': notebookIds.toList(),
    'notes': notes,
    'tags': tags,
    'imported_status': importedStatus,
    'exercise_control': exerciseControl,
    'source_created_at': sourceCreatedAt?.toIso8601String(),
    'source_updated_at': sourceUpdatedAt?.toIso8601String(),
    'revision': revision,
    'learning_card_id': learningCardId,
    'learning_card_revision': learningCardRevision,
    'learning_card_snapshot': learningCardSnapshot,
    'created_at': createdAt.toIso8601String(),
  };

  factory CollectionEntry.fromJson(Map<String, Object?> json) {
    final source = json['source_snapshot'];
    return CollectionEntry(
      id: json['id'] as String,
      kind: CollectionKind.values.byName(json['kind'] as String),
      displayText: json['display_text'] as String,
      targetLanguage: json['target_language'] as String,
      reading: json['reading'] as String?,
      lemma: json['lemma'] as String?,
      meaning: json['meaning'] as String,
      context: json['context'] as String?,
      sourceTitle: source == null ? null : (source as Map)['title'] as String?,
      sourceMaterialId: source == null ? null : (source as Map)['material_id'] as String?,
      notebookIds: Set<String>.from(json['notebook_ids'] as List),
      notes: json['notes'] as String? ?? '',
      tags: List<String>.from(json['tags'] as List? ?? const []),
      importedStatus: json['imported_status'] as String?,
      exerciseControl: json['exercise_control'] as String? ?? 'active',
      sourceCreatedAt: switch (json['source_created_at']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
      sourceUpdatedAt: switch (json['source_updated_at']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
      revision: json['revision'] as int? ?? 1,
      learningCardId: json['learning_card_id'] as String?,
      learningCardRevision: json['learning_card_revision'] as int?,
      learningCardSnapshot: switch (json['learning_card_snapshot']) {
        final Map<Object?, Object?> value => value.cast<String, Object?>(),
        _ => null,
      },
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

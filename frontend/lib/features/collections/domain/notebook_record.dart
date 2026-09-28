final class NotebookRecord {
  const NotebookRecord({
    required this.id,
    required this.name,
    required this.targetLanguage,
    required this.description,
    required this.revision,
  });

  final String id;
  final String name;
  final String targetLanguage;
  final String description;
  final int revision;

  NotebookRecord copyWith({String? name, String? description}) => NotebookRecord(
    id: id,
    name: name ?? this.name,
    targetLanguage: targetLanguage,
    description: description ?? this.description,
    revision: revision + 1,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'target_language': targetLanguage,
    'description': description,
    'revision': revision,
  };

  factory NotebookRecord.fromJson(Map<String, Object?> json) => NotebookRecord(
    id: json['id'] as String,
    name: json['name'] as String,
    targetLanguage: json['target_language'] as String,
    description: json['description'] as String,
    revision: json['revision'] as int,
  );
}

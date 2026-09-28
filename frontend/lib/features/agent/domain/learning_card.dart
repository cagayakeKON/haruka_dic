import '../../collections/domain/collection_entry.dart';

final class WordExample {
  const WordExample({required this.text, required this.translation});

  final String text;
  final String translation;

  Map<String, Object?> toJson() => {'text': text, 'translation': translation};

  factory WordExample.fromJson(Map<String, Object?> json) =>
      WordExample(text: json['text'] as String, translation: json['translation'] as String);
}

final class WordCardDetail {
  const WordCardDetail({
    required this.romanization,
    required this.partOfSpeech,
    required this.meaning,
    required this.usage,
    required this.examples,
  });

  final String romanization;
  final String partOfSpeech;
  final String meaning;
  final String usage;
  final List<WordExample> examples;

  Map<String, Object?> toJson() => {
    'romanization': romanization,
    'part_of_speech': partOfSpeech,
    'meaning': meaning,
    'usage': usage,
    'examples': [for (final example in examples) example.toJson()],
  };

  factory WordCardDetail.fromJson(Map<String, Object?> json) => WordCardDetail(
    romanization: json['romanization'] as String,
    partOfSpeech: json['part_of_speech'] as String,
    meaning: json['meaning'] as String,
    usage: json['usage'] as String,
    examples: [
      for (final value in json['examples'] as List)
        WordExample.fromJson((value as Map).cast<String, Object?>()),
    ],
  );
}

final class LearningCard {
  const LearningCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.explanation,
    required this.examples,
    required this.version,
    this.wordDetail,
  });

  final String id;
  final CollectionKind kind;
  final String title;
  final String explanation;
  final List<String> examples;
  final int version;
  final WordCardDetail? wordDetail;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'explanation': explanation,
    'examples': examples,
    'revision': version,
    if (wordDetail != null) 'word_detail': wordDetail!.toJson(),
  };

  factory LearningCard.fromJson(Map<String, Object?> json) => LearningCard(
    id: json['id'] as String,
    kind: CollectionKind.values.byName(json['kind'] as String),
    title: json['title'] as String,
    explanation: json['explanation'] as String,
    examples: List<String>.from(json['examples'] as List),
    version: json['revision'] as int,
    wordDetail: json['word_detail'] == null
        ? null
        : WordCardDetail.fromJson((json['word_detail'] as Map).cast<String, Object?>()),
  );
}

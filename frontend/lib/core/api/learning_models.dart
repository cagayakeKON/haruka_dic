import 'wire.dart';

String _language(Object? value) {
  final language = wireString(value);
  if (language != 'ja' && language != 'en') throw const FormatException('Invalid language');
  return language;
}

final class SourceSpan {
  const SourceSpan({required this.blockId, required this.start, required this.end});
  factory SourceSpan.fromJson(Object? value) {
    final json = wireObject(value);
    final start = json['start'];
    final end = json['end'];
    if (start is! int || end is! int || start < 0 || end <= start) {
      throw const FormatException('Invalid span');
    }
    return SourceSpan(blockId: wireUuid(json['block_id']), start: start, end: end);
  }
  final String blockId;
  final int start;
  final int end;
  Map<String, Object?> toJson() => {'block_id': blockId, 'start': start, 'end': end};
}

/// Source identity and whole-block bounds are published by the server. A
/// client-selected subrange remains a claim until the server rereads the
/// versioned source and validates its span, text and permissions.
final class NovelContentLocator {
  const NovelContentLocator({
    required this.instanceId,
    required this.libraryId,
    required this.materialId,
    required this.materialRevisionId,
    required this.novelChapterId,
    required this.chapterBlockId,
    required this.quote,
    required this.prefix,
    required this.suffix,
    required this.sourceTitle,
    required this.nodeTitle,
    required this.span,
  });
  factory NovelContentLocator.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['locator_schema_version'] != 1 ||
        json['target_kind'] != 'material_content' ||
        json['text_protocol_version'] != 'canonical-text-v1') {
      throw const FormatException('Unsupported locator');
    }
    final spans = json['spans'];
    if (spans is! List<Object?> || spans.length != 1) {
      throw const FormatException('Invalid source spans');
    }
    return NovelContentLocator(
      instanceId: wireString(json['instance_id']),
      libraryId: wireUuid(json['library_id']),
      materialId: wireUuid(json['material_id']),
      materialRevisionId: wireUuid(json['material_revision_id']),
      novelChapterId: wireUuid(json['novel_chapter_id']),
      chapterBlockId: wireUuid(json['chapter_block_id']),
      quote: wireString(json['quote']),
      prefix: wireString(json['prefix']),
      suffix: wireString(json['suffix']),
      sourceTitle: json['source_title'] == null ? null : wireString(json['source_title']),
      nodeTitle: json['node_title'] == null ? null : wireString(json['node_title']),
      span: SourceSpan.fromJson(spans.single),
    );
  }
  final String instanceId;
  final String libraryId;
  final String materialId;
  final String materialRevisionId;
  final String novelChapterId;
  final String chapterBlockId;
  final String quote;
  final String prefix;
  final String suffix;
  final String? sourceTitle;
  final String? nodeTitle;
  final SourceSpan span;
  Map<String, Object?> toJson() => {
    'locator_schema_version': 1,
    'instance_id': instanceId,
    'library_id': libraryId,
    'target_kind': 'material_content',
    'text_protocol_version': 'canonical-text-v1',
    'material_id': materialId,
    'material_revision_id': materialRevisionId,
    'novel_chapter_id': novelChapterId,
    'chapter_block_id': chapterBlockId,
    'quote': quote,
    'prefix': prefix,
    'suffix': suffix,
    if (sourceTitle != null) 'source_title': sourceTitle,
    if (nodeTitle != null) 'node_title': nodeTitle,
    'spans': [span.toJson()],
  };
}

final class MaterialSummary {
  const MaterialSummary({
    required this.id,
    required this.libraryId,
    required this.revisionId,
    required this.firstChapterId,
    required this.title,
    required this.language,
  });
  factory MaterialSummary.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['material_type'] != 'novel') throw const FormatException('Invalid material type');
    wireUtc(json['created_at']);
    return MaterialSummary(
      id: wireUuid(json['id']),
      libraryId: wireUuid(json['library_id']),
      revisionId: wireUuid(json['revision_id']),
      firstChapterId: wireUuid(json['first_chapter_id']),
      title: wireString(json['title']),
      language: _language(json['language']),
    );
  }
  final String id;
  final String libraryId;
  final String revisionId;
  final String firstChapterId;
  final String title;
  final String language;
}

final class NovelBlock {
  const NovelBlock({
    required this.id,
    required this.chapterBlockId,
    required this.text,
    required this.ordinal,
    required this.locator,
  });
  factory NovelBlock.fromJson(Object? value) {
    final json = wireObject(value);
    final ordinal = json['ordinal'];
    if (ordinal is! int || ordinal < 0) throw const FormatException('Invalid block ordinal');
    return NovelBlock(
      id: wireUuid(json['id']),
      chapterBlockId: wireUuid(json['chapter_block_id']),
      text: wireString(json['canonical_text']),
      ordinal: ordinal,
      locator: NovelContentLocator.fromJson(json['source_locator']),
    );
  }
  final String id;
  final String chapterBlockId;
  final String text;
  final int ordinal;
  final NovelContentLocator locator;
}

final class NovelChapter {
  const NovelChapter({
    required this.materialId,
    required this.libraryId,
    required this.revisionId,
    required this.nodeId,
    required this.title,
    required this.blocks,
  });
  factory NovelChapter.fromJson(Object? value) {
    final json = wireObject(value);
    final blocks = json['blocks'];
    if (blocks is! List<Object?>) throw const FormatException('Invalid chapter blocks');
    return NovelChapter(
      materialId: wireUuid(json['material_id']),
      libraryId: wireUuid(json['library_id']),
      revisionId: wireUuid(json['revision_id']),
      nodeId: wireUuid(json['node_id']),
      title: wireString(json['title']),
      blocks: List.unmodifiable(blocks.map(NovelBlock.fromJson)),
    );
  }
  final String materialId;
  final String libraryId;
  final String revisionId;
  final String nodeId;
  final String title;
  final List<NovelBlock> blocks;
}

final class WordExample {
  const WordExample({required this.text, required this.meaning});
  factory WordExample.fromJson(Object? value) {
    final json = wireObject(value);
    return WordExample(text: wireString(json['text']), meaning: wireString(json['meaning']));
  }
  final String text;
  final String meaning;
}

final class WordCardPayload {
  const WordCardPayload({
    required this.term,
    required this.reading,
    required this.partOfSpeech,
    required this.contextMeaning,
    required this.otherMeanings,
    required this.examples,
  });
  factory WordCardPayload.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['lexical_kind'] != 'word') throw const FormatException('Invalid card kind');
    final meanings = json['other_meanings'];
    final examples = json['examples'];
    if (meanings is! List<Object?> || examples is! List<Object?> || examples.length != 2) {
      throw const FormatException('Invalid word card');
    }
    return WordCardPayload(
      term: wireString(json['term']),
      reading: json['reading'] == null ? null : wireString(json['reading']),
      partOfSpeech: wireString(json['part_of_speech']),
      contextMeaning: wireString(json['context_meaning']),
      otherMeanings: List.unmodifiable(meanings.map(wireString)),
      examples: List.unmodifiable(examples.map(WordExample.fromJson)),
    );
  }
  final String term;
  final String? reading;
  final String partOfSpeech;
  final String contextMeaning;
  final List<String> otherMeanings;
  final List<WordExample> examples;
}

final class WordCard {
  const WordCard({
    required this.id,
    required this.revision,
    required this.targetLanguage,
    required this.explanationLanguage,
    required this.payload,
    required this.sourceRefs,
  });
  factory WordCard.fromJson(Object? value) {
    final json = wireObject(value);
    final revision = json['card_revision'];
    if (json['type'] != 'word' ||
        json['schema_version'] != 1 ||
        json['provenance'] != 'material' ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid word card version');
    }
    wireUtc(json['created_at']);
    final refs = json['source_refs'];
    if (refs is! List<Object?> || refs.isEmpty) throw const FormatException('Invalid source refs');
    return WordCard(
      id: wireUuid(json['card_id']),
      revision: revision,
      targetLanguage: _language(json['target_language']),
      explanationLanguage: wireString(json['explanation_language']),
      payload: WordCardPayload.fromJson(json['payload']),
      sourceRefs: List.unmodifiable(refs.map(NovelContentLocator.fromJson)),
    );
  }
  final String id;
  final int revision;
  final String targetLanguage;
  final String explanationLanguage;
  final WordCardPayload payload;
  final List<NovelContentLocator> sourceRefs;
}

final class ResolvedCard {
  const ResolvedCard({required this.found, required this.card});
  factory ResolvedCard.fromJson(Object? value) {
    final json = wireObject(value);
    final state = wireString(json['state']);
    if (state == 'missing' && json['card'] == null) {
      return const ResolvedCard(found: false, card: null);
    }
    if (state != 'found') throw const FormatException('Invalid resolved card');
    return ResolvedCard(found: true, card: WordCard.fromJson(json['card']));
  }
  final bool found;
  final WordCard? card;
}

final class ExplanationResolveRead {
  const ExplanationResolveRead(this.results);
  factory ExplanationResolveRead.fromJson(Object? value) {
    final results = wireObject(value)['results'];
    if (results is! List<Object?> || results.length != 1) {
      throw const FormatException('Invalid resolve result count');
    }
    return ExplanationResolveRead(List.unmodifiable(results.map(ResolvedCard.fromJson)));
  }
  final List<ResolvedCard> results;
}

final class CollectionRead {
  const CollectionRead({
    required this.id,
    required this.revision,
    required this.cardId,
    required this.cardRevision,
    required this.displayText,
    required this.targetLanguage,
    required this.payload,
    required this.sourceRefs,
    required this.createdAt,
  });
  factory CollectionRead.fromJson(Object? value) {
    final json = wireObject(value);
    final revision = json['revision'];
    final cardRevision = json['card_revision'];
    if (json['kind'] != 'word' ||
        revision is! int ||
        revision < 1 ||
        cardRevision is! int ||
        cardRevision < 1) {
      throw const FormatException('Invalid collection revision');
    }
    final refs = json['source_refs'];
    if (refs is! List<Object?>) throw const FormatException('Invalid collection refs');
    return CollectionRead(
      id: wireUuid(json['id']),
      revision: revision,
      cardId: wireUuid(json['card_id']),
      cardRevision: cardRevision,
      displayText: wireString(json['display_text']),
      targetLanguage: _language(json['target_language']),
      payload: WordCardPayload.fromJson(json['payload']),
      sourceRefs: List.unmodifiable(refs.map(NovelContentLocator.fromJson)),
      createdAt: wireUtc(json['created_at']),
    );
  }
  final String id;
  final int revision;
  final String cardId;
  final int cardRevision;
  final String displayText;
  final String targetLanguage;
  final WordCardPayload payload;
  final List<NovelContentLocator> sourceRefs;
  final DateTime createdAt;
}

import 'dart:convert';

import 'support/generated/api_compatibility_samples.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/learning_models.dart';
import 'package:haruka/core/api/responses.dart';

void main() {
  final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;

  test('persisted card, read-only resolve and collection share source identity', () {
    final card = SuccessResponse.fromJson(samples['learning_word_card'], WordCard.fromJson).data;
    final resolved = SuccessResponse.fromJson(
      samples['learning_resolve_found'],
      ExplanationResolveRead.fromJson,
    ).data;
    final collection = SuccessResponse.fromJson(
      samples['learning_collection'],
      CollectionRead.fromJson,
    ).data;
    expect(resolved.results.single.found, isTrue);
    expect(resolved.results.single.card!.id, card.id);
    expect(collection.cardId, card.id);
    expect(collection.cardRevision, card.revision);
    expect(collection.sourceRefs.single.materialId, card.sourceRefs.single.materialId);
    expect(collection.sourceRefs.single.span.blockId, card.sourceRefs.single.span.blockId);
  });

  test('unsupported locator and fabricated card kind fail closed', () {
    final value = jsonDecode(jsonEncode(samples['learning_word_card'])) as Map<String, dynamic>;
    final data = value['data'] as Map<String, dynamic>;
    data['type'] = 'sentence';
    expect(() => SuccessResponse.fromJson(value, WordCard.fromJson), throwsFormatException);
  });
}

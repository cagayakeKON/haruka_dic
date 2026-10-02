import '../../core/api/api_client.dart';
import '../../core/api/learning_models.dart';
import '../../core/api/responses.dart';

/// Explanation language of the currently published reference-card flow.
/// It is not the interface locale or a user-editable preference.
const publishedReferenceExplanationLanguage = 'zh-CN';

/// Reads published novel sources and already persisted word cards.
final class ReferenceRepository {
  const ReferenceRepository(this.api);
  final ApiClient api;

  Future<PageResponse<MaterialSummary>> materials(
    Map<String, String> headers, {
    String? cursor,
  }) => api.getPage(
    '/api/v1/materials?limit=20${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
    MaterialSummary.fromJson,
    headers: headers,
  );

  Future<NovelChapter> chapter(MaterialSummary material, Map<String, String> headers) async {
    final result = await api.getJson(
      '/api/v1/novels/${material.id}/revisions/${material.revisionId}'
      '/chapters/${material.firstChapterId}',
      NovelChapter.fromJson,
      headers: headers,
    );
    final chapter = result.data;
    if (chapter.materialId != material.id ||
        chapter.libraryId != material.libraryId ||
        chapter.revisionId != material.revisionId ||
        chapter.nodeId != material.firstChapterId ||
        chapter.blocks.any(
          (block) =>
              block.locator.materialId != material.id ||
              block.locator.materialRevisionId != material.revisionId ||
              block.locator.libraryId != material.libraryId ||
              block.locator.novelChapterId != chapter.nodeId ||
              block.locator.chapterBlockId != block.chapterBlockId ||
              block.locator.span.blockId != block.id ||
              block.locator.span.end - block.locator.span.start != block.text.runes.length ||
              block.locator.quote != block.text,
        )) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
    return chapter;
  }

  Future<ResolvedCard> resolve(
    NovelContentLocator locator,
    String targetLanguage,
    Map<String, String> headers,
  ) async {
    final response = await api.postJson(
      '/api/v1/explanations/resolve',
      {
        'targets': [
          {
            'source_locator': locator.toJson(),
            'target_language': targetLanguage,
            'explanation_language': publishedReferenceExplanationLanguage,
          },
        ],
      },
      ExplanationResolveRead.fromJson,
      headers: headers,
    );
    return response.data.results.single;
  }

  Future<CollectionRead> create(
    WordCard card,
    String idempotencyKey,
    Map<String, String> headers,
  ) async {
    final response = await api.postJson(
      '/api/v1/collections',
      {
        'card_id': card.id,
        'card_revision': card.revision,
        'confirmed_target_language': card.targetLanguage,
        'notebook_ids': <String>[],
      },
      CollectionRead.fromJson,
      acceptedStatuses: const {200, 201},
      headers: {...headers, 'Idempotency-Key': idempotencyKey, 'X-Operation-ID': idempotencyKey},
    );
    final collection = response.data;
    if (collection.cardId != card.id || collection.cardRevision != card.revision) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
    return collection;
  }

  Future<PageResponse<CollectionRead>> collections(
    Map<String, String> headers, {
    String? cursor,
  }) => api.getPage(
    '/api/v1/collections?limit=20${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
    CollectionRead.fromJson,
    headers: headers,
  );
}

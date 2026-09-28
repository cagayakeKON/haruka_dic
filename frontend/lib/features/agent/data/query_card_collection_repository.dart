/// The service resolves a committed card by ID and revision before saving it.
/// A query page never supplies card body or owner as the authority for a write.
final class QueryCardSaveRequest {
  QueryCardSaveRequest({
    required this.cardId,
    required this.cardRevision,
    required Set<String> notebookIds,
    this.confirmedTargetLanguage,
  }) : notebookIds = Set.unmodifiable(notebookIds);

  final String cardId;
  final int cardRevision;
  final Set<String> notebookIds;
  final String? confirmedTargetLanguage;
}

enum QueryCardSaveOutcome { saved, alreadySaved }

abstract interface class QueryCardCollectionRepository {
  String? targetLanguage(String cardId, int cardRevision);

  bool isSaved(String cardId, int cardRevision);

  Future<QueryCardSaveOutcome> save(QueryCardSaveRequest request);
}

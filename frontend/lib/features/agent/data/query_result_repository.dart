import '../domain/learning_card.dart';
import '../domain/query_history_entry.dart';
import '../domain/query_request.dart';

/// Query submission resolves a complete, saved learning result.
abstract interface class QueryResultRepository {
  List<QueryHistoryEntry> get history;

  Future<LearningCard> submit(QueryRequest request);

  /// Read an already committed result; never resolves or generates a new one.
  Future<LearningCard> readSaved(String id);
}

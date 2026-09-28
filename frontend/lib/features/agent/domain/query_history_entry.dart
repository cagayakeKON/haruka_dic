import 'learning_card.dart';

/// A completed query shown in the current repository's history.
final class QueryHistoryEntry {
  const QueryHistoryEntry({required this.prompt, required this.card, this.targetLanguage = ''});

  final String prompt;
  final LearningCard card;
  final String targetLanguage;
}

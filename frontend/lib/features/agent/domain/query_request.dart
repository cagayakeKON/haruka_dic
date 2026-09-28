/// Input fields carried to the query resolve/generate boundary.
final class QueryRequest {
  const QueryRequest({
    required this.text,
    this.context = '',
    this.targetLanguage = '',
    this.explanationLanguage = '',
  });

  final String text;
  final String context;
  final String targetLanguage;
  final String explanationLanguage;
}

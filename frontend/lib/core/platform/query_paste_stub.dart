import 'package:haruka/features/agent/application/query_images.dart';
import 'package:haruka/core/platform/query_paste.dart';

QueryPasteSource createQueryPasteSource() => _NoQueryPasteSource();

class _NoQueryPasteSource implements QueryPasteSource {
  @override
  void start({
    required bool Function() canAccept,
    required void Function(List<RawQueryImage>) onImages,
    required void Function(QueryImageProblem) onReadError,
  }) {}

  @override
  void dispose() {}
}

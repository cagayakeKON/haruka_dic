import 'package:haruka/features/agent/application/query_images.dart';

abstract class QueryPasteSource {
  void start({
    required bool Function() canAccept,
    required void Function(List<RawQueryImage>) onImages,
    required void Function(QueryImageProblem) onReadError,
  });

  void dispose();
}

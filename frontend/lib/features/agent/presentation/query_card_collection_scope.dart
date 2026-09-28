import 'package:flutter/widgets.dart';

import '../data/query_card_collection_repository.dart';

class QueryCardCollectionScope extends InheritedWidget {
  const QueryCardCollectionScope({required this.repository, required super.child, super.key});

  final QueryCardCollectionRepository repository;

  static QueryCardCollectionRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QueryCardCollectionScope>()?.repository;

  @override
  bool updateShouldNotify(QueryCardCollectionScope oldWidget) => repository != oldWidget.repository;
}

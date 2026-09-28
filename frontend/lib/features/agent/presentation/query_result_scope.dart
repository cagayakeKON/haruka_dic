import 'package:flutter/widgets.dart';

import '../data/query_result_repository.dart';

class QueryResultScope extends InheritedWidget {
  const QueryResultScope({required this.repository, required super.child, super.key});

  final QueryResultRepository repository;

  static QueryResultRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<QueryResultScope>();
    assert(scope != null, 'QueryResultScope is missing');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(QueryResultScope oldWidget) => repository != oldWidget.repository;
}

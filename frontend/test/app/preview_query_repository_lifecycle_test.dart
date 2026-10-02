import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/agent/data/cached_query_result_repository.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';
import 'package:haruka/features/agent/domain/query_history_entry.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/features/agent/presentation/query_result_scope.dart';

import '../support/preview_test_app.dart';

final class _InjectedQueryRepository extends ChangeNotifier implements QueryResultRepository {
  bool disposed = false;

  @override
  List<QueryHistoryEntry> get history => const [];

  @override
  Future<LearningCard> readSaved(String id) => throw UnimplementedError();

  @override
  Future<LearningCard> submit(QueryRequest request) => throw UnimplementedError();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('preview releases only the query repository it creates', (tester) async {
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PreviewPageFrame).first);
    final owned = QueryResultScope.of(context) as CachedQueryResultRepository;
    await tester.pumpWidget(const SizedBox.shrink());
    await expectLater(
      owned.readSaved('any'),
      throwsA(isA<CacheBlocked>().having((error) => error.reason, 'reason', 'repository_disposed')),
    );

    final injected = _InjectedQueryRepository();
    await tester.pumpWidget(buildTestPreviewApp(queryResultRepository: injected));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(injected.disposed, isFalse);
    injected.dispose();
  });
}

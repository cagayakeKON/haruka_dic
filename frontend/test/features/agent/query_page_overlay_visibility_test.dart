import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/agent/data/cached_query_result_repository.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

class _UnusedResultRemote extends Fake implements CacheRemote<LearningCard> {}

void main() {
  testWidgets('query display pins stay active for a dialog but pause for another page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await tester.runAsync(
      () => cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'query-overlay-test',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      ),
    );
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: _UnusedResultRemote(),
      resolveSource: (_) async => null,
      generateSource: (_) async => throw StateError('no query should be generated'),
    );
    final store = PreviewFixtureStore();
    addTearDown(() async {
      repository.dispose();
      store.dispose();
      await tester.runAsync(cache.closeScope);
    });
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      PreviewStoreScope(
        store: store,
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [PageRouteActivityObserver()],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QueryPage(queryResults: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.isVisible, isTrue);
    expect(tester.takeException(), isNull, reason: 'initial query page');

    final dialog = showDialog<void>(
      context: tester.element(find.byType(QueryPage)),
      builder: (_) => const AlertDialog(title: Text('query dialog')),
    );
    await tester.pumpAndSettle();
    expect(repository.isVisible, isTrue);
    expect(tester.takeException(), isNull, reason: 'dialog open');
    navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(repository.isVisible, isTrue);
    expect(tester.takeException(), isNull, reason: 'dialog close');

    final page = navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('other page'))),
    );
    await tester.pumpAndSettle();
    expect(repository.isVisible, isFalse);
    expect(tester.takeException(), isNull, reason: 'page push');
    navigator.currentState!.pop();
    await page;
    await tester.pumpAndSettle();
    expect(repository.isVisible, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(repository.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
}

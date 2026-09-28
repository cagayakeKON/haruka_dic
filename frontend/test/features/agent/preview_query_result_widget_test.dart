import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/query_prefill.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/dev/preview/fixture_settings_source.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/features/agent/presentation/query_result_scope.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  Future<CachedSettingsRepository> preparedSettings(PreviewFixtureStore store) async {
    final adapter = PreviewSettingsCacheAdapter(
      coordinator: CacheCoordinator(
        openBackend: (_) async {
          final executor = NativeDatabase.memory();
          return OpenedCacheBackend(
            executor: executor,
            mode: CacheStorageMode.memoryOnly,
            closeOwner: executor.close,
          );
        },
      ),
    );
    await adapter.initialize();
    final repository = CachedSettingsRepository(
      cache: adapter.coordinator,
      source: FixtureSettingsSource(store, adapter.coordinator),
    );
    await repository.refresh(SettingsGroup.studyProfile);
    await repository.refresh(SettingsGroup.preferences);
    addTearDown(() async {
      repository.dispose();
      await adapter.coordinator.closeScope();
      adapter.dispose();
    });
    return repository;
  }

  testWidgets('result motion staggers once per query identity and respects reduced motion', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final settings = await preparedSettings(store);
    final first = Object();
    final second = Object();
    Widget result(Object identity) => SettingsRepositoryScope(
      repository: settings,
      child: PreviewStoreScope(
        store: store,
        child: MaterialApp(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: QueryResultCard(
                card: store.cards.first,
                motionIdentity: identity,
                onAgain: () {},
              ),
            ),
          ),
        ),
      ),
    );
    double opacity(String key) =>
        tester.widget<FadeTransition>(find.byKey(ValueKey(key))).opacity.value;

    await tester.pumpWidget(result(first));
    expect(opacity('query-result-main-motion'), 0);
    expect(opacity('query-result-body-motion'), 0);
    expect(opacity('query-result-actions-motion'), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity('query-result-main-motion'), greaterThan(0));
    expect(opacity('query-result-body-motion'), greaterThan(0));
    expect(opacity('query-result-actions-motion'), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity('query-result-actions-motion'), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 160));
    expect(opacity('query-result-main-motion'), 1);
    expect(opacity('query-result-body-motion'), 1);
    expect(opacity('query-result-actions-motion'), 1);

    store.updateAppearance(store.themeMode, false);
    await tester.pump();
    await tester.pumpWidget(result(first));
    expect(opacity('query-result-main-motion'), 1);
    await tester.pumpWidget(result(second));
    expect(opacity('query-result-main-motion'), 0);
    store.updateAppearance(store.themeMode, true);
    await settings.refresh(SettingsGroup.preferences, force: true);
    await tester.pump();
    expect(opacity('query-result-main-motion'), 1);
    expect(opacity('query-result-body-motion'), 1);
    expect(opacity('query-result-actions-motion'), 1);
  });

  testWidgets('query submission jumps to the new result with app reduced motion', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final settings = await preparedSettings(store);
    store.updateAppearance(store.themeMode, true);
    await settings.refresh(SettingsGroup.preferences, force: true);
    for (var index = 0; index < 3; index++) {
      await store.submit(QueryRequest(text: 'そっと $index'));
    }
    await tester.pumpWidget(
      SettingsRepositoryScope(
        repository: settings,
        child: PreviewStoreScope(
          store: store,
          child: MaterialApp(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: QueryPage(queryResults: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: find.byType(MobileQueryView), matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);
    final before = scroll.position.pixels;
    await tester.enterText(find.byType(TextField).first, '新查询');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '新查询');
    await tester.tap(find.text('发送'));
    for (var frame = 0; frame < 6 && store.history.length == 3; frame++) {
      await tester.pump();
    }
    expect(store.history, hasLength(4));
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(before + 20));
    expect(scroll.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpPreview(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
  }

  testWidgets('phone query shows four distinct result structures and starts another query', (
    tester,
  ) async {
    await pumpPreview(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();

    final cases = <(String, String, String)>[
      ('そっと 是什么意思？', '语境例句', '轻轻地；悄悄地'),
      ('翻译：夏の風がそっと頬に触れた。', '译文', '夏风轻轻拂过脸颊。'),
      ('に 和 へ 有什么区别？', '核心用法', '目的地与移动方向'),
      ('批改：昨日、図書館に行きます。', '订正重点', '过去时间需要搭配过去式'),
      ('穏やか', '释义', '平静、温和。常用于形容气氛、心情或天气。'),
    ];
    for (var index = 0; index < cases.length; index++) {
      final (example, section, detail) = cases[index];
      if (index == 0) {
        await tester.tap(find.text(example));
      } else {
        await tester.enterText(find.byType(TextField).first, example);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MobileQueryView>(find.byType(MobileQueryView)).entries.length,
        index + 1,
      );
      expect(find.byType(QueryResultCard), findsWidgets);
      expect(tester.getTopLeft(find.byType(QueryResultCard).last).dy, inInclusiveRange(0, 300));
      expect(find.text(section), findsWidgets);
      expect(find.text(detail), findsOneWidget);
      expect(find.textContaining('本地示例'), findsNothing);
      if (index == 0) {
        final catalog = CollectionCatalogScope.of(
          tester.element(find.byType(QueryResultCard).last),
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, '收藏'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '收藏'));
        await tester.pumpAndSettle();
        expect(find.text('确认收藏'), findsOneWidget);
        final beforeIds = catalog.allCollections.map((item) => item.id).toSet();
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();
        expect(catalog.allCollections.map((item) => item.id).toSet(), beforeIds);
        await tester.tap(find.widgetWithText(FilledButton, '收藏'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(CheckboxListTile, '日常的细节'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认收藏'));
        await tester.pumpAndSettle();
        final saved = catalog.allCollections.singleWhere((item) => !beforeIds.contains(item.id));
        expect(saved.notebookIds, contains('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
        expect(find.widgetWithText(FilledButton, '已收藏'), findsOneWidget);
      }
      await tester.ensureVisible(find.text('再查一个').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('再查一个').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MobileQueryView>(find.byType(MobileQueryView)).entries.length,
        index + 1,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop query uses a separate view and card before the next input', (tester) async {
    await pumpPreview(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(TextButton, '查询').first);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopQueryView), findsOneWidget);
    await tester.tap(find.text('そっと 是什么意思？'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byType(QueryResultCard), findsOneWidget);
    expect(find.text('语境例句'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '收藏'));
    await tester.tap(find.widgetWithText(FilledButton, '收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('确认收藏'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query history returns after leaving for the library', (tester) async {
    await pumpPreview(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('そっと 是什么意思？'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byType(QueryResultCard), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    expect(find.byType(QueryResultCard), findsOneWidget);
    expect(tester.widget<MobileQueryView>(find.byType(MobileQueryView)).entries.length, 1);
    expect(find.text('そっと 是什么意思？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected text stays out of the URL and is cleared after an account switch', (
    tester,
  ) async {
    const selectedText = '昨日、図書館に行きます。';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final adapter = PreviewSettingsCacheAdapter(coordinator: cache);
    await adapter.initialize();
    addTearDown(adapter.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(
                AppRoutes.mockQuery,
                extra: QueryPrefill.capture(cache, selectedText),
              ),
              child: const Text('Open query'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.mockQuery,
          builder: (context, state) => ScopedQueryPage(
            prefill: state.extra is QueryPrefill ? state.extra! as QueryPrefill : null,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      PreviewSettingsCacheScope(
        adapter: adapter,
        child: QueryResultScope(
          repository: store,
          child: PreviewStoreScope(
            store: store,
            child: MaterialApp.router(
              routerConfig: router,
              theme: HarukaTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open query'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(), AppRoutes.mockQuery);
    expect(find.text(selectedText), findsOneWidget);
    expect(find.byType(QueryResultCard), findsNothing);
    expect(store.savedExplanationCount, 0);
    // A reload or direct deep link has no in-memory extra to restore.
    router.go(AppRoutes.mockQuery);
    await tester.pumpAndSettle();
    expect(find.text(selectedText), findsNothing);
    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open query'));
    await tester.pumpAndSettle();
    expect(find.text(selectedText), findsOneWidget);
    await cache.closeScope();
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://haruka.example/api'),
        instanceId: 'instance-2',
        userId: 'another-user',
        audience: 'client',
        sessionRef: 'another-session',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(selectedText), findsNothing);
    expect(router.routeInformationProvider.value.uri.toString(), AppRoutes.mockQuery);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same query with different context resolves distinct saved cards', (
    tester,
  ) async {
    await pumpPreview(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    final store = PreviewStoreScope.of(tester.element(find.byType(MobileQueryView)));

    await tester.tap(find.text('补充上下文（可选）'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'そっと');
    await tester.enterText(find.widgetWithText(TextField, '补充与本次查询有关的上下文'), '小说句子');
    await tester.ensureVisible(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    final firstId = store.lastCard!.id;
    await tester.tap(find.text('再查一个').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'そっと');
    await tester.enterText(find.widgetWithText(TextField, '补充与本次查询有关的上下文'), '教材例句');
    await tester.ensureVisible(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(store.lastCard!.id, isNot(firstId));
    expect(store.savedExplanationCount, 2);
  });
}

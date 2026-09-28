import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/query_prefill.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/features/collections/presentation/collection_detail_page.dart';
import 'package:haruka/features/textbooks/presentation/textbook_practice_page.dart';
import 'package:haruka/features/exams/presentation/exam_result_page.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';

import 'collection_catalog_test_harness.dart';

void main() {
  Future<GoRouter> pumpPage(
    WidgetTester tester,
    PreviewFixtureStore store,
    Widget page,
    Size size, {
    String location = '/',
    List<GoRoute> extraRoutes = const [],
    PreviewSettingsCacheAdapter? settingsCacheAdapter,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/', builder: (context, state) => page),
        ...extraRoutes,
      ],
    );
    addTearDown(router.dispose);
    final harness = await CollectionCatalogTestHarness.create(store);
    addTearDown(harness.close);
    final app = CollectionCatalogScope(
      catalog: harness.catalog,
      child: PreviewStoreScope(
        store: store,
        child: MaterialApp.router(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpWidget(
      settingsCacheAdapter == null
          ? app
          : PreviewSettingsCacheScope(adapter: settingsCacheAdapter, child: app),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<PreviewSettingsCacheAdapter> queryCacheAdapter() async {
    final adapter = PreviewSettingsCacheAdapter(
      coordinator: CacheCoordinator(
        openBackend: (_) async => OpenedCacheBackend(
          executor: NativeDatabase.memory(),
          mode: CacheStorageMode.memoryOnly,
          closeOwner: () async {},
        ),
      ),
    );
    await adapter.initialize();
    addTearDown(adapter.dispose);
    return adapter;
  }

  testWidgets('word detail edits all fields and notebook assignment survives layout change', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final word = store.collections.first;
    await pumpPage(tester, store, WordDetailPage(itemId: word.id), const Size(390, 844));
    expect(find.byType(MobileWordDetailView), findsOneWidget);
    expect(find.byType(DesktopWordDetailView), findsNothing);
    expect(find.text('そっと'), findsOneWidget);

    await tester.tap(find.text('归入单词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '阅读时遇见'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存归类'));
    await tester.pumpAndSettle();
    expect(store.collections.first.notebookIds, hasLength(2));

    await tester.tap(find.text('编辑与笔记'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'そっと新');
    await tester.enterText(fields.at(1), '新的释义');
    await tester.enterText(fields.at(2), '我的笔记');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(store.collections.first.displayText, 'そっと新');
    expect(store.collections.first.meaning, '新的释义');
    expect(store.collections.first.notes, '我的笔记');
    final catalog = CollectionCatalogScope.of(tester.element(find.byType(WordDetailPage)));
    expect(catalog.allCollectionStatus, CollectionCatalogStatus.ready);
    expect(catalog.notebookStatus, CollectionCatalogStatus.ready);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopWordDetailView), findsOneWidget);
    expect(find.byType(MobileWordDetailView), findsNothing);
    expect(find.text('そっと新'), findsOneWidget);
    expect(find.text('阅读时遇见'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('word detail opens as phone sheet and desktop dialog', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final id = store.collections.first.id;
    final launcher = Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showWordDetail(context, id),
            child: const Text('打开词条'),
          ),
        ),
      ),
    );
    await pumpPage(tester, store, launcher, const Size(390, 844));
    await tester.tap(find.text('打开词条'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(WordDetailDialog), findsOneWidget);
    expect(find.text('そっと'), findsOneWidget);
    await tester.tap(find.text('归入单词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '阅读时遇见'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存归类'));
    await tester.pumpAndSettle();
    expect(store.collections.first.notebookIds, hasLength(2));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开词条'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(WordDetailDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone can assign one word to two books then delete only one membership', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final word = store.collections.first;
    final firstBook = store.notebooks[0];
    final secondBook = store.notebooks[1];
    await pumpPage(tester, store, const NotebooksPage(), const Size(390, 844));

    await tester.tap(find.text(word.displayText));
    await tester.pumpAndSettle();
    expect(find.byType(WordDetailDialog), findsOneWidget);
    await tester.tap(find.text('归入单词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, secondBook.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存归类'));
    await tester.pumpAndSettle();
    expect(store.collections.first.notebookIds, {firstBook.id, secondBook.id});
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '全部收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理日常的细节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除词本'));
    await tester.pumpAndSettle();
    expect(find.text('日常的细节 · 2 条收藏'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(store.notebooks, contains(firstBook));

    await tester.tap(find.text('删除词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(store.notebooks, isNot(contains(firstBook)));
    expect(store.collections.first.notebookIds, {secondBook.id});
    expect(store.collections.first.id, word.id);

    await tester.tap(find.widgetWithText(OutlinedButton, '全部收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, secondBook.name));
    await tester.pumpAndSettle();
    expect(find.text(word.displayText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese manual entry can be saved into a Chinese notebook', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final chinese = store.addNotebook('中文随手记', 'zh', '手动整理');
    await pumpPage(
      tester,
      store,
      const NewCollectionPage(),
      const Size(390, 844),
      extraRoutes: [
        GoRoute(path: AppRoutes.mockNotebooks, builder: (_, _) => const NotebooksPage()),
      ],
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, chinese.name), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, chinese.name));
    await tester.enterText(find.byType(TextField).at(0), '清晨');
    await tester.enterText(find.byType(TextField).at(1), '天刚亮的时候');
    await tester.tap(find.widgetWithText(FilledButton, '添加收藏'));
    await tester.pumpAndSettle();

    final saved = store.collections.first;
    expect(saved.displayText, '清晨');
    expect(saved.targetLanguage, 'zh');
    expect(saved.notebookIds, {chinese.id});
    expect(find.text('清晨'), findsOneWidget);
    await tester.tap(find.text('清晨'));
    await tester.pumpAndSettle();
    expect(find.text('单词 · 中文'), findsOneWidget);
    await tester.tap(find.text('归入单词本'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, chinese.name), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '日常的细节'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return to source uses material id even when titles overlap', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final source = store.materials.first;
    store.materials.insert(
      0,
      MaterialSummary(
        id: '99999999-9999-4999-8999-999999999999',
        type: LearningMaterialType.novel,
        title: '手紙',
        language: 'ja',
        status: 'readable',
        revision: 1,
        updatedAt: DateTime.utc(2026, 9, 27),
        description: '',
        cover: '手',
      ),
    );
    await pumpPage(
      tester,
      store,
      WordDetailPage(itemId: store.collections.first.id),
      const Size(390, 844),
      extraRoutes: [
        GoRoute(
          path: '/mock/material/:id',
          builder: (_, state) => Scaffold(body: Text('source:${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.tap(find.text('回到原文 →'));
    await tester.pumpAndSettle();
    expect(find.text('source:${source.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-word collection opens phone sheet and desktop dialog and edits all fields', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final item = store.collections.firstWhere((entry) => entry.kind == CollectionKind.grammar);
    await pumpPage(tester, store, const NotebooksPage(), const Size(390, 844));

    await tester.tap(find.text(item.displayText));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CollectionDetailPage), findsOneWidget);
    await tester.tap(find.text('编辑与笔记'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'に / へ（修订）');
    await tester.enterText(fields.at(1), '目标和方向');
    await tester.enterText(fields.at(2), '教材例句');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final edited = store.collections.firstWhere((entry) => entry.id == item.id);
    expect(edited.displayText, 'に / へ（修订）');
    expect(edited.meaning, '目标和方向');
    expect(edited.notes, '教材例句');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('に / へ（修订）'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(CollectionDetailPage), findsOneWidget);
    expect(find.text('目标和方向'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice selection, feedback and retry stay in one attempt across resize', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await pumpPage(tester, store, const TextbookPracticePage(), const Size(390, 844));
    expect(find.byType(MobileTextbookPracticeView), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认答案')).onPressed,
      isNull,
    );
    await tester.tap(find.text('表示移动方向'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认答案'));
    await tester.pumpAndSettle();
    expect(find.text('这题选 A'), findsOneWidget);
    expect(find.text('「は」提示句子的话题。'), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTextbookPracticeView), findsOneWidget);
    expect(find.text('这题选 A'), findsOneWidget);
    await tester.tap(find.text('重新作答'));
    await tester.pumpAndSettle();
    expect(find.text('这题选 A'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认答案')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop practice breadcrumb returns to the current textbook unit', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final textbookId = store.materials
        .firstWhere((item) => item.type == LearningMaterialType.textbook)
        .id;
    final router = GoRouter(
      initialLocation: '${AppRoutes.mockMaterialPath(textbookId)}?unit=2',
      routes: [
        GoRoute(
          path: '/mock/material/:id',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                Text('课本 Unit ${state.uri.queryParameters['unit']}'),
                TextButton(
                  onPressed: () => context.push('${AppRoutes.mockTextbookPractice}?unit=2'),
                  child: const Text('打开练习'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.mockTextbookPractice,
          builder: (context, state) => const TextbookPracticePage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      PreviewStoreScope(
        store: store,
        child: MaterialApp.router(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开练习'));
    await tester.pumpAndSettle();
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '课本学习'));
    await tester.pumpAndSettle();
    expect(find.text('课本 Unit 2'), findsOneWidget);

    router.go('${AppRoutes.mockTextbookPractice}?unit=3');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '课本学习'));
    await tester.pumpAndSettle();
    expect(find.text('课本 Unit 3'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['unit'], '3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice bookmark stores only visible answer projection', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await pumpPage(tester, store, const TextbookPracticePage(), const Size(390, 844));
    await tester.tap(find.text('收藏题目'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '日常的细节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认收藏'));
    await tester.pumpAndSettle();
    final saved = store.collections.first;
    expect(saved.kind, CollectionKind.exercise);
    expect(saved.displayText, '「わたしは学生です」中的「は」有什么作用？');
    expect(saved.meaning, isEmpty);
    expect(saved.notebookIds, contains(store.notebooks.first.id));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unit 02 has its own options, feedback, bookmark and retains attempt on resize', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final router = await pumpPage(
      tester,
      store,
      const TextbookPracticePage(),
      const Size(390, 844),
      location: '/?unit=2',
    );
    expect(find.byType(MobileTextbookPracticeView), findsOneWidget);
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    expect(find.text('「駅へ行きます」中的「へ」主要表示什么？'), findsOneWidget);
    expect(find.text('动作对象'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认答案')).onPressed,
      isNull,
    );
    await tester.tap(find.text('动作对象'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认答案'));
    await tester.pumpAndSettle();
    expect(find.text('这题选 A'), findsOneWidget);
    expect(find.text('「へ」标示移动的方向。'), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTextbookPracticeView), findsOneWidget);
    expect(find.text('这题选 A'), findsOneWidget);
    expect(tester.getSize(find.text('移动方向')).height, greaterThan(23));
    await tester.tap(find.text('收藏题目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认收藏'));
    await tester.pumpAndSettle();
    final saved = store.collections.first;
    expect(saved.displayText, '「駅へ行きます」中的「へ」主要表示什么？');
    expect(saved.meaning, '「へ」标示移动的方向。');

    router.go('/?unit=3');
    await tester.pumpAndSettle();
    expect(find.text('Unit 03 · 在咖啡馆'), findsOneWidget);
    expect(find.text('这题选 A'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认答案')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unit 03 question and correct explanation stay distinct across phone layout', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await pumpPage(
      tester,
      store,
      const TextbookPracticePage(),
      const Size(1440, 900),
      location: '/?unit=3',
    );
    expect(find.text('在咖啡馆点餐时，「ください」通常表达什么？'), findsOneWidget);
    expect(find.text('请给我'), findsOneWidget);
    expect(find.text('欢迎回来'), findsOneWidget);
    await tester.tap(find.text('请给我'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '确认答案'));
    await tester.pumpAndSettle();
    expect(find.text('回答正确'), findsOneWidget);
    expect(find.text('「ください」在这里表达礼貌请求。'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MobileTextbookPracticeView), findsOneWidget);
    expect(find.text('回答正确'), findsOneWidget);
    await tester.tap(find.text('重新作答'));
    await tester.pumpAndSettle();
    expect(find.text('回答正确'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认答案')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exam result scores submitted answers and bookmarks review content', (tester) async {
    final store = PreviewFixtureStore()..submitExam({0: 1, 1: 1, 2: 1});
    addTearDown(store.dispose);
    await pumpPage(tester, store, const ExamResultPage(), const Size(390, 844));
    expect(find.byType(MobileExamResultView), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('你的选择：迅速猛烈'), findsOneWidget);
    expect(find.text('参考答案：平静温和'), findsOneWidget);

    await tester.tap(find.text('收藏题目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认收藏'));
    await tester.pumpAndSettle();
    final saved = store.collections.first;
    expect(saved.kind, CollectionKind.exercise);
    expect(saved.displayText, '「穏やか」に最接近的意思是？');
    expect(saved.meaning, '参考答案：平静温和');
    expect(saved.context, contains('A. 平静温和'));
    expect(saved.context, contains('B. 迅速猛烈'));
    expect(saved.notes, contains('你的选择：迅速猛烈'));
    expect(saved.notes, contains('参考答案：平静温和'));

    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('收藏题目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认收藏'));
    await tester.pump();
    expect(store.collections.where((item) => item.id == saved.id), hasLength(1));
    expect(find.text('已收藏此题'), findsOneWidget);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamResultView), findsOneWidget);
    expect(find.byType(MobileExamResultView), findsNothing);
    expect(find.text('需要回看的题目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exam result hides answers before submitted attempt', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await pumpPage(tester, store, const ExamResultPage(), const Size(390, 844));
    expect(find.text('交卷后答卷锁定，才可查看参考答案与复盘。'), findsOneWidget);
    expect(find.text('参考答案：平静温和'), findsNothing);
    expect(find.byType(MobileExamResultView), findsNothing);
    expect(find.byType(MobileExamSelectionPopover), findsNothing);
    expect(find.text('收藏题目'), findsNothing);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamResultView), findsNothing);
    expect(find.byType(DesktopExamSelectionPopover), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitted phone review supports long press, speaker and selected text query', (
    tester,
  ) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    addTearDown(store.dispose);
    final settingsCacheAdapter = await queryCacheAdapter();
    final initialCollections = store.collections.length;
    await pumpPage(
      tester,
      store,
      const ExamResultPage(),
      const Size(390, 844),
      settingsCacheAdapter: settingsCacheAdapter,
      extraRoutes: [
        GoRoute(
          path: AppRoutes.mockQuery,
          builder: (context, state) => Scaffold(
            body: Text(
              'query:${(state.extra as QueryPrefill?)?.read(settingsCacheAdapter.coordinator)}',
            ),
          ),
        ),
      ],
    );
    final promptRect = tester.getRect(find.text('「穏やか」に最接近的意思是？'));
    await tester.longPress(find.text('「穏やか」に最接近的意思是？'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamSelectionPopover), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    final popoverRect = tester.getRect(find.byType(MobileExamSelectionPopover));
    expect(popoverRect.top, lessThanOrEqualTo(promptRect.bottom + 20));
    expect(popoverRect.bottom, lessThanOrEqualTo(844 - 12));
    expect(
      tester.getRect(find.widgetWithText(FilledButton, '查询')).bottom,
      lessThanOrEqualTo(popoverRect.bottom),
    );
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .any((barrier) => (barrier.color?.a ?? 0) == 0),
      isTrue,
    );
    expect(find.text('选句学习'), findsOneWidget);
    final expectedBubbles = ['穏やか', 'に', '最', '接近', '的', '意思', '是'];
    for (var index = 0; index < expectedBubbles.length; index++) {
      final bubble = tester.widget<FilterChip>(find.byKey(ValueKey('exam-selection-token-$index')));
      expect((bubble.label as Text).data, expectedBubbles[index]);
    }

    await tester.tap(find.byTooltip('朗读整句'));
    await tester.pumpAndSettle();
    expect(find.text('音频暂不可用'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exam-selection-token-0')));
    await tester.pumpAndSettle();
    expect(find.text('收藏选中文字'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(find.text('query:穏やか'), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.text('query:穏やか'))).routeInformationProvider.value.uri.query,
      isEmpty,
    );
    expect(store.collections.length, initialCollections);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitted desktop review queries selected text and returns to exam prep', (
    tester,
  ) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    addTearDown(store.dispose);
    final settingsCacheAdapter = await queryCacheAdapter();
    final examId = store.materials.firstWhere((item) => item.type == LearningMaterialType.exam).id;
    final router = await pumpPage(
      tester,
      store,
      const ExamResultPage(),
      const Size(1440, 900),
      settingsCacheAdapter: settingsCacheAdapter,
      extraRoutes: [
        GoRoute(
          path: AppRoutes.mockQuery,
          builder: (context, state) => Scaffold(
            body: Text(
              'query:${(state.extra as QueryPrefill?)?.read(settingsCacheAdapter.coordinator)}',
            ),
          ),
        ),
        GoRoute(
          path: '/mock/material/:id',
          builder: (context, state) => Scaffold(body: Text('prep:${state.pathParameters['id']}')),
        ),
      ],
    );
    expect(find.text('试卷准备'), findsOneWidget);
    await tester.tap(find.text('「穏やか」に最接近的意思是？'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamSelectionPopover), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    final desktopPopover = tester.getRect(find.byType(DesktopExamSelectionPopover));
    final desktopPrompt = tester.getRect(find.text('「穏やか」に最接近的意思是？'));
    expect(desktopPopover.top, greaterThanOrEqualTo(desktopPrompt.bottom));
    expect(desktopPopover.top, lessThanOrEqualTo(desktopPrompt.bottom + 20));
    expect(desktopPopover.bottom, lessThanOrEqualTo(900 - 12));
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(find.text('query:「穏やか」に最接近的意思是？'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.query, isEmpty);
    router.pop();
    await tester.pumpAndSettle();
    await tester.longPress(find.text('「穏やか」に最接近的意思是？'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamSelectionPopover), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exam-selection-token-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(find.text('query:穏やか'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('试卷准备'));
    await tester.pumpAndSettle();
    expect(find.text('prep:$examId'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitted phone review back control returns to exam preparation', (tester) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    addTearDown(store.dispose);
    final examId = store.materials.firstWhere((item) => item.type == LearningMaterialType.exam).id;
    await pumpPage(
      tester,
      store,
      const ExamResultPage(),
      const Size(390, 844),
      extraRoutes: [
        GoRoute(
          path: '/mock/material/:id',
          builder: (context, state) => Scaffold(body: Text('prep:${state.pathParameters['id']}')),
        ),
      ],
    );
    expect(find.byType(MobileExamResultView), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('prep:$examId'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exam review selection range rejects reversed boundaries', (tester) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    addTearDown(store.dispose);
    await pumpPage(tester, store, const ExamResultPage(), const Size(390, 844));
    await tester.longPress(find.text('「穏やか」に最接近的意思是？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整范围'));
    await tester.pumpAndSettle();

    Future<void> chooseBoundary(String key, int value) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      final menuItem = find
          .byWidgetPredicate((widget) => widget is DropdownMenuItem<int> && widget.value == value)
          .last;
      await tester.tap(find.descendant(of: menuItem, matching: find.byType(Text)).last);
      await tester.pumpAndSettle();
    }

    await chooseBoundary('exam-selection-start', 4);
    await chooseBoundary('exam-selection-end', 2);
    expect(find.text('终点需要在起点之后'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '查询')).onPressed, isNull);
    await chooseBoundary('exam-selection-end', 6);
    expect(find.text('」に'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '查询')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exam review selection limits non-adjacent token groups to three', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await pumpPage(
      tester,
      store,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGeneralDialog<Object?>(
              context: context,
              pageBuilder: (_, animation, secondaryAnimation) => const Stack(
                children: [
                  Positioned(
                    left: 20,
                    top: 100,
                    width: 340,
                    child: MobileExamSelectionPopover(text: 'a b c d e f g'),
                  ),
                ],
              ),
            ),
            child: const Text('open selection'),
          ),
        ),
      ),
      const Size(390, 844),
    );
    await tester.tap(find.text('open selection'));
    await tester.pumpAndSettle();
    for (final index in [0, 2, 4, 6]) {
      await tester.tap(find.byKey(ValueKey('exam-selection-token-$index')));
      await tester.pumpAndSettle();
    }
    expect(find.text('每次最多查询 3 组，请减少选择'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '查询')).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('exam-selection-token-6')));
    await tester.pumpAndSettle();
    expect(find.text('a / c / e'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '查询')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}

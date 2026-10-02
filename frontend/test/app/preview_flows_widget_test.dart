import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/ai_exercises/presentation/exercise_pages.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/features/textbooks/presentation/textbook_practice_page.dart';
import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/fixture_material_remote.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/library/data/cached_material_catalog.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

class _CountingMaterialRemote implements CacheRemote<List<MaterialSummary>> {
  _CountingMaterialRemote(this.delegate);

  final FixtureMaterialRemote delegate;
  int requests = 0;

  @override
  Future<CachePayload<List<MaterialSummary>>> fetch(CacheResource resource, CancelToken cancel) {
    requests++;
    return delegate.fetch(resource, cancel);
  }

  @override
  Future<CacheValidation> validate(CacheResource resource, CacheVersion known, CancelToken cancel) {
    requests++;
    return delegate.validate(resource, known, cancel);
  }
}

void main() {
  setUpAll(initializeTestDatabase);
  Future<void> pumpMock(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
  }

  PreviewFixtureStore currentStore(WidgetTester tester) =>
      PreviewStoreScope.of(tester.element(find.byType(PreviewPageFrame).first));

  testWidgets('mobile library filters, searches, and resets empty result', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    expect(find.byType(MobileLibraryView), findsOneWidget);
    expect(find.byType(DesktopLibraryView), findsNothing);
    expect(find.text('4 份材料'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    expect(find.text('任务进度'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    await tester.tap(find.text('小说').first);
    await tester.pumpAndSettle();
    expect(find.text('2 份材料'), findsNothing);

    await tester.tap(find.byTooltip('搜索材料'));
    await tester.pumpAndSettle();
    final search = find.byType(TextField).first;
    await tester.tap(search);
    final searchElement = tester.element(search);
    for (final value in ['不', '不存', '不存在']) {
      tester.testTextInput.enterText(value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.element(search), same(searchElement));
      expect(
        tester.widget<EditableText>(find.byType(EditableText).first).focusNode.hasFocus,
        isTrue,
      );
    }
    tester.testTextInput.enterText('不存在的材料');
    await tester.pumpAndSettle();
    expect(tester.element(search), same(searchElement));
    expect(find.text('没有匹配的材料'), findsOneWidget);
    await tester.tap(find.text('重置筛选'));
    await tester.pumpAndSettle();
    expect(find.text('4 份材料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile root header honors one system top inset', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 52);
    addTearDown(tester.view.resetPadding);
    await pumpMock(tester, const Size(390, 844));
    final logoTop = tester.getTopLeft(find.text('h')).dy;
    expect(logoTop, greaterThanOrEqualTo(52));
    expect(logoTop, lessThan(68));
  });

  testWidgets('mobile material delete requires confirmation', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    final store = currentStore(tester);
    await tester.tap(find.byTooltip('夏の手紙更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(find.text('材料操作'), findsNothing);
    expect(find.byType(HarukaDialogSurface), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('删除材料'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(HarukaDialogSurface), findsOneWidget);
    expect(find.text('删除材料？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.materials, hasLength(4));

    await tester.tap(find.byTooltip('夏の手紙更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除', skipOffstage: false).last);
    await tester.pumpAndSettle();
    expect(store.materials, hasLength(3));
    expect(find.text('3 份材料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile material menu stays under its trigger and closes on outside tap', (
    tester,
  ) async {
    await pumpMock(tester, const Size(390, 844));
    final trigger = find.byTooltip('夏の手紙更多操作');
    expect(tester.getSize(trigger), const Size(48, 48));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final menuItem = find.byType(MenuItemButton).first;
    expect(tester.getTopLeft(menuItem).dy, greaterThanOrEqualTo(tester.getBottomLeft(trigger).dy));
    expect(find.byType(HarukaDialogSurface), findsNothing);
    await tester.tapAt(const Offset(12, 200));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(HarukaDialogSurface), findsNothing);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(MobileLibraryView), findsOneWidget);
  });

  testWidgets('mobile material details use a centered dialog with the same opening route', (
    tester,
  ) async {
    await pumpMock(tester, const Size(390, 844));
    final materialId = currentStore(tester).materials.first.id;
    final router = GoRouter.of(tester.element(find.byType(LibraryPage)));
    await tester.tap(find.byTooltip('夏の手紙更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(HarukaDialogSurface), findsNothing);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    final dialog = find.byType(HarukaDialogSurface);
    expect(dialog, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getCenter(dialog).dy, closeTo(422, 24));
    expect(find.text('一封从夏日海边寄来的信，慢慢连接起两个人的故事。'), findsOneWidget);
    await tester.tap(find.text('打开材料'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.mockMaterialPath(materialId));
  });

  testWidgets('mobile menu opens details through the gated cached catalog', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = _CountingMaterialRemote(FixtureMaterialRemote(store));
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: memoryTestDatabase(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final catalog = CachedMaterialCatalog(
      cache: cache,
      remote: remote,
      importSource: (type, title, language) async => store.importMaterial(type, title, language),
      deleteSource: (id) async => store.deleteMaterial(id),
    );
    await tester.runAsync(
      () => cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'preview-test',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      ),
    );
    await tester.runAsync(() => catalog.refresh());
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    final card = find.byType(MobileMaterialCard).first;
    final cardElement = tester.element(card);
    final requestsBeforeMenu = remote.requests;
    await tester.tap(find.byTooltip('夏の手紙更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(catalog.status, MaterialCatalogStatus.ready);
    expect(tester.element(card), same(cardElement));
    expect(remote.requests, requestsBeforeMenu);

    await tester.tapAt(const Offset(12, 200));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(tester.element(card), same(cardElement));
    expect(remote.requests, requestsBeforeMenu);
    expect(find.text('夏の手紙'), findsOneWidget);

    await tester.tap(find.byTooltip('夏の手紙更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.byType(HarukaDialogSurface), findsOneWidget);
    expect(find.text('材料已删除或不可读取'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => cache.closeScope());
  });

  testWidgets('mobile navigation opens notebook and chooser dialog', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '词本'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileNotebooksView), findsOneWidget);
    expect(find.text('6 条收藏'), findsOneWidget);
    await tester.tap(find.text('全部收藏').first);
    await tester.pumpAndSettle();
    expect(find.text('切换与管理词本'), findsOneWidget);
    await tester.tap(find.text('阅读时遇见'));
    await tester.pumpAndSettle();
    expect(find.text('1 条收藏'), findsOneWidget);
    expect(find.text('微笑む'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile notebook keeps search text after its filtered list refreshes', (
    tester,
  ) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索收藏内容'));
    await tester.pumpAndSettle();
    final search = find.byType(TextField).first;
    await tester.tap(search);
    final searchElement = tester.element(search);
    for (final value in ['g', 'gl', 'gli']) {
      tester.testTextInput.enterText(value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.element(search), same(searchElement));
      expect(tester.widget<TextField>(search).controller?.text, value);
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
    }
    await tester.pumpAndSettle();
    for (final value in ['glim', 'glimm', 'glimme', 'glimmer']) {
      tester.testTextInput.enterText(value);
      await tester.pump();
      expect(tester.element(search), same(searchElement));
      expect(tester.widget<TextField>(search).controller?.text, value);
    }
    await tester.pumpAndSettle();
    expect(find.text('1 条收藏'), findsOneWidget);
    expect(tester.element(search), same(searchElement));
    expect(tester.widget<TextField>(search).controller?.text, 'glimmer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile collection source closes its sheet before opening the material', (
    tester,
  ) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('に / へ'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('回到原文 →'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(MaterialEntryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop collection source closes its dialog before opening the material', (
    tester,
  ) async {
    await pumpMock(tester, const Size(1440, 900));
    GoRouter.of(tester.element(find.byType(PreviewPageFrame).first)).go(AppRoutes.mockNotebooks);
    await tester.pumpAndSettle();
    await tester.tap(find.text('に / へ'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('回到原文 →'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(MaterialEntryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query example, context and result change without leaving page', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileQueryView), findsOneWidget);
    await tester.tap(find.text('补充上下文（可选）'));
    await tester.pumpAndSettle();
    expect(find.text('补充与本次查询有关的上下文'), findsOneWidget);
    await tester.tap(find.text('に 和 へ 有什么区别？'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '输入单词、句子、语法问题，或添加图片…'), findsOneWidget);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byType(QueryResultCard), findsOneWidget);
    expect(find.text('に / へ'), findsOneWidget);
    expect(currentStore(tester).savedExplanationCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice submission keeps chosen answer until reset', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '练习'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExerciseView), findsOneWidget);
    await tester.tap(find.text('语境中的表达'));
    await tester.pumpAndSettle();
    expect(find.byType(PracticePage), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '提交答案')).onPressed,
      isNull,
    );
    await tester.tap(find.text('B  きっと'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交答案'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正确答案是「そっと」'), findsOneWidget);
    expect(currentStore(tester).selectedAnswer, 1);
    await tester.tap(find.text('重做'));
    await tester.pumpAndSettle();
    expect(currentStore(tester).selectedAnswer, isNull);
    expect(find.textContaining('正确答案是「そっと」'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop library keeps filter state through compact and wide resize', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    expect(find.byType(DesktopLibraryView), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.widgetWithText(HarukaPill, '课本'));
    await tester.pumpAndSettle();
    expect(find.text('1 份材料'), findsNothing);
    expect(find.text('日语的日常表达'), findsOneWidget);
    expect(find.text('夏の手紙'), findsNothing);
    tester.view.physicalSize = const Size(760, 900);
    await tester.pumpAndSettle();
    expect(find.byType(MobileLibraryView), findsOneWidget);
    await tester.tap(find.byTooltip('搜索材料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '日语');
    await tester.pumpAndSettle();
    expect(find.text('1 份材料'), findsNothing);
    expect(find.text('日语的日常表达'), findsOneWidget);
    expect(find.text('夏の手紙'), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MobileLibraryView), findsOneWidget);
    expect(find.text('1 份材料'), findsNothing);
    expect(find.text('日语的日常表达'), findsOneWidget);
    expect(find.text('夏の手紙'), findsNothing);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopLibraryView), findsOneWidget);
    expect(find.text('1 份材料'), findsNothing);
    expect(find.text('日语的日常表达'), findsOneWidget);
    expect(find.text('夏の手紙'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop navigation opens distinct query and settings views', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(
      find.descendant(of: find.byType(PreviewSideNavigation), matching: find.byTooltip('查询')).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopQueryView), findsOneWidget);
    expect(find.byType(MobileQueryView), findsNothing);
    await tester.tap(
      find.descendant(of: find.byType(PreviewSideNavigation), matching: find.byTooltip('我的')).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsView), findsOneWidget);
    expect(find.byType(MobileSettingsView), findsNothing);
    await tester.tap(find.text('本机缓存'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsDetail), findsOneWidget);
    expect(find.text('本机空间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile import wizard requires a file and keeps type and AI choice', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: memoryTestDatabase(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final catalog = CachedMaterialCatalog(
      cache: cache,
      remote: FixtureMaterialRemote(store),
      importSource: (type, title, language) async => store.importMaterial(type, title, language),
      deleteSource: (id) async => store.deleteMaterial(id),
    );
    addTearDown(() async {
      catalog.dispose();
      await tester.runAsync(() => cache.closeScope());
    });
    await tester.runAsync(
      () => cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'preview-test',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      ),
    );
    await tester.runAsync(() => catalog.refresh());
    final router = GoRouter(
      initialLocation: AppRoutes.mockImport,
      routes: [
        GoRoute(
          path: AppRoutes.mockImport,
          builder: (context, state) => ImportPage(pickFileName: () async => '新的故事.epub'),
        ),
        GoRoute(path: AppRoutes.mockLibrary, builder: (context, state) => const LibraryPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialCatalogScope(
        catalog: catalog,
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
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsOneWidget);
    expect(find.byType(MobileImportView), findsOneWidget);
    expect(find.text('1 / 3 · 小说'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3 · 小说'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed, isNull);
    await tester.tap(find.text('选择材料文件'));
    await tester.pumpAndSettle();
    expect(find.text('已选文件：新的故事.epub'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3 · 小说'), findsOneWidget);
    expect(find.text('新的故事.epub'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('已选文件：新的故事.epub'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入').last);
    await tester.pumpAndSettle();
    expect(store.materials.first.title, '新的故事');
    expect(store.materials.first.status, 'processing');
    expect(find.text('5 份材料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notebook editor creates a notebook and rejects duplicate name', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    final store = currentStore(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, '词本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部收藏').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建词本'));
    await tester.pumpAndSettle();
    final nameField = find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(nameField, '日常的细节');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('名称不能为空或与现有词本重复'), findsOneWidget);
    expect(store.notebooks, hasLength(3));

    await tester.enterText(nameField, '旅行表达');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notebooks.last.name, '旅行表达');
    expect(store.notebooks, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache clear dialog preserves saved result after confirmation', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    final store = currentStore(tester);
    store.runQuery('そっと');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('本机缓存'), 260);
    await tester.pumpAndSettle();
    await tester.tap(find.text('本机缓存'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsDetail), findsOneWidget);
    expect(find.text('1 份解释 · 0 段音频'), findsOneWidget);
    await tester.tap(find.text('清除此账号本机缓存'));
    await tester.pumpAndSettle();
    expect(find.text('清除此账号本机缓存？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.localExplanationCount, 1);
    await tester.tap(find.text('清除此账号本机缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    expect(store.localExplanationCount, 0);
    expect(store.savedExplanationCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop notebook filters collection kind and opens details', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(
      find
          .descendant(of: find.byType(PreviewSideNavigation), matching: find.byTooltip('单词本'))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNotebooksView), findsOneWidget);
    await tester.tap(find.widgetWithText(HarukaPill, '语法'));
    await tester.pumpAndSettle();
    expect(find.text('1 条收藏'), findsOneWidget);
    await tester.tap(find.text('に / へ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('目的地与移动方向'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop notebook search accepts continued keyboard input', (tester) async {
    await pumpMock(tester, const Size(760, 900));
    await tester.tap(
      find
          .descendant(of: find.byType(PreviewSideNavigation), matching: find.byTooltip('单词本'))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索收藏内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    for (final value in ['g', 'gl', 'gli']) {
      tester.testTextInput.enterText(value);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text, value);
      expect(tester.widget<TextField>(find.byType(TextField).first).focusNode?.hasFocus, isTrue);
    }
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('glimmer');
    await tester.pumpAndSettle();
    expect(find.text('1 条收藏'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text, 'glimmer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop notebook keeps long names and readings usable', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CollectionKind? selectedKind;
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    final searchFocusNode = FocusNode();
    addTearDown(searchFocusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DesktopNotebooksView(
            items: [
              CollectionEntry(
                id: 'long-word',
                kind: CollectionKind.word,
                displayText: 'ことばをたくさん集めた長い表現の見出し',
                targetLanguage: 'ja',
                reading: 'ことばをたくさんあつめたながいひょうげんのみだし',
                meaning: '很长的示例释义，用来检查窄桌面上的词条仍能打开',
                createdAt: DateTime.utc(2026, 9, 27),
              ),
            ],
            kind: null,
            selectedName: '在日语阅读中反复收集的长名称个人单词本',
            searchController: searchController,
            searchFocusNode: searchFocusNode,
            onType: (value) => selectedKind = value,
            onQuery: (_) {},
            onNotebook: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(HarukaPill, '单词'));
    expect(selectedKind, CollectionKind.word);
    expect(tester.takeException(), isNull);
  });

  testWidgets('novel preparation rejects an empty AI and audio selection', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.text('夏の手紙'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileNovelView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('准备本章'));
    await tester.pumpAndSettle();
    expect(find.text('缓存内容 · 可多选'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始准备')).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始准备')).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('开始准备'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1/5 句本机就绪'), findsOneWidget);
    await tester.tap(find.text('暂停准备'));
    await tester.pumpAndSettle();
    expect(find.text('已暂停，已完成内容保留。'), findsOneWidget);
    await tester.tap(find.text('继续准备'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('本章准备完成'), findsOneWidget);
    expect(find.text('已暂停，已完成内容保留。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sentence panel keeps the novel reading surface wide', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(find.text('夏の手紙'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    final reader = find
        .ancestor(of: find.text('第 3 章 / 12 章'), matching: find.byType(HarukaSurface))
        .first;
    final originalWidth = tester.getSize(reader).width;
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('句子解析'), findsOneWidget);
    final selectedWidth = tester.getSize(reader).width;
    expect(selectedWidth, greaterThan(700));
    expect(selectedWidth, lessThan(originalWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile novel analysis shows ruby and sentence sheet keeps navigation and collection',
    (tester) async {
      await pumpMock(tester, const Size(390, 844));
      final store = currentStore(tester);
      final before = store.collections.length;
      await tester.tap(find.text('夏の手紙'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '解析'));
      await tester.pumpAndSettle();
      expect(find.byType(RubySentence), findsNWidgets(5));
      await tester.tap(
        find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SentenceDialog), findsOneWidget);
      expect(find.text('第 1 / 5 句'), findsOneWidget);
      await tester.tap(find.text('下一句'));
      await tester.pumpAndSettle();
      expect(find.text('打开窗户，夏风轻轻拂过脸颊。'), findsOneWidget);
      await tester.ensureVisible(find.text('收藏').last);
      await tester.tap(find.text('收藏').last);
      await tester.pumpAndSettle();
      expect(store.collections.length, before + 1);
      expect(find.text('已收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile textbook opens the first unit and its content sheet', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.text('日语的日常表达'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPage), findsOneWidget);
    expect(find.text('单元目录'), findsOneWidget);
    expect(find.text('3 个可用单元'), findsOneWidget);
    await tester.tap(find.text('初次见面'));
    await tester.pumpAndSettle();
    expect(find.text('Unit 01 · 初次见面'), findsOneWidget);
    expect(find.text('会话与课文'), findsOneWidget);
    await tester.tap(find.text('会话：よろしくお願いします'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileTextbookTopicSheet), findsOneWidget);
    expect(find.text('出处：Unit 01 · 初次见面'), findsOneWidget);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileTextbookTopicSheet), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('单元目录'), findsOneWidget);
    await tester.tap(find.text('一起去车站'));
    await tester.pumpAndSettle();
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在咖啡馆'));
    await tester.pumpAndSettle();
    expect(find.text('Unit 03 · 在咖啡馆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('textbook unit deep link opens Unit 02 on phone and desktop', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    final store = currentStore(tester);
    final router = GoRouter.of(tester.element(find.byType(LibraryPage)));
    final textbookPath = AppRoutes.mockMaterialPath(store.materials[1].id);
    router.go('$textbookPath?unit=2');
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPage), findsOneWidget);
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    expect(find.text('课文：駅までの道'), findsOneWidget);
    expect(find.text('课后练习：4 题'), findsOneWidget);
    await tester.tap(find.text('课文：駅までの道'));
    await tester.pumpAndSettle();
    expect(find.text('駅まで一緒に行きましょう。'), findsOneWidget);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('词汇：方向与交通'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookVocabularyWord), findsOneWidget);
    expect(find.text('駅'), findsOneWidget);
    expect(find.text('右'), findsNothing);
    expect(find.byTooltip('朗读駅'), findsOneWidget);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语法：に / へ'));
    await tester.pumpAndSettle();
    expect(find.text('「へ」表示移动的方向。'), findsOneWidget);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    expect(find.text('词汇：方向与交通'), findsOneWidget);
    await tester.tap(find.text('词汇：方向与交通'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookVocabularyWord), findsNWidgets(3));
    expect(find.text('右'), findsNWidgets(2));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语法：に / へ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('「へ」表示移动方向。'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    router.go(textbookPath);
    await tester.pumpAndSettle();
    expect(find.text('Unit 01 · 初次见面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unit 03 uses distinct phone and desktop topics with a direct exercise link', (
    tester,
  ) async {
    await pumpMock(tester, const Size(390, 844));
    final store = currentStore(tester);
    final router = GoRouter.of(tester.element(find.byType(LibraryPage)));
    router.go('${AppRoutes.mockMaterialPath(store.materials[1].id)}?unit=3');
    await tester.pumpAndSettle();
    expect(find.text('Unit 03 · 在咖啡馆'), findsOneWidget);
    expect(find.text('会话：注文をお願いします'), findsOneWidget);
    expect(find.text('例句与译文'), findsOneWidget);
    await tester.tap(find.text('会话：注文をお願いします'));
    await tester.pumpAndSettle();
    expect(find.text('コーヒーを一つください。'), findsOneWidget);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('例句与译文'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookVocabularyWord), findsOneWidget);
    expect(find.text('注文'), findsOneWidget);
    expect(find.text('水'), findsNothing);
    await tester.tap(find.byTooltip('朗读注文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(TextbookPlaybackPanel), findsOneWidget);
    expect(find.text('播放中'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      greaterThan(0),
    );
    await tester.tap(find.widgetWithText(TextButton, '暂停'));
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.2×').last);
    await tester.pumpAndSettle();
    expect(find.text('1.2×'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '继续'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('播放中'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '停止'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPlaybackPanel), findsNothing);
    await tester.tap(find.text('回到单元'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.text('Unit 03 · 在咖啡馆'), findsOneWidget);
    await tester.tap(find.text('例句与译文'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookVocabularyWord), findsNWidgets(3));
    expect(find.text('コーヒー'), findsOneWidget);
    await tester.tap(find.byTooltip('朗读コーヒー'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TextbookPlaybackPanel), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '停止'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语法：ください'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ケーキをください。'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课后练习：3 题'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPracticePage), findsOneWidget);
    expect(find.textContaining('「ください」通常表达什么？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile exam script confirmation requires an explicit checked match', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await tester.tap(find.text('N2 模拟试卷'));
    await tester.pumpAndSettle();
    expect(find.byType(ExamPrepPage), findsOneWidget);
    await tester.tap(find.text('校对听力稿'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamScriptReviewSheet), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认候选匹配')).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认候选匹配')).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('确认候选匹配'));
    await tester.pumpAndSettle();
    expect(find.text('已确认脚本与题组'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop textbook uses unit navigation and a centered topic dialog', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(find.text('日语的日常表达'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPage), findsOneWidget);
    expect(find.text('Unit 01 · 初次见面'), findsOneWidget);
    await tester.tap(find.text('会话：よろしくお願いします'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTextbookTopicDialog), findsOneWidget);
    expect(find.textContaining('请多关照。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop exam candidate dialog keeps confirmation gated', (tester) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(find.text('N2 模拟试卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校对听力候选'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamScriptReviewDialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认匹配')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

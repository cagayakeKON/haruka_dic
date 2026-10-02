import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/features/library/presentation/material_catalog_access.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'material_catalog_widget_test.mocks.dart';

@GenerateNiceMocks([MockSpec<MaterialCatalog>()])
void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('a dialog leaves authorized material rows mounted without another read', (
    tester,
  ) async {
    final catalog = MockMaterialCatalog();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) async {});
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PageRouteActivityObserver()],
        home: MaterialCatalogScope(
          catalog: catalog,
          child: MaterialCatalogAccess(
            builder: (context, _) => Column(
              children: [
                const Text('private material row'),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('detail dialog')),
                  ),
                  child: const Text('open dialog'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.element(find.text('private material row'));
    clearInteractions(catalog);
    await tester.tap(find.text('open dialog'));
    await tester.pump();
    expect(tester.element(find.text('private material row')), same(row));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    verifyNever(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('private material row')), same(row));
    verifyNever(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile type controls and import stay mounted while private results recheck', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final material = MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: '受权材料',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '可阅读',
      cover: '书',
    );
    final pending = Completer<void>();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((invocation) {
      final query = invocation.namedArguments[#query] as MaterialCatalogQuery;
      return query.type == LearningMaterialType.novel ? pending.future : Future<void>.value();
    });
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    final tabs = find.byKey(const ValueKey('mobile-material-types'));
    final tabElement = tester.element(tabs);
    final importButton = find.text('导入材料');
    final importElement = tester.element(importButton);
    expect(find.text('受权材料'), findsOneWidget);

    await tester.tap(find.text('小说').first);
    await tester.pump();
    expect(tester.element(tabs), same(tabElement));
    expect(tester.element(importButton), same(importElement));
    expect(find.text('受权材料'), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.element(tabs), same(tabElement));
    expect(tester.element(importButton), same(importElement));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.element(tabs), same(tabElement));
    expect(find.text('受权材料'), findsOneWidget);
  });

  testWidgets('library reads injected catalog and confirms deletion before mutation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final material = MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: '注入的小说',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '章节已准备',
      cover: '书',
      sectionCount: 2,
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    expect(find.text('注入的小说'), findsOneWidget);
    expect(find.text('1 份材料'), findsNothing);
    clearInteractions(catalog);
    await tester.tap(find.text('小说').first);
    await tester.pumpAndSettle();
    verify(
      catalog.refresh(
        query: argThat(
          isA<MaterialCatalogQuery>().having(
            (value) => value.type,
            'type',
            LearningMaterialType.novel,
          ),
          named: 'query',
        ),
        force: false,
        preserveCurrent: false,
      ),
    ).called(1);
    await tester.tap(find.byTooltip('注入的小说更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    verifyNever(catalog.deleteMaterial(material.id));

    await tester.tap(find.byTooltip('注入的小说更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除', skipOffstage: false).last);
    await tester.pumpAndSettle();
    verify(catalog.deleteMaterial(material.id)).called(1);
  });

  testWidgets('desktop detail resolves the selected material through the catalog', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final material = MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: '仓储中的小说',
      language: 'ja',
      status: 'readable',
      revision: 2,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '仓储详情',
      cover: '书',
      sectionCount: 2,
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    when(catalog.findById(material.id)).thenReturn(material);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    expect(find.text('1 份材料'), findsNothing);
    await tester.tap(find.byTooltip('仓储中的小说更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情').last);
    await tester.pumpAndSettle();
    expect(find.text('仓储详情'), findsOneWidget);
    verify(catalog.findById(material.id)).called(greaterThan(0));
  });

  testWidgets(
    'phone detail uses its authorized filtered list without replacing the selected card',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = MockMaterialCatalog();
      final material = MaterialSummary(
        id: '11111111-1111-4111-8111-111111111111',
        type: LearningMaterialType.novel,
        title: '筛选后的小说',
        language: 'ja',
        status: 'readable',
        revision: 3,
        updatedAt: DateTime.utc(2026, 9, 27),
        description: '授权详情',
        cover: '书',
      );
      when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
      when(catalog.filterMaterials(any)).thenReturn([material]);
      when(catalog.findById(material.id)).thenReturn(material);
      when(
        catalog.refresh(
          query: anyNamed('query'),
          force: anyNamed('force'),
          preserveCurrent: anyNamed('preserveCurrent'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小说').first);
      await tester.pumpAndSettle();
      final card = tester.element(find.byType(MobileMaterialCard));
      clearInteractions(catalog);
      final pending = Completer<void>();
      when(
        catalog.refresh(
          query: anyNamed('query'),
          force: anyNamed('force'),
          preserveCurrent: anyNamed('preserveCurrent'),
        ),
      ).thenAnswer((_) => pending.future);
      await tester.tap(find.byTooltip('筛选后的小说更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情').last);
      await tester.pump();
      expect(tester.element(find.byType(MobileMaterialCard)), same(card));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      verifyNever(
        catalog.refresh(
          query: anyNamed('query'),
          force: anyNamed('force'),
          preserveCurrent: anyNamed('preserveCurrent'),
        ),
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('授权详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone detail rejects a changed revision after the authorization read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final selected = MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: '旧版小说',
      language: 'ja',
      status: 'readable',
      revision: 3,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '旧详情',
      cover: '书',
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([selected]);
    when(catalog.findById(selected.id)).thenAnswer(
      (_) => MaterialSummary(
        id: selected.id,
        type: selected.type,
        title: selected.title,
        language: selected.language,
        status: selected.status,
        revision: 4,
        updatedAt: selected.updatedAt,
        description: '新版详情',
        cover: selected.cover,
      ),
    );
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('旧版小说更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情').last);
    await tester.pumpAndSettle();
    expect(find.text('新版详情'), findsNothing);
    expect(find.text('材料已删除或不可读取'), findsOneWidget);

    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) async => throw StateError('authorization read failed'));
    await tester.tap(find.byTooltip('旧版小说更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情').last);
    await tester.pumpAndSettle();
    expect(find.text('新版详情'), findsNothing);
    expect(find.text('材料已删除或不可读取'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone material card keeps a long title contained and omits task progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    const longTitle = '这是一个标题很长、需要在手机材料列表中完整换行显示的日语小说资料';
    final material = MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: longTitle,
      language: 'ja',
      status: 'processing',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '解析中',
      cover: '书',
      activeJobProgressPercent: 35,
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();

    final card = find.ancestor(of: find.text(longTitle), matching: find.byType(Card));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, lessThan(140));
    expect(find.text('处理中'), findsOneWidget);
    expect(find.textContaining('35%'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle time and app resume keep rows mounted without a business refresh', (
    tester,
  ) async {
    final catalog = MockMaterialCatalog();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) async {});
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PageRouteActivityObserver()],
        home: MaterialCatalogScope(
          catalog: catalog,
          child: MaterialCatalogAccess(builder: (context, _) => const Text('ready')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    clearInteractions(catalog);
    final pending = Completer<void>();
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) => pending.future);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('ready'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('ready'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    verifyNever(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    );
    pending.complete();
    await tester.pump();
  });

  testWidgets('returning to unchanged material rows preserves their element with zero reads', (
    tester,
  ) async {
    final catalog = MockMaterialCatalog();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) async {});
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PageRouteActivityObserver()],
        home: MaterialCatalogScope(
          catalog: catalog,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(appBar: AppBar(), body: const Text('detail')),
                      ),
                    ),
                    child: const Text('open detail'),
                  ),
                  Expanded(
                    child: MaterialCatalogAccess(
                      builder: (context, _) => const Text('private material rows'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('private material rows'), findsOneWidget);
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    clearInteractions(catalog);
    final pending = Completer<void>();
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((_) => pending.future);

    final row = tester.element(find.text('private material rows', skipOffstage: false));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('private material rows'), findsOneWidget);
    expect(tester.element(find.text('private material rows')), same(row));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    verifyNever(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    );
    pending.complete();
  });

  testWidgets('phone list restores its scroll position after material route return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final materials = List.generate(
      12,
      (index) => MaterialSummary(
        id: '11111111-1111-4111-8111-${index.toString().padLeft(12, '0')}',
        type: LearningMaterialType.novel,
        title: '滚动小说 $index',
        language: 'ja',
        status: 'readable',
        revision: 1,
        updatedAt: DateTime.utc(2026, 9, 27),
        description: '可阅读',
        cover: '书',
        sectionCount: 2,
      ),
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn(materials);
    when(catalog.findById(any)).thenAnswer(
      (invocation) =>
          materials.where((item) => item.id == invocation.positionalArguments.first).firstOrNull,
    );
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byType(MobileLibraryView),
      matching: find.byType(ListView),
    );
    await tester.scrollUntilVisible(
      find.text('滚动小说 5'),
      180,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    expect(before, greaterThan(0));
    await tester.tap(find.text('滚动小说 5'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.descendant(
                  of: find.byType(MobileLibraryView),
                  matching: find.byType(ListView),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    expect(after, closeTo(before, 1));
  });

  for (final desktop in [false, true]) {
    for (final insertAhead in [false, true]) {
      testWidgets('${desktop ? 'desktop' : 'phone'} return keeps the opened material in view '
          'after a leading ${insertAhead ? 'insert' : 'delete'}', (tester) async {
        tester.view.physicalSize = desktop ? const Size(1200, 900) : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final catalog = MockMaterialCatalog();
        final materials = List.generate(12, _scrollMaterial);
        final publishChange = _catalogChanges(catalog);
        when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
        when(catalog.filterMaterials(any)).thenAnswer((_) => List.of(materials));
        when(catalog.findById(any)).thenAnswer(
          (invocation) => materials
              .where((item) => item.id == invocation.positionalArguments.first)
              .firstOrNull,
        );
        when(
          catalog.refresh(
            query: anyNamed('query'),
            force: anyNamed('force'),
            preserveCurrent: anyNamed('preserveCurrent'),
          ),
        ).thenAnswer((_) async {});
        await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
        await tester.pumpAndSettle();
        final view = desktop ? find.byType(DesktopLibraryResults) : find.byType(MobileLibraryView);
        final scrollable = find.descendant(of: view, matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(
          find.text('滚动小说 5'),
          desktop ? 220 : 180,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        final openedCard = find.ancestor(of: find.text('滚动小说 5'), matching: find.byType(Card));
        final beforeTop = tester.getTopLeft(openedCard).dy;
        if (!desktop && insertAhead) {
          await tester.tap(find.byTooltip('滚动小说 5更多操作'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('查看详情').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('打开材料'));
        } else {
          await tester.tap(find.text('滚动小说 5'));
        }
        await tester.pumpAndSettle();

        clearInteractions(catalog);
        if (insertAhead) {
          materials.insert(0, _scrollMaterial(99));
        } else {
          materials.removeAt(0);
        }
        publishChange();
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byType(desktop ? DesktopLibraryResults : MobileLibraryResults), findsOneWidget);
        verifyNever(
          catalog.refresh(
            query: anyNamed('query'),
            force: anyNamed('force'),
            preserveCurrent: anyNamed('preserveCurrent'),
          ),
        );
        await tester.pumpAndSettle();
        final restoredCard = find.ancestor(of: find.text('滚动小说 5'), matching: find.byType(Card));
        expect(restoredCard, findsOneWidget);
        expect(tester.getTopLeft(restoredCard).dy, closeTo(beforeTop, 1));
        if (!desktop && !insertAhead) {
          await tester.tap(find.text('滚动小说 5'));
          await tester.pumpAndSettle();
          materials.insert(0, _scrollMaterial(98));
          publishChange();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          final secondCard = find.ancestor(of: find.text('滚动小说 5'), matching: find.byType(Card));
          expect(secondCard, findsOneWidget);
          expect(tester.getTopLeft(secondCard).dy, closeTo(beforeTop, 1));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('removed anchor returns to the authorized library without repeated jumps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final materials = List.generate(12, _scrollMaterial);
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenAnswer((_) => List.of(materials));
    when(catalog.findById(any)).thenAnswer(
      (invocation) =>
          materials.where((item) => item.id == invocation.positionalArguments.first).firstOrNull,
    );
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byType(MobileLibraryView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('滚动小说 5'), 180, scrollable: list.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('滚动小说 5'));
    await tester.pumpAndSettle();
    materials.removeWhere((item) => item.title == '滚动小说 5');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('滚动小说 5'), findsNothing);
    final returnedList = find.descendant(
      of: find.byType(MobileLibraryView),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(returnedList.first).position.jumpTo(0);
    await tester.pump();
    expect(find.text('11 份材料'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('11 份材料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop search retains text and focus across a gated catalog refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn(const []);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(DesktopLibraryView),
      matching: find.byType(TextField),
    );
    final searchElement = tester.element(search);
    await tester.enterText(search, '夏');
    await tester.pump();
    expect(tester.element(search), same(searchElement));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '夏の',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(tester.element(search), same(searchElement));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller?.text, '夏の');
    expect(
      tester.widget<TextField>(search).controller?.value.composing,
      const TextRange(start: 0, end: 2),
    );
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
  });

  testWidgets('new search starts after debounce even while the old search is pending', (
    tester,
  ) async {
    final catalog = MockMaterialCatalog();
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    final oldPending = Completer<void>();
    final seen = <String>[];
    when(
      catalog.refresh(
        query: anyNamed('query'),
        force: anyNamed('force'),
        preserveCurrent: anyNamed('preserveCurrent'),
      ),
    ).thenAnswer((invocation) {
      final query = invocation.namedArguments[#query] as MaterialCatalogQuery;
      seen.add(query.search);
      return query.search == 'old' ? oldPending.future : Future<void>.value();
    });
    var query = const MaterialCatalogQuery();
    await tester.pumpWidget(
      MaterialApp(
        home: MaterialCatalogScope(
          catalog: catalog,
          child: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        update(() => query = const MaterialCatalogQuery(search: 'old')),
                    child: const Text('old search'),
                  ),
                  TextButton(
                    onPressed: () =>
                        update(() => query = const MaterialCatalogQuery(search: 'new')),
                    child: const Text('new search'),
                  ),
                  Expanded(
                    child: MaterialCatalogAccess(
                      query: query,
                      builder: (context, _) => const Text('results'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('old search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(seen, ['', 'old']);
    await tester.tap(find.text('new search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(seen, ['', 'old', 'new']);
    expect(find.text('results'), findsOneWidget);
    oldPending.complete();
    await tester.pump();
    expect(find.text('results'), findsOneWidget);
  });

  for (final desktop in [false, true]) {
    testWidgets('deleted material has a safe ${desktop ? 'desktop' : 'phone'} return', (
      tester,
    ) async {
      tester.view.physicalSize = desktop ? const Size(1200, 900) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = MockMaterialCatalog();
      final publishChange = _catalogChanges(catalog);
      const materialId = '11111111-1111-4111-8111-111111111111';
      final material = MaterialSummary(
        id: materialId,
        type: LearningMaterialType.novel,
        title: '删除前的小说',
        language: 'ja',
        status: 'readable',
        revision: 1,
        updatedAt: DateTime.utc(2026, 9, 27),
        description: '可阅读',
        cover: '书',
      );
      var available = true;
      when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
      when(catalog.filterMaterials(any)).thenAnswer((_) => available ? [material] : []);
      when(catalog.findById(materialId)).thenAnswer((_) => available ? material : null);
      await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
      await tester.pumpAndSettle();
      if (desktop) {
        await tester.tap(find.byTooltip('删除前的小说更多操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看详情').last);
      } else {
        await tester.tap(find.text('删除前的小说'));
      }
      await tester.pumpAndSettle();
      clearInteractions(catalog);
      available = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(desktop ? '材料已删除' : '材料已删除或不可读取'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(desktop ? '材料已删除' : '材料已删除或不可读取'), findsNothing);
      verifyNever(
        catalog.refresh(
          query: anyNamed('query'),
          force: anyNamed('force'),
          preserveCurrent: anyNamed('preserveCurrent'),
        ),
      );
      publishChange();
      await tester.pumpAndSettle();
      expect(find.text(desktop ? '材料已删除' : '材料已删除或不可读取'), findsOneWidget);
      if (desktop) {
        await tester.tap(find.widgetWithText(TextButton, '材料库').last);
      } else {
        await tester.tap(find.byTooltip('返回'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(desktop ? DesktopLibraryView : MobileLibraryView), findsOneWidget);
    });
  }

  for (final desktop in [false, true]) {
    testWidgets('deleted material deep link returns to ${desktop ? 'desktop' : 'phone'} library', (
      tester,
    ) async {
      tester.view.physicalSize = desktop ? const Size(1200, 900) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = MockMaterialCatalog();
      when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
      when(catalog.filterMaterials(any)).thenReturn(const []);
      await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
      await tester.pumpAndSettle();
      final library = find.byType(desktop ? DesktopLibraryView : MobileLibraryView);
      GoRouter.of(tester.element(library))
          .go(AppRoutes.mockMaterialDetailsPath('11111111-1111-4111-8111-111111111111'));
      await tester.pumpAndSettle();
      expect(find.text('材料已删除'), findsOneWidget);
      if (desktop) {
        await tester.tap(find.widgetWithText(TextButton, '材料库').last);
      } else {
        await tester.tap(find.byTooltip('返回'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(desktop ? DesktopLibraryView : MobileLibraryView), findsOneWidget);
    });
  }
}

MaterialSummary _scrollMaterial(int index) => MaterialSummary(
  id: '11111111-1111-4111-8111-${index.toString().padLeft(12, '0')}',
  type: LearningMaterialType.novel,
  title: '滚动小说 $index',
  language: 'ja',
  status: 'readable',
  revision: 1,
  updatedAt: DateTime.utc(2026, 9, 27),
  description: '可阅读',
  cover: '书',
  sectionCount: 2,
);

/// A real mutation signal replaces the obsolete timer/route-refresh assumption.
VoidCallback _catalogChanges(MockMaterialCatalog catalog) {
  final listeners = <VoidCallback>{};
  when(catalog.addListener(any)).thenAnswer((invocation) {
    listeners.add(invocation.positionalArguments.single as VoidCallback);
  });
  when(catalog.removeListener(any)).thenAnswer((invocation) {
    listeners.remove(invocation.positionalArguments.single as VoidCallback);
  });
  return () {
    for (final listener in List.of(listeners)) {
      listener();
    }
  };
}

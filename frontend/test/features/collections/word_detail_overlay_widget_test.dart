import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/collections/domain/notebook_record.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

class _MemoryWordCatalog extends ChangeNotifier implements CollectionCatalog {
  _MemoryWordCatalog(this.entry, this.books);

  final CollectionEntry entry;
  final List<NotebookRecord> books;
  int collectionReads = 0;
  int notebookReads = 0;
  @override
  int get scopeGeneration => 1;

  @override
  CollectionCatalogStatus get allCollectionStatus => CollectionCatalogStatus.ready;
  @override
  CollectionCatalogStatus get collectionStatus => CollectionCatalogStatus.ready;
  @override
  CollectionCatalogStatus get notebookStatus => CollectionCatalogStatus.ready;
  @override
  List<NotebookRecord> get notebooks => books;
  @override
  CollectionEntry? findCollection(String id) => id == entry.id ? entry : null;
  @override
  Future<void> refreshAllCollections({bool force = false, bool preserveCurrent = false}) async {
    collectionReads++;
  }

  @override
  Future<void> refreshNotebooks({bool force = false, bool preserveCurrent = false}) async {
    notebookReads++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<(_MemoryWordCatalog, CollectionEntry)> openWord(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final entry = store.collections.firstWhere((item) => item.kind == CollectionKind.word);
    final catalog = _MemoryWordCatalog(entry, store.notebooks);
    addTearDown(catalog.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () => showWordDetail(context, entry.id),
              child: const Text('打开单词详情'),
            ),
          ),
        ),
        GoRoute(path: AppRoutes.mockLibrary, builder: (_, _) => const Text('原文路由')),
        GoRoute(path: AppRoutes.mockMaterial, builder: (_, _) => const Text('原文路由')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      CollectionCatalogScope(
        catalog: catalog,
        child: PreviewStoreScope(
          store: store,
          child: MaterialApp.router(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开单词详情'));
    await tester.pumpAndSettle();
    expect(find.byType(WordDetailDialog), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(catalog.collectionReads, 0);
    expect(catalog.notebookReads, 0);
    return (catalog, entry);
  }

  testWidgets('word edit and assignment stay in one dialog and discard cancelled drafts', (
    tester,
  ) async {
    final (catalog, entry) = await openWord(tester, size: const Size(390, 844));
    final background = tester.element(find.text('打开单词详情'));

    await tester.tap(find.text('编辑与笔记'));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '内容',
    );
    await tester.enterText(field, '未保存的草稿');
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    await tester.tap(find.text('编辑与笔记'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, entry.displayText);
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();

    await tester.tap(find.text('归入单词本'));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);
    final checkbox = find.byType(CheckboxListTile).first;
    final initial = tester.widget<CheckboxListTile>(checkbox).value!;
    tester.widget<CheckboxListTile>(checkbox).onChanged!(!initial);
    await tester.pump();
    await tester.tap(find.byTooltip('取消'));
    await tester.pump();
    await tester.tap(find.text('归入单词本'));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value, initial);
    expect(tester.element(find.text('打开单词详情')), same(background));
    expect(catalog.collectionReads, 0);
    expect(catalog.notebookReads, 0);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(WordDetailDialog), findsNothing);
    expect(tester.element(find.text('打开单词详情')), same(background));
    expect(catalog.collectionReads, 0);
    expect(catalog.notebookReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('word editor remains scrollable above a short viewport keyboard', (tester) async {
    await openWord(tester, size: const Size(320, 560));
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pump();
    await tester.tap(find.text('编辑与笔记'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(tester.getTopLeft(find.byTooltip('关闭')).dy, lessThan(560 - 180));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('source action closes the $size overlay before routing from its owner', (
      tester,
    ) async {
      await openWord(tester, size: size);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      await tester.tap(find.text('回到原文 →'));
      await tester.pumpAndSettle();
      expect(find.text('原文路由'), findsOneWidget);
      expect(find.byType(WordDetailDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

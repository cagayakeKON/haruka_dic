import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/collections/domain/notebook_record.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/collections/presentation/collection_detail_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

class _MemoryOverlayCatalog extends ChangeNotifier implements CollectionCatalog {
  _MemoryOverlayCatalog(this.entry, this.books);

  final CollectionEntry entry;
  final List<NotebookRecord> books;
  int collectionReads = 0;
  int notebookReads = 0;

  @override
  int get scopeGeneration => 1;
  @override
  CollectionCatalogStatus get collectionStatus => CollectionCatalogStatus.ready;

  @override
  CollectionCatalogStatus get allCollectionStatus => CollectionCatalogStatus.ready;
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
  testWidgets('authorized collection dialog opens and closes without list reads or remount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final entry = store.collections.firstWhere((row) => row.kind == CollectionKind.grammar);
    final catalog = _MemoryOverlayCatalog(entry, store.notebooks);
    addTearDown(catalog.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => showCollectionDetail(context, entry.id),
              child: const Text('打开详情'),
            ),
          ),
        ),
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
    final background = tester.element(find.text('打开详情'));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionDetailPage), findsOneWidget);
    expect(catalog.collectionReads, 0);
    expect(catalog.notebookReads, 0);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('打开详情')), same(background));
    expect(catalog.collectionReads, 0);
    expect(catalog.notebookReads, 0);
    expect(tester.takeException(), isNull);
  });

  Future<(_MemoryOverlayCatalog, CollectionEntry)> openOverlay(
    WidgetTester tester, {
    required Size size,
    double keyboard = 0,
    bool longContent = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final original = store.collections.firstWhere((item) => item.kind == CollectionKind.grammar);
    final entry = longContent
        ? original.copyWith(meaning: List.filled(70, '有来源的长释义可在详情正文滚动。').join('\n'))
        : original;
    final catalog = _MemoryOverlayCatalog(entry, store.notebooks);
    addTearDown(catalog.dispose);
    await tester.pumpWidget(
      CollectionCatalogScope(
        catalog: catalog,
        child: PreviewStoreScope(
          store: store,
          child: MaterialApp(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => Dialog(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 520,
                          maxHeight: (MediaQuery.sizeOf(dialogContext).height - keyboard) * .85,
                        ),
                        child: CollectionDetailPage(itemId: entry.id, overlay: true),
                      ),
                    ),
                  ),
                  child: const Text('打开详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    return (catalog, entry);
  }

  testWidgets('cancelled edit and notebook drafts reset in one overlay', (tester) async {
    final (_, entry) = await openOverlay(tester, size: const Size(390, 844));
    await tester.tap(find.text('编辑与笔记'));
    await tester.pump();
    final contentField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '内容',
    );
    await tester.enterText(contentField, '取消的草稿');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.tap(find.text('编辑与笔记'));
    await tester.pump();
    expect(tester.widget<TextField>(contentField).controller!.text, entry.displayText);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();

    await tester.tap(find.text('归入单词本'));
    await tester.pump();
    final checkbox = find.byType(CheckboxListTile).first;
    final initial = tester.widget<CheckboxListTile>(checkbox).value!;
    tester.widget<CheckboxListTile>(checkbox).onChanged!(!initial);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.tap(find.text('归入单词本'));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value, initial);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long detail scrolls within a short dialog above the keyboard', (tester) async {
    await openOverlay(tester, size: const Size(320, 560), keyboard: 150, longContent: true);
    final list = find.descendant(
      of: find.byType(CollectionDetailPage),
      matching: find.byType(ListView),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(list, const Offset(0, -900));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

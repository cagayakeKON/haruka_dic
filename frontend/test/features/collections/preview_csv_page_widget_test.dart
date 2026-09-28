import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/collections/data/csv_file_port.dart';
import 'package:haruka/features/collections/presentation/csv_page.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/ai_exercises/presentation/exercise_support_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';

import 'collection_catalog_test_harness.dart';

class _FakeCsvFilePort implements CsvFilePort {
  PickedCsvFile? nextFile;
  CsvSaveOutcome nextSave = CsvSaveOutcome.downloadStarted;
  int pickCalls = 0;
  int saveCalls = 0;
  Uint8List? savedBytes;

  @override
  Future<PickedCsvFile?> pick() async {
    pickCalls++;
    return nextFile;
  }

  @override
  Future<CsvSaveOutcome> save(String name, Uint8List bytes) async {
    saveCalls++;
    savedBytes = bytes;
    expect(name, endsWith('.csv'));
    return nextSave;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  PreviewFixtureStore store,
  Widget page,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => page)],
  );
  addTearDown(router.dispose);
  final harness = await CollectionCatalogTestHarness.create(store);
  addTearDown(harness.close);
  await tester.pumpWidget(
    CollectionCatalogScope(
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
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone CSV selection previews actual rows and confirms only after exclusion', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final files = _FakeCsvFilePort()
      ..nextFile = PickedCsvFile(
        name: 'chosen.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'word,language,meaning,context,source_title\n'
            'そっと,ja,旧释义,夏の風がそっと頬に触れた。,夏の手紙 · 第 03 章\n'
            '新しい,ja,新的,,\n'
            ',ja,无效词条,,',
          ),
        ),
      );
    await _pumpPage(tester, store, CsvPage(filePort: files), const Size(390, 844));
    expect(find.byType(MobileCsvView), findsOneWidget);
    expect(find.byType(DesktopCsvView), findsNothing);
    expect(store.collections.length, 6);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '查看导入预览')).onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '选择 UTF-8 CSV'));
    await tester.pumpAndSettle();
    expect(files.pickCalls, 1);
    expect(find.text('chosen.csv'), findsOneWidget);
    await tester.ensureVisible(find.text('查看导入预览'));
    await tester.tap(find.text('查看导入预览'));
    await tester.pumpAndSettle();
    expect(find.text('共 3 行 · 新词 1 · 重复 1 · 错误 1'), findsOneWidget);
    expect(store.collections.length, 6);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入')).onPressed,
      isNull,
    );
    await tester.drag(
      find.descendant(of: find.byType(MobileCsvView), matching: find.byType(ListView)),
      const Offset(0, -580),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('排除错误行后导入'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认导入'));
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    expect(store.collections.length, 7);
    expect(store.collections.first.displayText, '新しい');
    expect(find.text('新增 1 · 补全 0 · 跳过 1 · 排除 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop CSV export sends all word rows to save port', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final files = _FakeCsvFilePort();
    await _pumpPage(tester, store, CsvPage(filePort: files), const Size(1440, 900));
    expect(find.byType(DesktopCsvView), findsOneWidget);
    expect(find.byType(MobileCsvView), findsNothing);
    await tester.tap(find.text('下载单词 CSV'));
    await tester.pumpAndSettle();
    expect(files.saveCalls, 1);
    expect(utf8.decode(files.savedBytes!), contains('そっと'));
    expect(find.text('已交给浏览器下载'), findsOneWidget);
    expect(store.collections.length, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled file selection leaves import state unchanged', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final files = _FakeCsvFilePort();
    await _pumpPage(tester, store, CsvPage(filePort: files), const Size(390, 844));
    await tester.tap(find.text('选择 UTF-8 CSV').last);
    await tester.pumpAndSettle();
    expect(files.pickCalls, 1);
    expect(store.collections.length, 6);
    expect(find.text('确认导入'), findsNothing);
  });

  testWidgets('invalid mistake index shows resource not found', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await _pumpPage(tester, store, const MistakeDetailPage(index: -1), const Size(390, 844));
    expect(find.text('未找到资源'), findsOneWidget);
    expect(find.text('归因：'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

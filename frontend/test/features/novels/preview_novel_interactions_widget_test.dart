import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/features/novels/presentation/selection_overlay.dart';

void main() {
  Future<void> openNovel(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('夏の手紙'));
    await tester.pumpAndSettle();
  }

  Future<void> longPressSentence(WidgetTester tester, int index) async {
    final finder = find
        .ancestor(of: find.byType(RubySentence).at(index), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(finder);
    await tester.longPress(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openSelectionWithKeyboard(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('phone reading text keeps ordinary selection separate from Alt+Enter', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final paragraph = find.byType(NovelReadingParagraph).first;
    final bounds = tester.getRect(paragraph);
    final secondSentence = Offset(bounds.left + 40, bounds.bottom - 8);
    await tester.tapAt(secondSentence);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byType(NovelSelectionToolbar), findsNothing);

    await openSelectionWithKeyboard(tester);
    expect(tester.widget<MobileNovelView>(find.byType(MobileNovelView)).selectedRangeSentence, 1);
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native selection in the second sentence keeps its exact query range', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final paragraph = find.byType(NovelReadingParagraph).first;
    final richText = find.descendant(of: paragraph, matching: find.byType(RichText)).first;
    final text = tester.widget<NovelReadingParagraph>(paragraph);
    final full = '${text.first} ${text.second}';
    final secondStart = text.first.length + 1;
    final targetOffset = full.indexOf('の', secondStart);
    final render = tester.renderObject<RenderParagraph>(richText);
    final box = render
        .getBoxesForSelection(
          TextSelection(baseOffset: targetOffset, extentOffset: targetOffset + 1),
        )
        .single;
    final origin = tester.getTopLeft(richText);
    final y = origin.dy + (box.top + box.bottom) / 2;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(Offset(origin.dx + box.left + .1, y));
    await gesture.moveTo(Offset(origin.dx + box.right - .1, y));
    await gesture.up();
    await tester.pump();

    final listener = tester.widget<SelectionListener>(
      find.descendant(of: paragraph, matching: find.byType(SelectionListener)).first,
    );
    final range = listener.selectionNotifier.selection.range;
    expect(range, isNotNull);
    expect(range!.startOffset, greaterThanOrEqualTo(secondStart));
    expect(range.endOffset, greaterThan(range.startOffset));
    expect(find.byType(NovelSelectionToolbar), findsNothing);
    final selectedText = full.substring(range.startOffset, range.endOffset);

    await openSelectionWithKeyboard(tester);
    expect(tester.widget<MobileNovelView>(find.byType(MobileNovelView)).selectedRangeSentence, 1);
    expect(
      tester.widget<NovelSelectionToolbar>(find.byType(NovelSelectionToolbar)).nativeSelectionText,
      selectedText,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NovelSelectionResultBody>(find.byType(NovelSelectionResultBody)).selectedText,
      selectedText,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop analysis selection opens on Alt+Enter and focuses its toolbar', (
    tester,
  ) async {
    await openNovel(tester, const Size(1440, 900));
    final sentence = find
        .ancestor(of: find.byType(RubySentence).at(1), matching: find.byType(InkWell))
        .first;
    await tester.tap(sentence);
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionToolbar), findsNothing);

    await openSelectionWithKeyboard(tester);
    expect(tester.widget<DesktopNovelView>(find.byType(DesktopNovelView)).selectedRangeSentence, 1);
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    final toolbarFocus = find.descendant(
      of: find.byType(NovelSelectionToolbar),
      matching: find.byKey(const ValueKey('novel-selection-toolbar-focus')),
    );
    final toolbarMaterial = find
        .descendant(of: toolbarFocus, matching: find.byType(Material))
        .first;
    expect(Focus.of(tester.element(toolbarMaterial)).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked novel scope cannot reopen a sentence from the keyboard', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await coordinator.closeScope();
    await tester.pumpAndSettle();

    await openSelectionWithKeyboard(tester);
    expect(find.byType(NovelSelectionToolbar), findsNothing);
    expect(find.byType(NovelPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open sentence sheet masks private text when account access is revoked', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SentenceDialog), findsOneWidget);
    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(SentenceDialog), findsNothing);
    expect(find.text('朝の光が、白いカーテンを通して部屋に広がった。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open sentence sheet masks private text when material is deleted', (tester) async {
    await openNovel(tester, const Size(390, 844));
    final novel = tester.widget<NovelPage>(find.byType(NovelPage));
    final catalog = MaterialCatalogScope.of(tester.element(find.byType(NovelPage)));
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SentenceDialog), findsOneWidget);
    await catalog.deleteMaterial(novel.item.id);
    await tester.pumpAndSettle();
    expect(find.byType(SentenceDialog), findsNothing);
    expect(find.text('朝の光が、白いカーテンを通して部屋に広がった。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open selection result sheet masks private text after scope revocation', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await longPressSentence(tester, 0);
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsOneWidget);

    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsNothing);
    expect(find.text('朝の光が、白いカーテンを通して部屋に広がった。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked selection result rejects a captured word save callback', (tester) async {
    await openNovel(tester, const Size(390, 844));
    final novelContext = tester.element(find.byType(NovelPage));
    final coordinator = PreviewSettingsCacheScope.of(novelContext).coordinator;
    final store = PreviewStoreScope.of(novelContext);
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await longPressSentence(tester, 1);
    await tester.tap(find.widgetWithText(FilterChip, '窓'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '收藏'));
    final before = store.collections.where((item) => item.displayText == '窓').length;

    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsNothing);
    save.onPressed?.call();
    await tester.pump();
    expect(store.collections.where((item) => item.displayText == '窓').length, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open chapter preparation and its menu mask titles after scope revocation', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(find.text('准备本章'));
    await tester.pumpAndSettle();
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始准备'));
    await tester.tap(find.byType(DropdownMenu<int>));
    await tester.pumpAndSettle();
    expect(find.textContaining('海边的邮筒'), findsWidgets);

    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.textContaining('海边的邮筒'), findsNothing);
    expect(find.widgetWithText(FilledButton, '开始准备'), findsNothing);
    expect(tester.takeException(), isNull);
    start.onPressed?.call();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('open phone contents sheet masks chapter titles after material deletion', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    final novel = tester.widget<NovelPage>(find.byType(NovelPage));
    final catalog = MaterialCatalogScope.of(tester.element(find.byType(NovelPage)));
    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    final chapter = tester.widget<ListTile>(find.widgetWithText(ListTile, '第 1 章 · 海边的邮筒'));
    await catalog.deleteMaterial(novel.item.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('海边的邮筒'), findsNothing);
    chapter.onTap?.call();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('open phone typography sheet cannot change a revoked reader', (tester) async {
    await openNovel(tester, const Size(390, 844));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(find.text('排版'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    slider.onChanged?.call(20);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('open desktop contents menu masks titles and blocks selection on deletion', (
    tester,
  ) async {
    await openNovel(tester, const Size(1440, 900));
    final novel = tester.widget<NovelPage>(find.byType(NovelPage));
    final catalog = MaterialCatalogScope.of(tester.element(find.byType(NovelPage)));
    final menu = tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('海边的邮筒'), findsWidgets);
    await catalog.deleteMaterial(novel.item.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('海边的邮筒'), findsNothing);
    menu.onSelected?.call(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('open desktop typography dialog masks controls after scope revocation', (
    tester,
  ) async {
    await openNovel(tester, const Size(1440, 900));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(find.byTooltip('排版'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    await coordinator.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    slider.onChanged?.call(20);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone long press offers token choice, range, and query', (tester) async {
    await openNovel(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await longPressSentence(tester, 1);
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    expect(find.text('选句学习'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'そっと'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'そっと'));
    await tester.pumpAndSettle();
    final selected = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'そっと'));
    expect(selected.selected, isTrue);
    await tester.tap(find.text('调整范围'));
    await tester.pumpAndSettle();
    expect(find.text('起点'), findsOneWidget);
    expect(find.text('终点'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsOneWidget);
    expect(find.text('轻轻地、悄悄地。强调动作温柔，不打扰周围。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone reading paragraphs keep adjacent sentences and select the touched one', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    expect(find.byType(NovelReadingParagraph), findsNWidgets(3));
    final first = find.byType(NovelReadingParagraph).first;
    final paragraph = tester.widget<NovelReadingParagraph>(first);
    expect(paragraph.first, '朝の光が、白いカーテンを通して部屋に広がった。');
    expect(paragraph.second, '窓を開けると、夏の風がそっと頬に触れた。');

    final bounds = tester.getRect(first);
    await tester.longPressAt(Offset(bounds.left + 30, bounds.bottom - 8));
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('窓を開けると、夏の風がそっと頬に触れた。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone selected window token opens a word card', (tester) async {
    await openNovel(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await longPressSentence(tester, 1);
    await tester.tap(find.widgetWithText(FilterChip, '窓'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsOneWidget);
    expect(find.text('窓'), findsWidgets);
    expect(find.text('单词'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NovelSelectionResultBody), matching: find.text('まど')),
      findsOneWidget,
    );
    expect(find.text('释义'), findsOneWidget);
    expect(find.text('窗户'), findsOneWidget);
    expect(find.text('暂无查询结果'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone sentence query carries the current sentence and returns to its sheet', (
    tester,
  ) async {
    await openNovel(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一句'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '查询选中内容'));
    await tester.tap(find.widgetWithText(FilledButton, '查询选中内容'));
    await tester.pumpAndSettle();

    expect(find.byType(QueryPage), findsOneWidget);
    expect(tester.widget<QueryPage>(find.byType(QueryPage)).initialText, '窓を開けると、夏の風がそっと頬に触れた。');
    final router = GoRouter.of(tester.element(find.byType(QueryPage)));
    expect(router.routeInformationProvider.value.uri.toString(), AppRoutes.mockQuery);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(SentenceDialog), findsOneWidget);
    expect(find.text('第 2 / 5 句'), findsOneWidget);
    expect(find.text('打开窗户，夏风轻轻拂过脸颊。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sentence query restores the selected analysis panel', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 5 句'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '查询选中内容'));
    await tester.pumpAndSettle();

    expect(tester.widget<QueryPage>(find.byType(QueryPage)).initialText, '朝の光が、白いカーテンを通して部屋に広がった。');
    final router = GoRouter.of(tester.element(find.byType(QueryPage)));
    expect(router.routeInformationProvider.value.uri.toString(), AppRoutes.mockQuery);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 5 句'), findsOneWidget);
    expect(find.text('句子解析'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('novel sentence draft is cleared when the account scope changes', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    final coordinator = PreviewSettingsCacheScope.of(tester.element(find.byType(NovelPage)))
        .coordinator;
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '查询选中内容'));
    await tester.pumpAndSettle();
    expect(tester.widget<QueryPage>(find.byType(QueryPage)).initialText, isNotNull);

    await coordinator.closeScope();
    await coordinator.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://haruka.example/api'),
        instanceId: 'another-instance',
        userId: 'another-user',
        audience: 'client',
        sessionRef: 'another-session',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<QueryPage>(find.byType(QueryPage)).initialText, isNull);
    expect(
      GoRouter.of(tester.element(find.byType(QueryPage))).routeInformationProvider.value.uri
          .toString(),
      AppRoutes.mockQuery,
    );
    GoRouter.of(tester.element(find.byType(QueryPage))).pop();
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 5 句'), findsNothing);
    expect(find.text('句子解析'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted novel does not restore its sentence after query navigation', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    final novel = tester.widget<NovelPage>(find.byType(NovelPage));
    final catalog = MaterialCatalogScope.of(tester.element(find.byType(NovelPage)));
    await tester.tap(
      find.ancestor(of: find.byType(RubySentence).first, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '查询选中内容'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(QueryPage)));

    await catalog.deleteMaterial(novel.item.id);
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(find.byType(NovelPage), findsNothing);
    expect(find.text('材料已删除或不可读取'), findsOneWidget);
    expect(find.text('第 1 / 5 句'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone continuous playback advances and long press pauses it', (tester) async {
    await openNovel(tester, const Size(390, 844));
    await tester.tap(find.text('连续朗读').first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MobileNovelPlaybackPanel), findsOneWidget);
    expect(
      tester.widget<MobileNovelPlaybackPanel>(find.byType(MobileNovelPlaybackPanel)).position,
      1,
    );
    await tester.pump(const Duration(seconds: 3));
    final advanced = tester.widget<MobileNovelPlaybackPanel>(find.byType(MobileNovelPlaybackPanel));
    expect(advanced.position, greaterThan(1));
    expect(advanced.continuous, isTrue);

    await tester.tap(find.widgetWithText(TextButton, '解析'));
    await tester.pump();
    await longPressSentence(tester, 0);
    expect(find.byType(MobileNovelPlaybackPanel), findsNothing);
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    final query = find.descendant(
      of: find.byType(NovelSelectionToolbar),
      matching: find.widgetWithText(TextButton, '查询'),
    );
    expect(tester.getRect(query).bottom, lessThan(844));
    await tester.tap(
      find.descendant(of: find.byType(NovelSelectionToolbar), matching: find.byTooltip('关闭')),
    );
    await tester.pump();
    final paused = tester.widget<MobileNovelPlaybackPanel>(find.byType(MobileNovelPlaybackPanel));
    expect(paused.paused, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<MobileNovelPlaybackPanel>(find.byType(MobileNovelPlaybackPanel)).position,
      paused.position,
    );
    await tester.tap(find.widgetWithText(TextButton, '停止').last);
    await tester.pump();
    expect(find.byType(MobileNovelPlaybackPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop long press queries in the right panel', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    final reader = find
        .ancestor(of: find.text('第 3 章 / 12 章'), matching: find.byType(HarukaSurface))
        .first;
    final heightBefore = tester.getSize(reader).height;
    final followingSentence = find.byType(RubySentence).at(1);
    final followingTopBefore = tester.getTopLeft(followingSentence).dy;
    await longPressSentence(tester, 0);
    expect(find.byType(NovelSelectionToolbar), findsOneWidget);
    expect(tester.getSize(find.byType(NovelSelectionToolbar)).width, lessThanOrEqualTo(360));
    expect((tester.getSize(reader).height - heightBefore).abs(), lessThan(1));
    expect((tester.getTopLeft(followingSentence).dy - followingTopBefore).abs(), lessThan(1));
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsOneWidget);
    expect(find.text('查询结果'), findsOneWidget);
    expect(find.text('暂无查询结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop selected window token opens the same word card', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    await longPressSentence(tester, 1);
    await tester.tap(find.widgetWithText(FilterChip, '窓'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NovelSelectionToolbar),
        matching: find.widgetWithText(TextButton, '查询'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NovelSelectionResultBody), findsOneWidget);
    expect(find.text('单词'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NovelSelectionResultBody), matching: find.text('まど')),
      findsOneWidget,
    );
    expect(find.text('释义'), findsOneWidget);
    expect(find.text('窗户'), findsOneWidget);
    expect(find.text('暂无查询结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop playback speed, pause, resume, and stop remain local UI state', (
    tester,
  ) async {
    await openNovel(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(OutlinedButton, '连续朗读'));
    await tester.pump();
    expect(find.byType(DesktopNovelPlaybackPanel), findsOneWidget);
    await tester.ensureVisible(find.byType(DesktopNovelPlaybackPanel));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '暂停').last);
    await tester.pump();
    expect(
      tester.widget<DesktopNovelPlaybackPanel>(find.byType(DesktopNovelPlaybackPanel)).paused,
      isTrue,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '继续').last);
    await tester.pump();
    expect(
      tester.widget<DesktopNovelPlaybackPanel>(find.byType(DesktopNovelPlaybackPanel)).paused,
      isFalse,
    );
    await tester.tap(find.widgetWithText(TextButton, '停止').last);
    await tester.pump();
    expect(find.byType(DesktopNovelPlaybackPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop reader and playback cards align at the same width', (tester) async {
    await openNovel(tester, const Size(1440, 900));
    final reader = find
        .ancestor(of: find.text('第 3 章 / 12 章'), matching: find.byType(HarukaSurface))
        .first;
    final readingWidth = tester.getSize(reader).width;
    expect(readingWidth, greaterThan(1000));
    await tester.tap(find.widgetWithText(OutlinedButton, '连续朗读'));
    await tester.pump();
    final playerWidth = tester.getSize(find.byType(DesktopNovelPlaybackPanel)).width;
    expect((readingWidth - playerWidth).abs(), lessThan(2));
    expect(tester.takeException(), isNull);
  });
}

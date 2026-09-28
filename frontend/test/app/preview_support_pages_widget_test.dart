import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';

import '../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/presentation/daily_words_page.dart';
import 'package:haruka/features/ai_exercises/presentation/exercise_support_pages.dart';
import 'package:haruka/features/notifications/presentation/notifications_page.dart';
import 'package:haruka/features/jobs/presentation/jobs_page.dart';
import 'package:haruka/features/exams/presentation/exam_session_page.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';

import '../features/library/material_catalog_widget_test.mocks.dart';

void main() {
  Future<PreviewFixtureStore> launch(WidgetTester tester, Size size, String path) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PreviewPageFrame).first);
    final store = PreviewStoreScope.of(context);
    GoRouter.of(context).go(path);
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('daily words selects the mobile list and desktop summary layout', (tester) async {
    await launch(tester, const Size(390, 844), AppRoutes.mockDailyWords);
    expect(find.byType(MobileDailyWordsView), findsOneWidget);
    expect(find.byType(DesktopDailyWordsView), findsNothing);
    expect(find.text('そっと'), findsOneWidget);
    expect(find.text('微笑む'), findsOneWidget);
    await tester.tap(find.text('2026-09-27'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-09-27'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(find.text('穏やか'), findsOneWidget);
    expect(find.text('そっと'), findsNothing);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDailyWordsView), findsOneWidget);
    expect(find.byType(MobileDailyWordsView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily words uses the account timezone at a UTC day boundary', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockDailyWords);
    expect(find.text('そっと'), findsOneWidget);
    expect(find.text('微笑む'), findsOneWidget);
    store.updateProfileDetails(
      name: store.displayName,
      birthYear: store.birthYear,
      gender: store.gender,
      timezone: 'UTC',
      allowProfileForAi: store.allowProfileForAi,
    );
    await tester.pumpAndSettle();
    expect(find.text('そっと'), findsOneWidget);
    expect(find.text('微笑む'), findsNothing);
    expect(find.textContaining('UTC ·'), findsOneWidget);
    store.updateProfileDetails(
      name: store.displayName,
      birthYear: store.birthYear,
      gender: store.gender,
      timezone: 'Asia/Shanghai',
      allowProfileForAi: store.allowProfileForAi,
    );
    await tester.pumpAndSettle();
    expect(find.text('微笑む'), findsOneWidget);
    expect(find.textContaining('Asia/Shanghai ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily words empty date keeps the date control and guidance on both layouts', (
    tester,
  ) async {
    await launch(tester, const Size(390, 844), AppRoutes.mockDailyWords);
    await tester.tap(find.text('2026-09-27'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('23').last);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileDailyWordsView), findsOneWidget);
    expect(find.text('2026-09-23'), findsOneWidget);
    expect(find.text('这天没有加入单词'), findsOneWidget);
    expect(find.text('选择其他日期查看。'), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDailyWordsView), findsOneWidget);
    expect(find.text('这天没有加入单词'), findsOneWidget);
    expect(find.text('选择其他日期查看。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mistake favorite survives returning to the desktop list', (tester) async {
    await launch(tester, const Size(1440, 900), AppRoutes.mockMistakes);
    expect(find.byType(DesktopMistakesView), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('移动方向与目的地'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopMistakeDetailView), findsOneWidget);
    await tester.tap(find.text('收藏错题'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(PreviewPageFrame).first)).go(AppRoutes.mockMistakes);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('targeted mistake generation preselects the current mistake and still reviews', (
    tester,
  ) async {
    await launch(tester, const Size(390, 844), AppRoutes.mockMistakePath(0));
    await tester.tap(find.text('针对它出题'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseBuilderPage), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, '错题')).value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, '单词本')).value,
      isFalse,
    );
    expect(find.text('移动方向与目的地'), findsOneWidget);
    await tester.tap(find.text('下一步 · 设置与确认'));
    await tester.pumpAndSettle();
    expect(find.text('移动方向与目的地'), findsOneWidget);
    expect(find.text('修改来源'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, '确认生成习题');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final countMenu = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(countMenu);
    await tester.tap(countMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 题').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('题目 1 / 1 · 日语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('builder requires concrete source and resets reuse after condition changes', (
    tester,
  ) async {
    await launch(tester, const Size(390, 844), AppRoutes.mockExerciseBuilder);
    final next = find.widgetWithText(FilledButton, '下一步 · 设置与确认');
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    final firstNotebook = find.widgetWithText(CheckboxListTile, '日常的细节');
    await tester.ensureVisible(firstNotebook);
    await tester.tap(firstNotebook);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.ensureVisible(firstNotebook);
    await tester.tap(firstNotebook);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('そっと'), findsOneWidget);
    expect(find.text('穏やか'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, '确认生成习题');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final reuse = find.widgetWithText(CheckboxListTile, '候选不足时允许同一来源多题');
    await tester.ensureVisible(reuse);
    await tester.tap(reuse);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    final typeMenu = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(typeMenu);
    await tester.tap(typeMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('词义选择').last);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(reuse).value, isFalse);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.textContaining('词义选择 · 5 题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifications mark all read and open the selected material', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockNotifications);
    expect(find.byType(MobileNotificationsView), findsOneWidget);
    expect(store.unreadCount, 2);
    await tester.tap(find.text('全部标为已读'));
    await tester.pumpAndSettle();
    expect(store.unreadCount, 0);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNotificationsView), findsOneWidget);
    await tester.tap(find.text('「夏の手紙」已可阅读'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .path,
      AppRoutes.mockMaterialPath(store.materials.first.id),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification target is rechecked after deletion and never rebound by type', (
    tester,
  ) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockNotifications);
    final deletedId = store.materials.first.id;
    final deletedType = store.materials.first.type;
    store.deleteMaterial(deletedId);
    store.importMaterial(deletedType, 'Another book', 'ja');
    await tester.pumpAndSettle();

    await tester.tap(find.text('「夏の手紙」已可阅读'));
    await tester.pumpAndSettle();
    final route = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
        .routeInformationProvider
        .value
        .uri
        .path;
    expect(route, AppRoutes.mockNotifications);
    expect(find.text('材料已删除或不可读取'), findsWidgets);
    expect(store.notifications.first.readAt, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('textbook notification opens its own material', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockNotifications);
    await tester.tap(find.text('「日语的日常表达」已完成解析'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .path,
      AppRoutes.mockMaterialPath(store.materials[1].id),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked notification target stays on the list and hides its title', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockNotifications);
    store.revokeMaterialRead(store.materials.first.id);
    await tester.pumpAndSettle();
    await tester.tap(find.text('「夏の手紙」已可阅读'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .path,
      AppRoutes.mockNotifications,
    );
    expect(find.text('「夏の手紙」已可阅读'), findsNothing);
    expect(find.text('材料已删除或不可读取'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('job progress comes from the active material and disables opening', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockJobs);
    expect(find.byType(MobileJobsView), findsOneWidget);
    expect(find.text('解析中 · 35%'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      store.materials.last.activeJobProgressPercent! / 100,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '打开材料 →')).onPressed,
      isNull,
    );
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopJobsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('job page reads injected catalog rather than preview fixture materials', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final material = MaterialSummary(
      id: '55555555-5555-4555-8555-555555555555',
      type: LearningMaterialType.novel,
      title: '注入的任务材料',
      language: 'ja',
      status: 'processing',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '',
      cover: '任',
      activeJobProgressPercent: 100,
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(PreviewPageFrame).first)).go(AppRoutes.mockJobs);
    await tester.pumpAndSettle();
    expect(find.text('注入的任务材料'), findsOneWidget);
    expect(find.text('雨上がり'), findsNothing);
    expect(find.text('解析中 · 100%'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '打开材料 →')).onPressed,
      isNull,
    );
    verify(catalog.filterMaterials(any)).called(greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed active material is hidden on the open job page', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockJobs);
    final catalog = MaterialCatalogScope.of(tester.element(find.byType(JobsPage)));
    final activeId = store.materials.last.id;
    expect(find.text('雨上がり'), findsOneWidget);
    store.deleteMaterial(activeId);
    await catalog.refresh(force: true);
    await tester.pumpAndSettle();
    expect(find.text('雨上がり'), findsNothing);
    expect(find.text('解析中 · 35%'), findsNothing);
    expect(find.text('暂不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('job opening follows published readability rather than percent', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = MockMaterialCatalog();
    final material = MaterialSummary(
      id: '66666666-6666-4666-8666-666666666666',
      type: LearningMaterialType.novel,
      title: '正文已发布的小说',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '',
      cover: '书',
      activeJobProgressPercent: 35,
    );
    when(catalog.status).thenReturn(MaterialCatalogStatus.ready);
    when(catalog.filterMaterials(any)).thenReturn([material]);
    await tester.pumpWidget(buildTestPreviewApp(materialCatalog: catalog));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(PreviewPageFrame).first)).go(AppRoutes.mockJobs);
    await tester.pumpAndSettle();
    expect(find.text('正文已发布的小说'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '打开材料 →')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnosis uses separate layouts and opens the selected textbook', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockDiagnosis);
    expect(find.byType(MobileDiagnosisView), findsOneWidget);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDiagnosisView), findsOneWidget);
    await tester.tap(find.text('回到教材 →'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .path,
      AppRoutes.mockMaterialPath(store.materials[1].id),
    );
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .queryParameters['unit'],
      '2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile exam card, save, leave and resume retain the draft', (tester) async {
    final store = await launch(tester, const Size(390, 844), AppRoutes.mockExamSession);
    expect(find.byType(MobileExamSessionView), findsOneWidget);
    expect(find.text('已答 0 / 3'), findsOneWidget);
    await tester.tap(find.text('平静温和'));
    await tester.pumpAndSettle();
    expect(store.examDraftAnswers[0], 0);
    expect(find.text('已答 1 / 3'), findsOneWidget);
    await tester.tap(find.text('标记稍后检查'));
    await tester.pumpAndSettle();
    expect(store.examMarkedQuestions, contains(0));
    await tester.tap(find.text('答题卡'));
    await tester.pumpAndSettle();
    expect(find.text('已标记'), findsOneWidget);
    expect(find.text('未答'), findsNWidgets(2));
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(store.examCurrentQuestion, 1);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.examDraftSaved, isTrue);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('暂时离开考试？'), findsOneWidget);
    await tester.tap(find.text('继续作答'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamSessionView), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存并离开'));
    await tester.pumpAndSettle();
    expect(store.examSubmitted, isFalse);
    expect(store.examDraftAnswers[0], 0);
    expect(store.examMarkedQuestions, contains(0));
    expect(store.examCurrentQuestion, 1);
    GoRouter.of(tester.element(find.byType(PreviewPageFrame).first)).go(AppRoutes.mockExamSession);
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamSessionView), findsOneWidget);
    expect(find.text('第 2 题'), findsOneWidget);
    expect(find.text('已答 1 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop exam answer card and submit confirmation use the saved draft', (
    tester,
  ) async {
    final store = await launch(tester, const Size(1440, 900), AppRoutes.mockExamSession);
    expect(find.byType(DesktopExamSessionView), findsOneWidget);
    expect(find.text('答题卡'), findsOneWidget);
    await tester.tap(find.text('平静温和'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记稍后检查'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    expect(store.examDraftSaved, isTrue);
    expect(find.textContaining('已答 1 / 3 · 已保存'), findsOneWidget);
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    expect(find.text('确认交卷？'), findsOneWidget);
    await tester.tap(find.text('继续作答'));
    await tester.pumpAndSettle();
    expect(store.examSubmitted, isFalse);
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认交卷'));
    await tester.pumpAndSettle();
    expect(store.examSubmitted, isTrue);
    expect(store.examDraftAnswers[0], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop exam sidebar navigation asks before leaving', (tester) async {
    final store = await launch(tester, const Size(1440, 900), AppRoutes.mockExamSession);
    await tester.tap(find.text('平静温和'));
    await tester.pumpAndSettle();
    expect(store.examDraftAnswers[0], 0);
    await tester.tap(find.text('单词本').first);
    await tester.pumpAndSettle();
    expect(find.text('暂时离开考试？'), findsOneWidget);
    await tester.tap(find.text('继续作答'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopExamSessionView), findsOneWidget);
    expect(store.examDraftAnswers[0], 0);
    await tester.tap(find.text('单词本').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂时离开'));
    await tester.pumpAndSettle();
    expect(store.examDraftSaved, isTrue);
    expect(store.examSubmitted, isFalse);
    expect(
      GoRouter.of(tester.element(find.byType(PreviewPageFrame).first))
          .routeInformationProvider
          .value
          .uri
          .path,
      AppRoutes.mockNotebooks,
    );
    expect(tester.takeException(), isNull);
  });
}

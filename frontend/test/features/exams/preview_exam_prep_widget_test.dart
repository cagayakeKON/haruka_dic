import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/app/preview_shell.dart';

void main() {
  setUpAll(initializeTestDatabase);
  Future<void> openExam(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('N2 模拟试卷'));
    await tester.pumpAndSettle();
    expect(find.byType(ExamPrepPage), findsOneWidget);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('phone question review validates, cancels, and gates start', (tester) async {
    await openExam(tester, const Size(390, 844));
    final start = find.widgetWithText(FilledButton, '确认版本并开考');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tapVisible(tester, find.text('校对题号与分值'));
    expect(find.byType(MobileExamQuestionReviewSheet), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '9');
    await tapVisible(tester, find.text('取消'));
    expect(find.text('已提取 · 待校对'), findsOneWidget);

    await tapVisible(tester, find.text('校对题号与分值'));
    final number = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(number).controller!.text, '1');
    await tester.enterText(number, '0');
    await tapVisible(tester, find.text('确认校对'));
    expect(find.text('请输入大于 0 的题号'), findsOneWidget);
    await tester.enterText(number, '2');
    await tapVisible(tester, find.text('确认校对'));
    expect(find.text('题号不能重复'), findsNWidgets(2));
    await tester.enterText(number, '1');
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tapVisible(tester, find.text('确认校对'));
    expect(find.text('请输入大于 0 的分值'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '1');
    await tapVisible(tester, find.text('确认校对'));
    expect(find.byType(MobileExamQuestionReviewSheet), findsNothing);
    expect(find.text('已校对'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tapVisible(tester, find.text('校对听力稿'));
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('确认候选匹配'));
    await tapVisible(tester, find.text('生成听力音频'));
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop script candidate supports reject and rebind', (tester) async {
    await openExam(tester, const Size(1440, 900));
    expect(find.text('题号、题组与分值'), findsOneWidget);
    expect(find.text('待人工校对'), findsOneWidget);
    await tapVisible(tester, find.text('校对题号与分值'));
    expect(find.byType(DesktopExamQuestionReviewDialog), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
    await tapVisible(tester, find.text('校对听力候选'));
    expect(find.byType(DesktopExamScriptReviewDialog), findsOneWidget);
    expect(find.text('明日は駅の南口で会いましょう。'), findsOneWidget);
    expect(find.text('来源：试卷正文 · 听力题组 1。'), findsOneWidget);
    await tapVisible(tester, find.text('拒绝候选'));
    expect(find.text('候选已拒绝'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '生成音频')).onPressed,
      isNull,
    );

    await tapVisible(tester, find.text('校对听力候选'));
    await tapVisible(tester, find.text('调整关联'));
    await tapVisible(tester, find.byType(DropdownButtonFormField<int>));
    await tapVisible(tester, find.text('小题 02').last);
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('确认匹配'));
    expect(find.text('已确认'), findsOneWidget);
    await tapVisible(tester, find.text('校对听力候选'));
    await tapVisible(tester, find.text('调整关联'));
    expect(find.text('小题 02'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('关闭'));
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '生成音频')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing reviewed scores invalidates the confirmed script and audio', (
    tester,
  ) async {
    await openExam(tester, const Size(390, 844));
    await tapVisible(tester, find.text('校对题号与分值'));
    await tapVisible(tester, find.text('确认校对'));
    await tapVisible(tester, find.text('校对听力稿'));
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('确认候选匹配'));
    await tapVisible(tester, find.text('生成听力音频'));
    final start = find.widgetWithText(FilledButton, '确认版本并开考');
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);

    await tapVisible(tester, find.text('校对题号与分值'));
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    await tapVisible(tester, find.text('确认校对'));
    expect(find.text('待确认脚本与题组'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '生成听力音频')).onPressed,
      isNull,
    );
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved exam draft can continue after reopening preparation', (tester) async {
    await openExam(tester, const Size(390, 844));
    final store = PreviewStoreScope.of(tester.element(find.byType(ExamPrepPage)));
    store.chooseExamAnswer(0, 1);
    store.selectExamQuestion(2);
    store.saveExamDraft();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('继续作答'));
    expect(store.examDraftAnswers[0], 1);
    expect(store.examCurrentQuestion, 2);
    expect(store.examSubmitted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewed preparation remains ready after leaving the exam session', (tester) async {
    await openExam(tester, const Size(390, 844));
    final store = PreviewStoreScope.of(tester.element(find.byType(ExamPrepPage)));
    final examId = store.materials.firstWhere((item) => item.title == 'N2 模拟试卷').id;
    await tapVisible(tester, find.text('校对题号与分值'));
    await tapVisible(tester, find.text('确认校对'));
    await tapVisible(tester, find.text('校对听力稿'));
    await tapVisible(tester, find.byType(CheckboxListTile));
    await tapVisible(tester, find.text('确认候选匹配'));
    await tapVisible(tester, find.text('生成听力音频'));
    expect(store.examPrepFor(examId)?.audioReady, isTrue);

    await tapVisible(tester, find.text('确认版本并开考'));
    await tapVisible(tester, find.byTooltip('返回'));
    expect(find.text('暂时离开考试？'), findsOneWidget);
    await tapVisible(tester, find.text('保存并离开'));
    expect(find.byType(ExamPrepPage), findsOneWidget);
    expect(find.text('已校对'), findsOneWidget);
    expect(find.text('已确认脚本与题组'), findsOneWidget);
    expect(find.text('已生成'), findsOneWidget);
    expect(find.text('继续作答'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

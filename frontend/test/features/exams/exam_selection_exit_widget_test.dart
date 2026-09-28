import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/exams/presentation/exam_result_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/domain/learning_records.dart';

void main() {
  testWidgets('exam text popover releases the page as soon as close is tapped', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore()..submitExam({0: 0});
    addTearDown(store.dispose);
    final examId = store.materials.firstWhere((item) => item.type == LearningMaterialType.exam).id;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const ExamResultPage()),
        GoRoute(
          path: '/mock/material/:id',
          builder: (context, state) => Scaffold(body: Text('prep:${state.pathParameters['id']}')),
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
    await tester.longPress(find.text('「穏やか」に最接近的意思是？'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamSelectionPopover), findsOneWidget);
    await tester.tap(find.byTooltip('收起选区工具'));
    await tester.pump();
    expect(find.byType(MobileExamSelectionPopover), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('prep:$examId'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

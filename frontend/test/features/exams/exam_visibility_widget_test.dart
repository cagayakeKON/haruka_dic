import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/dev/preview/exam_fixture.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/exams/data/exam_projections.dart';
import 'package:haruka/features/exams/presentation/exam_result_page.dart';
import 'package:haruka/features/exams/presentation/exam_session_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/l10n/app_localizations_zh.dart';

void main() {
  testWidgets('session page renders the scoped paper projection', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const ExamSessionPage())],
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
    final context = tester.element(find.byType(ExamSessionPage));
    final state = previewExamProjection(store, AppLocalizations.of(context));
    state.openSession(
      accountBinding: state.accountBinding!,
      sessionId: state.sessionId!,
      paperVersion: state.paperVersion!,
      paper: [
        for (var index = 0; index < 3; index++)
          ExamPaperQuestion(
            id: 'q-$index',
            category: 'category',
            sessionGroup: 'group',
            prompt: 'projection-prompt-$index',
            options: const ['A', 'B', 'C', 'D'],
          ),
      ],
    );
    store.selectExamQuestion(1);
    await tester.pumpAndSettle();
    expect(find.text('projection-prompt-1'), findsOneWidget);
    expect(find.text('projection-prompt-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'active listening question never renders hidden transcript or answer on either layout',
    (tester) async {
      final store = PreviewFixtureStore()..selectExamQuestion(2);
      final paper = previewExamPaper(AppLocalizationsZh());
      addTearDown(store.dispose);

      Future<void> showSession(Widget session) async {
        await tester.pumpWidget(
          PreviewStoreScope(
            store: store,
            child: MaterialApp(
              theme: HarukaTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: session),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(tester.element(find.byType(session.runtimeType)));
        expect(find.text(l10n.mockSupportExamQuestionListening), findsOneWidget);
        expect(find.text(l10n.mockMaterialExamScriptCandidateText), findsNothing);
        expect(
          find.text(l10n.mockLearningResultReference(l10n.mockSupportExamOptionStationSouthExit)),
          findsNothing,
        );
      }

      await showSession(
        MobileExamSessionView(store: store, paper: paper, onAnswerCard: () {}, onSubmit: () {}),
      );
      await showSession(DesktopExamSessionView(store: store, paper: paper, onSubmit: () {}));
    },
  );

  Future<void> openResult(WidgetTester tester, PreviewFixtureStore store) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(store.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const ExamResultPage()),
        GoRoute(
          path: '/mock/exam/session',
          builder: (context, state) => const Scaffold(body: Text('session')),
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
  }

  testWidgets('deep link cannot reveal review before confirmed submission', (tester) async {
    final store = PreviewFixtureStore();
    await openResult(tester, store);

    final context = tester.element(find.byType(ExamResultPage));
    final l10n = AppLocalizations.of(context);
    expect(previewSubmittedExamReview(l10n, submitted: false), isNull);
    expect(find.byType(MobileExamResultView), findsNothing);
    expect(
      find.text(l10n.mockLearningResultReference(l10n.mockSupportExamOptionCalm)),
      findsNothing,
    );
    expect(find.text(l10n.mockSupportExamSubmitConfirmBody), findsOneWidget);
  });

  testWidgets('confirmed submission exposes the separate review projection', (tester) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    await openResult(tester, store);

    final context = tester.element(find.byType(ExamResultPage));
    final l10n = AppLocalizations.of(context);
    final review = previewSubmittedExamReview(l10n, submitted: store.examSubmitted);
    expect(review, hasLength(3));
    expect(review!.first.correctOption, 0);
    expect(find.byType(MobileExamResultView), findsOneWidget);
    expect(
      find.text(l10n.mockLearningResultReference(l10n.mockSupportExamOptionCalm)),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible review follows the effective run and account projection', (tester) async {
    final store = PreviewFixtureStore()..submitExam({0: 0});
    await openResult(tester, store);
    final context = tester.element(find.byType(ExamResultPage));
    final state = previewExamProjection(store, AppLocalizations.of(context));
    expect(find.byType(MobileExamResultView), findsOneWidget);

    expect(
      state.publishEffectiveGrade(
        ExamGradePublication(
          accountBinding: state.accountBinding!,
          sessionId: state.sessionId!,
          paperVersion: state.paperVersion!,
          generation: 2,
          runId: 'new-effective-run',
          awardedPoints: 2,
        ),
      ),
      isTrue,
    );
    final localized = previewExamProjection(store, _AlternateExamLocalizations());
    expect(identical(localized, state), isTrue);
    expect(localized.paper.first.prompt, 'localized-preview-question');
    expect(localized.effectiveGrade?.generation, 2);
    expect(localized.review, isEmpty);
    store.selectExamQuestion(1);
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamResultView), findsNothing);

    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: state.accountBinding!,
          sessionId: state.sessionId!,
          paperVersion: state.paperVersion!,
          generation: 1,
          runId: 'old-run',
          questions: [
            for (final paper in state.paper) ExamReviewQuestion(paper: paper, correctOption: 0),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: state.accountBinding!,
          sessionId: state.sessionId!,
          paperVersion: state.paperVersion!,
          generation: 2,
          runId: 'new-effective-run',
          questions: [
            for (final paper in state.paper) ExamReviewQuestion(paper: paper, correctOption: 0),
          ],
        ),
      ),
      isTrue,
    );
    store.selectExamQuestion(2);
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamResultView), findsOneWidget);

    state.bindAccount('another-account');
    store.selectExamQuestion(0);
    await tester.pumpAndSettle();
    expect(find.byType(MobileExamResultView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _AlternateExamLocalizations extends AppLocalizationsZh {
  _AlternateExamLocalizations() : super('zh-alt');

  @override
  String get mockSupportExamQuestionMeaning => 'localized-preview-question';
}

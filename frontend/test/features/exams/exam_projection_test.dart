import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/exams/data/exam_projections.dart';

void main() {
  ExamPaperQuestion question(String id) => ExamPaperQuestion(
    id: id,
    category: 'reading',
    sessionGroup: 'reading',
    prompt: 'Choose a meaning',
    options: ['first', 'second'],
  );

  test('paper and submitted review have separate visibility and immutable data', () {
    final paper = question('q-1');
    final state = ExamProjectionState()..bindAccount('account-a');
    state.openSession(
      accountBinding: 'account-a',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
      paper: [paper],
    );

    expect(state.submitted, isFalse);
    expect(state.review, isEmpty);
    expect(() => state.paper.add(question('q-2')), throwsUnsupportedError);
    expect(() => paper.options.add('hidden answer'), throwsUnsupportedError);

    final review = ExamReviewQuestion(paper: paper, correctOption: 1);
    expect(
      state.confirmSubmission(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v0',
      ),
      isFalse,
    );
    expect(state.review, isEmpty);
    expect(
      state.confirmSubmission(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
      ),
      isTrue,
    );
    expect(state.review, isEmpty);
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 0,
          runId: 'submitted-review',
          questions: [review],
        ),
      ),
      isTrue,
    );
    expect(state.review.single.correctOption, 1);
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 0,
          runId: 'late-duplicate',
          questions: [ExamReviewQuestion(paper: paper, correctOption: 0)],
        ),
      ),
      isFalse,
    );
    expect(state.review.single.correctOption, 1);
  });

  test('other account and mismatched question cannot publish a review', () {
    final state = ExamProjectionState()..bindAccount('account-b');
    state.openSession(
      accountBinding: 'account-b',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
      paper: [question('q-1')],
    );
    expect(
      state.confirmSubmission(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
      ),
      isFalse,
    );
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-b',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 0,
          runId: 'run-0',
          questions: [ExamReviewQuestion(paper: question('other-q'), correctOption: 0)],
        ),
      ),
      isFalse,
    );
    expect(state.submitted, isFalse);
    state.bindAccount('account-a');
    expect(state.paper, isEmpty);
    expect(state.review, isEmpty);
    expect(state.sessionId, isNull);
  });

  test('late and duplicate grading runs do not replace the effective generation', () {
    final paper = question('q-1');
    final state = ExamProjectionState()..bindAccount('account-a');
    state.openSession(
      accountBinding: 'account-a',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
      paper: [paper],
    );
    ExamGradePublication grade(int generation, String runId, {String account = 'account-a'}) =>
        ExamGradePublication(
          accountBinding: account,
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: generation,
          runId: runId,
          awardedPoints: generation,
        );
    expect(state.publishEffectiveGrade(grade(1, 'run-1')), isFalse);
    expect(
      state.confirmSubmission(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
      ),
      isTrue,
    );
    expect(state.publishEffectiveGrade(grade(2, 'run-2')), isTrue);
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 1,
          runId: 'late-run',
          questions: [ExamReviewQuestion(paper: paper, correctOption: 1)],
        ),
      ),
      isFalse,
    );
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 2,
          runId: 'run-2',
          questions: [ExamReviewQuestion(paper: paper, correctOption: 0)],
        ),
      ),
      isTrue,
    );
    expect(state.publishEffectiveGrade(grade(1, 'late-run')), isFalse);
    expect(state.publishEffectiveGrade(grade(2, 'duplicate-run')), isFalse);
    expect(state.publishEffectiveGrade(grade(3, 'other-account', account: 'account-b')), isFalse);
    expect(state.effectiveGrade?.runId, 'run-2');
    expect(state.publishEffectiveGrade(grade(3, 'run-3')), isTrue);
    expect(state.effectiveGrade?.runId, 'run-3');
    expect(state.review, isEmpty);
    state.clear();
    expect(state.effectiveGrade, isNull);
  });

  test('same generation from another run removes the earlier review', () {
    final paper = question('q-1');
    final state = ExamProjectionState()..bindAccount('account-a');
    state.openSession(
      accountBinding: 'account-a',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
      paper: [paper],
    );
    expect(
      state.confirmSubmission(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
      ),
      isTrue,
    );
    expect(
      state.publishReview(
        ExamReviewPublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 2,
          runId: 'run-old',
          questions: [ExamReviewQuestion(paper: paper, correctOption: 0)],
        ),
      ),
      isTrue,
    );
    expect(
      state.publishEffectiveGrade(
        const ExamGradePublication(
          accountBinding: 'account-a',
          sessionId: 'session-1',
          paperVersion: 'paper-v1',
          generation: 2,
          runId: 'run-effective',
          awardedPoints: 1,
        ),
      ),
      isTrue,
    );
    expect(state.review, isEmpty);
    expect(state.effectiveGrade?.runId, 'run-effective');
  });

  test('localized text replacement preserves grade identity and never revives an old review', () {
    final original = question('q-1');
    final state = ExamProjectionState()..bindAccount('account-a');
    state.openSession(
      accountBinding: 'account-a',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
      paper: [original],
    );
    state.confirmSubmission(
      accountBinding: 'account-a',
      sessionId: 'session-1',
      paperVersion: 'paper-v1',
    );
    state.publishEffectiveGrade(
      const ExamGradePublication(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
        generation: 1,
        runId: 'run-1',
        awardedPoints: 1,
      ),
    );
    state.publishReview(
      ExamReviewPublication(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
        generation: 1,
        runId: 'run-1',
        questions: [ExamReviewQuestion(paper: original, correctOption: 1)],
      ),
    );
    final localized = ExamPaperQuestion(
      id: 'q-1',
      category: '阅读',
      sessionGroup: '阅读',
      prompt: '已翻译的题面',
      options: ['甲', '乙'],
    );
    expect(
      state.replaceLocalizedPaper(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
        paper: [localized],
      ),
      isTrue,
    );
    expect(state.paper.single.prompt, '已翻译的题面');
    expect(state.review.single.options, ['甲', '乙']);
    expect(state.review.single.correctOption, 1);
    expect(state.effectiveGrade?.runId, 'run-1');

    state.publishEffectiveGrade(
      const ExamGradePublication(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
        generation: 2,
        runId: 'run-2',
        awardedPoints: 0,
      ),
    );
    expect(state.review, isEmpty);
    expect(
      state.replaceLocalizedPaper(
        accountBinding: 'account-a',
        sessionId: 'session-1',
        paperVersion: 'paper-v1',
        paper: [original],
      ),
      isTrue,
    );
    expect(state.effectiveGrade?.generation, 2);
    expect(state.review, isEmpty);
  });
}

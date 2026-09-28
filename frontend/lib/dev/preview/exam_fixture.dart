import 'package:haruka/features/exams/data/exam_projections.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

import 'fixture_store.dart';

const _previewAccountBinding = 'preview-account';
const _previewSessionId = 'preview-exam-session';
const _previewPaperVersion = 'preview-paper-v1';
const _previewGradeRunId = 'preview-rule-grade-v1';

final _previewProjections = Expando<({String localeName, ExamProjectionState state})>();

/// Keeps the mock exam's paper, submission and published grade in one
/// per-store, process-memory projection. No exam object enters CacheCoordinator.
ExamProjectionState previewExamProjection(PreviewFixtureStore store, AppLocalizations l10n) {
  var holder = _previewProjections[store];
  if (holder == null) {
    final state = ExamProjectionState()..bindAccount(_previewAccountBinding);
    state.openSession(
      accountBinding: _previewAccountBinding,
      sessionId: _previewSessionId,
      paperVersion: _previewPaperVersion,
      paper: previewExamPaper(l10n),
    );
    holder = (localeName: l10n.localeName, state: state);
    _previewProjections[store] = holder;
  } else if (holder.localeName != l10n.localeName &&
      holder.state.replaceLocalizedPaper(
        accountBinding: _previewAccountBinding,
        sessionId: _previewSessionId,
        paperVersion: _previewPaperVersion,
        paper: previewExamPaper(l10n),
      )) {
    holder = (localeName: l10n.localeName, state: holder.state);
    _previewProjections[store] = holder;
  }
  final state = holder.state;
  if (store.examSubmitted && !state.submitted) {
    state.confirmSubmission(
      accountBinding: _previewAccountBinding,
      sessionId: _previewSessionId,
      paperVersion: _previewPaperVersion,
    );
    // The preview source publishes its deterministic rule grade immediately.
    // The real repository must wait for the server's effective publication.
    final review = previewSubmittedExamReview(l10n, submitted: true)!;
    final points = [
      for (var index = 0; index < review.length; index++)
        if (store.examAnswers[index] == review[index].correctOption) 1,
    ].length;
    state.publishEffectiveGrade(
      ExamGradePublication(
        accountBinding: _previewAccountBinding,
        sessionId: _previewSessionId,
        paperVersion: _previewPaperVersion,
        generation: 1,
        runId: _previewGradeRunId,
        awardedPoints: points,
      ),
    );
    state.publishReview(
      ExamReviewPublication(
        accountBinding: _previewAccountBinding,
        sessionId: _previewSessionId,
        paperVersion: _previewPaperVersion,
        generation: 1,
        runId: _previewGradeRunId,
        questions: review,
      ),
    );
  }
  return state;
}

/// Preview source for the active-session DTO. The result-only fields are kept
/// in [previewSubmittedExamReview] and never passed to the session views.
List<ExamPaperQuestion> previewExamPaper(AppLocalizations l10n) => [
  ExamPaperQuestion(
    id: 'e1111111-1111-4111-8111-111111111111',
    category: l10n.mockLearningResultLanguageCategory,
    sessionGroup: l10n.mockSupportExamLanguageKnowledge,
    prompt: l10n.mockSupportExamQuestionMeaning,
    options: [
      l10n.mockSupportExamOptionCalm,
      l10n.mockSupportExamOptionRapid,
      l10n.mockSupportExamOptionComplex,
      l10n.mockSupportExamOptionSurprising,
    ],
  ),
  ExamPaperQuestion(
    id: 'e2222222-2222-4222-8222-222222222222',
    category: l10n.mockLearningResultReadingCategory,
    sessionGroup: l10n.mockSupportExamReading,
    prompt: l10n.mockSupportExamQuestionReading,
    options: [
      l10n.mockSupportExamOptionForgotPromise,
      l10n.mockSupportExamOptionRememberedFriend,
      l10n.mockSupportExamOptionHeardBroadcast,
      l10n.mockSupportExamOptionMetTeacher,
    ],
  ),
  ExamPaperQuestion(
    id: 'e3333333-3333-4333-8333-333333333333',
    category: l10n.mockLearningResultListeningCategory,
    sessionGroup: l10n.mockSupportExamListening,
    prompt: l10n.mockSupportExamQuestionListening,
    options: [
      l10n.mockSupportExamOptionLibraryEntrance,
      l10n.mockSupportExamOptionStationSouthExit,
      l10n.mockSupportExamOptionParkEntrance,
      l10n.mockSupportExamOptionSchoolHall,
    ],
  ),
];

List<ExamReviewQuestion>? previewSubmittedExamReview(
  AppLocalizations l10n, {
  required bool submitted,
}) {
  if (!submitted) return null;
  final paper = previewExamPaper(l10n);
  return [
    ExamReviewQuestion(paper: paper[0], correctOption: 0),
    ExamReviewQuestion(paper: paper[1], correctOption: 1),
    ExamReviewQuestion(paper: paper[2], correctOption: 1),
  ];
}

/// Fixed NLP hints belong to the preview source. A future API review DTO
/// supplies versioned token spans and does not depend on this mock analysis.
List<({String text, int start, int end})> previewExamTextTokens(String text) {
  const hints = [
    '穏やか',
    '主人公',
    '图书馆',
    '为什么',
    '接近',
    '意思',
    '平静',
    '温和',
    '迅速',
    '猛烈',
    '十分',
    '复杂',
    '令人',
    '惊讶',
    '忘记',
    '约定',
    '想起',
    '旧友',
    '听到',
    '广播',
    '遇见',
    '老师',
    '听力',
    '题组',
    '两人',
    '最后',
    '决定',
    '哪里',
    '见面',
    '门口',
    '车站',
    '南口',
    '公园',
    '入口',
    '学校',
    '大厅',
    '停下',
    '脚步',
  ];
  final grouped = RegExp(
    r'[A-Za-z0-9]+|[\u3400-\u9fff][\u3040-\u309f]+|[\u3040-\u30ff]+',
    unicode: true,
  );
  final word = RegExp(r'[\u3040-\u30ff\u3400-\u9fffA-Za-z0-9]', unicode: true);
  final grapheme = RegExp(r'.', unicode: true);
  final parts = <({String text, int start, int end})>[];
  var offset = 0;
  while (offset < text.length) {
    final character = grapheme.matchAsPrefix(text, offset)!;
    if (!word.hasMatch(character.group(0)!)) {
      offset = character.end;
      continue;
    }
    String? known;
    for (final hint in hints) {
      if (text.startsWith(hint, offset) && (known == null || hint.length > known.length)) {
        known = hint;
      }
    }
    final end = known == null
        ? (grouped.matchAsPrefix(text, offset)?.end ?? character.end)
        : offset + known.length;
    parts.add((text: text.substring(offset, end), start: offset, end: end));
    offset = end;
  }
  return parts.isEmpty ? [(text: text.trim(), start: 0, end: text.length)] : parts;
}

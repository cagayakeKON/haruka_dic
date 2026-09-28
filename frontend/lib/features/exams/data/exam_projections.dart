import 'dart:collection';

/// The active-session projection contains only fields visible before submission.
/// It deliberately has no answer, rubric, grade, or listening transcript member.
final class ExamPaperQuestion {
  ExamPaperQuestion({
    required this.id,
    required this.category,
    required this.sessionGroup,
    required this.prompt,
    required List<String> options,
  }) : options = List.unmodifiable(options);

  final String id;
  final String category;
  final String sessionGroup;
  final String prompt;
  final List<String> options;
}

/// A separate projection is available only after submission is confirmed.
final class ExamReviewQuestion {
  ExamReviewQuestion({required this.paper, required this.correctOption}) {
    if (correctOption < 0 || correctOption >= paper.options.length) {
      throw RangeError.range(correctOption, 0, paper.options.length - 1, 'correctOption');
    }
  }

  final ExamPaperQuestion paper;
  final int correctOption;

  String get id => paper.id;
  String get category => paper.category;
  String get prompt => paper.prompt;
  List<String> get options => paper.options;
}

/// A grade is an online, effective projection. Historical runs are not allowed
/// to replace a newer effective run in the visible session state.
final class ExamGradePublication {
  const ExamGradePublication({
    required this.accountBinding,
    required this.sessionId,
    required this.paperVersion,
    required this.generation,
    required this.runId,
    required this.awardedPoints,
  });

  final String accountBinding;
  final String sessionId;
  final String paperVersion;
  final int generation;
  final String runId;
  final num awardedPoints;
}

final class ExamReviewPublication {
  ExamReviewPublication({
    required this.accountBinding,
    required this.sessionId,
    required this.paperVersion,
    required this.generation,
    required this.runId,
    required List<ExamReviewQuestion> questions,
  }) : questions = List.unmodifiable(questions);

  final String accountBinding;
  final String sessionId;
  final String paperVersion;
  final int generation;
  final String runId;
  final List<ExamReviewQuestion> questions;
}

/// Exam session and grade state stays in memory; this class has no Drift or
/// generic cache adapter. Account changes invalidate every visible projection.
final class ExamProjectionState {
  String? _accountBinding;
  String? _sessionId;
  String? _paperVersion;
  bool _submitted = false;
  List<ExamPaperQuestion> _paper = const [];
  List<ExamReviewQuestion> _review = const [];
  int _reviewGeneration = -1;
  String? _reviewRunId;
  ExamGradePublication? _effectiveGrade;

  String? get accountBinding => _accountBinding;
  String? get sessionId => _sessionId;
  String? get paperVersion => _paperVersion;
  bool get submitted => _submitted;
  List<ExamPaperQuestion> get paper => UnmodifiableListView(_paper);
  List<ExamReviewQuestion> get review => UnmodifiableListView(_review);
  ExamGradePublication? get effectiveGrade => _effectiveGrade;

  void bindAccount(String accountBinding) {
    if (accountBinding.isEmpty) throw ArgumentError.value(accountBinding, 'accountBinding');
    if (_accountBinding == accountBinding) return;
    clear();
    _accountBinding = accountBinding;
  }

  void openSession({
    required String accountBinding,
    required String sessionId,
    required String paperVersion,
    required List<ExamPaperQuestion> paper,
  }) {
    if (_accountBinding == null || _accountBinding != accountBinding) {
      throw StateError('Account is not confirmed for this session');
    }
    if (sessionId.isEmpty || paperVersion.isEmpty || paper.isEmpty) {
      throw ArgumentError('A session needs an ID, version, and visible questions');
    }
    _sessionId = sessionId;
    _paperVersion = paperVersion;
    _paper = List.unmodifiable(paper);
    _review = const [];
    _reviewGeneration = -1;
    _reviewRunId = null;
    _submitted = false;
    _effectiveGrade = null;
  }

  /// Updates only localized display text for the same frozen paper. Grade and
  /// review publication identities remain unchanged across locale switches.
  bool replaceLocalizedPaper({
    required String accountBinding,
    required String sessionId,
    required String paperVersion,
    required List<ExamPaperQuestion> paper,
  }) {
    if (_accountBinding != accountBinding ||
        _sessionId != sessionId ||
        _paperVersion != paperVersion ||
        paper.length != _paper.length) {
      return false;
    }
    for (var index = 0; index < paper.length; index++) {
      if (paper[index].id != _paper[index].id ||
          paper[index].options.length != _paper[index].options.length) {
        return false;
      }
    }
    _paper = List.unmodifiable(paper);
    if (_review.isNotEmpty) {
      _review = List.unmodifiable([
        for (var index = 0; index < _review.length; index++)
          ExamReviewQuestion(paper: _paper[index], correctOption: _review[index].correctOption),
      ]);
    }
    return true;
  }

  bool confirmSubmission({
    required String accountBinding,
    required String sessionId,
    required String paperVersion,
  }) {
    if (_accountBinding != accountBinding ||
        _sessionId != sessionId ||
        _paperVersion != paperVersion) {
      return false;
    }
    _submitted = true;
    return true;
  }

  bool publishReview(ExamReviewPublication incoming) {
    if (!_submitted ||
        _accountBinding != incoming.accountBinding ||
        _sessionId != incoming.sessionId ||
        _paperVersion != incoming.paperVersion ||
        incoming.generation < 0 ||
        incoming.generation <= _reviewGeneration ||
        (_effectiveGrade != null &&
            (incoming.generation != _effectiveGrade!.generation ||
                incoming.runId != _effectiveGrade!.runId)) ||
        incoming.questions.length != _paper.length) {
      return false;
    }
    for (var index = 0; index < incoming.questions.length; index++) {
      if (incoming.questions[index].id != _paper[index].id) return false;
    }
    _review = incoming.questions;
    _reviewGeneration = incoming.generation;
    _reviewRunId = incoming.runId;
    return true;
  }

  bool publishEffectiveGrade(ExamGradePublication incoming) {
    if (_accountBinding != incoming.accountBinding ||
        !_submitted ||
        _sessionId != incoming.sessionId ||
        _paperVersion != incoming.paperVersion ||
        incoming.generation < 0) {
      return false;
    }
    final current = _effectiveGrade;
    if (current != null && incoming.generation <= current.generation) return false;
    _effectiveGrade = incoming;
    if (_reviewGeneration != incoming.generation || _reviewRunId != incoming.runId) {
      _review = const [];
      _reviewGeneration = -1;
      _reviewRunId = null;
    }
    return true;
  }

  void clear() {
    _accountBinding = null;
    _sessionId = null;
    _paperVersion = null;
    _submitted = false;
    _paper = const [];
    _review = const [];
    _reviewGeneration = -1;
    _reviewRunId = null;
    _effectiveGrade = null;
  }
}

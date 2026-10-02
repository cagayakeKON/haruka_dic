import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/query_prefill.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/collections/presentation/bookmark_question.dart';
import 'package:haruka/features/exams/data/exam_projections.dart';
import 'package:haruka/dev/preview/exam_fixture.dart';

/// The result consumes the submitted attempt projection. The session owns the
/// answer transaction and only navigates here after its confirmation succeeds.
class ExamResultPage extends StatelessWidget {
  const ExamResultPage({this.answers, super.key});
  final Map<int, int>? answers;

  @override
  Widget build(BuildContext context) {
    final store = PreviewStoreScope.of(context);
    final l10n = AppLocalizations.of(context);
    final projection = previewExamProjection(store, l10n);
    if (!projection.submitted || projection.review.isEmpty || projection.effectiveGrade == null) {
      final unavailable = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: HarukaSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.mockSupportExamSubmitConfirmBody),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.mockExamSession),
                  child: Text(l10n.mockSupportExamSessionTitle),
                ),
              ],
            ),
          ),
        ),
      );
      return PreviewPageFrame(
        location: AppRoutes.mockLibrary,
        title: l10n.mockLearningResultTitle,
        detail: true,
        detailNotifications: false,
        desktopBackLabel: l10n.mockLearningResultBackToPrep,
        onBack: () => _backToExamPrep(context),
        mobile: unavailable,
        desktop: unavailable,
      );
    }
    final questions = projection.review;
    final submittedAnswers = answers ?? store.examAnswers;
    final correct = List.generate(
      questions.length,
      (index) => submittedAnswers[index] == questions[index].correctOption,
    ).where((value) => value).length;
    return PreviewPageFrame(
      location: AppRoutes.mockLibrary,
      title: l10n.mockLearningResultTitle,
      detail: true,
      detailNotifications: false,
      desktopBackLabel: l10n.mockLearningResultBackToPrep,
      onBack: () => _backToExamPrep(context),
      mobile: MobileExamResultView(
        questions: questions,
        answers: submittedAnswers,
        correctCount: correct,
        onBookmark: (index) =>
            _bookmarkResultQuestion(context, questions[index], submittedAnswers[index]),
        onStudyText: (index, text, anchor) => _openExamTextSelection(context, text, anchor),
      ),
      desktop: DesktopExamResultView(
        questions: questions,
        answers: submittedAnswers,
        correctCount: correct,
        onBookmark: (index) =>
            _bookmarkResultQuestion(context, questions[index], submittedAnswers[index]),
        onStudyText: (index, text, anchor) => _openExamTextSelection(context, text, anchor),
      ),
    );
  }

  void _backToExamPrep(BuildContext context) {
    for (final item in PreviewStoreScope.of(context).materials) {
      if (item.type == LearningMaterialType.exam) {
        context.go(AppRoutes.mockMaterialPath(item.id));
        return;
      }
    }
    context.go(AppRoutes.mockLibrary);
  }

  Future<void> _bookmarkResultQuestion(
    BuildContext context,
    ExamReviewQuestion question,
    int? answer,
  ) {
    final l10n = AppLocalizations.of(context);
    return bookmarkQuestion(
      context,
      id: question.id,
      question: question.prompt,
      meaning: l10n.mockLearningResultReference(question.options[question.correctOption]),
      source: l10n.mockSupportExamPaperTitle,
      contextText: [
        for (var option = 0; option < question.options.length; option++)
          '${String.fromCharCode(65 + option)}. ${question.options[option]}',
      ].join('\n'),
      notes: [
        question.category,
        l10n.mockLearningResultYourChoice(
          answer == null ? l10n.mockLearningResultUnanswered : question.options[answer],
        ),
        l10n.mockLearningResultReference(question.options[question.correctOption]),
      ].join('\n'),
    );
  }
}

typedef ExamStudyTextAction = void Function(int questionIndex, String text, Rect anchor);
typedef _ExamTextAction = void Function(String text, Rect anchor);

class MobileExamResultView extends StatelessWidget {
  const MobileExamResultView({
    required this.questions,
    required this.answers,
    required this.correctCount,
    required this.onBookmark,
    required this.onStudyText,
    super.key,
  });
  final List<ExamReviewQuestion> questions;
  final Map<int, int> answers;
  final int correctCount;
  final ValueChanged<int> onBookmark;
  final ExamStudyTextAction onStudyText;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 36),
    children: [
      Text(
        AppLocalizations.of(context).mockLearningResultHeadline,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      Text(
        AppLocalizations.of(context).mockLearningResultSummary,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 22),
      _MobileScoreCard(correctCount: correctCount, total: questions.length),
      const SizedBox(height: 29),
      Text(
        AppLocalizations.of(context).mockLearningResultReview,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      for (var index = 0; index < questions.length; index++) ...[
        _ExamReviewCard(
          question: questions[index],
          index: index,
          answer: answers[index],
          onBookmark: () => onBookmark(index),
          onStudyText: (text, anchor) => onStudyText(index, text, anchor),
        ),
        const SizedBox(height: 13),
      ],
      OutlinedButton(
        onPressed: () => context.go(AppRoutes.mockMistakes),
        child: Text(AppLocalizations.of(context).mockLearningResultViewMistakes),
      ),
      const SizedBox(height: 9),
      TextButton(
        onPressed: () => context.go(AppRoutes.mockLibrary),
        child: Text(AppLocalizations.of(context).mockLearningResultReturnLibrary),
      ),
    ],
  );
}

class DesktopExamResultView extends StatelessWidget {
  const DesktopExamResultView({
    required this.questions,
    required this.answers,
    required this.correctCount,
    required this.onBookmark,
    required this.onStudyText,
    super.key,
  });
  final List<ExamReviewQuestion> questions;
  final Map<int, int> answers;
  final int correctCount;
  final ValueChanged<int> onBookmark;
  final ExamStudyTextAction onStudyText;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 44),
        children: [
          Text(
            AppLocalizations.of(context).mockLearningResultTitle,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _DesktopScoreTile(
                  value: '$correctCount / ${questions.length}',
                  label: AppLocalizations.of(context).mockLearningResultObjective,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DesktopScoreTile(
                  value: '${questions.length - correctCount}',
                  label: AppLocalizations.of(context).mockLearningResultNeedsReview,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DesktopScoreTile(
                  value: AppLocalizations.of(context).mockLearningResultSubmitted,
                  label: AppLocalizations.of(context).mockLearningResultAnswerStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).mockLearningResultReview,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.mockMistakes),
                child: Text(AppLocalizations.of(context).mockLearningResultViewMistakes),
              ),
            ],
          ),
          const SizedBox(height: 17),
          for (var index = 0; index < questions.length; index++) ...[
            _ExamReviewCard(
              question: questions[index],
              index: index,
              answer: answers[index],
              onBookmark: () => onBookmark(index),
              onStudyText: (text, anchor) => onStudyText(index, text, anchor),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
  );
}

class _MobileScoreCard extends StatelessWidget {
  const _MobileScoreCard({required this.correctCount, required this.total});
  final int correctCount;
  final int total;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(17)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).mockLearningResultObjective,
                  style: TextStyle(color: scheme.onPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).mockLearningResultCorrectCount,
                  style: TextStyle(color: scheme.onPrimary.withValues(alpha: .85), fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '$correctCount / $total',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DesktopScoreTile extends StatelessWidget {
  const _DesktopScoreTile({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => HarukaSurface(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

class _ExamReviewCard extends StatelessWidget {
  const _ExamReviewCard({
    required this.question,
    required this.index,
    required this.answer,
    required this.onBookmark,
    required this.onStudyText,
  });
  final ExamReviewQuestion question;
  final int index;
  final int? answer;
  final VoidCallback onBookmark;
  final _ExamTextAction onStudyText;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HarukaSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mockLearningResultQuestionLabel(index + 1, question.category),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onBookmark,
                icon: const Icon(Icons.bookmark_border),
                label: Text(l10n.mockLearningPracticeBookmark),
              ),
            ],
          ),
          const SizedBox(height: 23),
          _ExamStudyText(
            text: question.prompt,
            style: Theme.of(context).textTheme.titleMedium,
            onStudyText: onStudyText,
          ),
          const SizedBox(height: 18),
          for (var option = 0; option < question.options.length; option++) ...[
            _ExamStudyText(
              text: '${String.fromCharCode(65 + option)}. ${question.options[option]}',
              onStudyText: onStudyText,
            ),
            const SizedBox(height: 5),
          ],
          const SizedBox(height: 15),
          _ExamStudyText(
            text: l10n.mockLearningResultYourChoice(
              answer == null ? l10n.mockLearningResultUnanswered : question.options[answer!],
            ),
            onStudyText: onStudyText,
          ),
          const SizedBox(height: 8),
          _ExamStudyText(
            text: l10n.mockLearningResultReference(question.options[question.correctOption]),
            onStudyText: onStudyText,
          ),
        ],
      ),
    );
  }
}

class _ExamStudyText extends StatelessWidget {
  const _ExamStudyText({required this.text, required this.onStudyText, this.style});
  final String text;
  final TextStyle? style;
  final _ExamTextAction onStudyText;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchorContext) => Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isAltPressed) {
          onStudyText(text, _anchorRect(anchorContext));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (focusContext) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => Focus.of(focusContext).requestFocus(),
          onLongPress: () => onStudyText(text, _anchorRect(anchorContext)),
          onSecondaryTap: () => onStudyText(text, _anchorRect(anchorContext)),
          child: Text(text, style: style),
        ),
      ),
    ),
  );
}

Rect _anchorRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _InstantExitExamSelectionRoute<T> extends RawDialogRoute<T> {
  _InstantExitExamSelectionRoute({
    required super.pageBuilder,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionDuration,
  }) : super(barrierDismissible: true);

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

Future<void> _openExamTextSelection(BuildContext context, String text, Rect anchor) async {
  final compact = MediaQuery.sizeOf(context).width < 760;
  final selectedText = await Navigator.of(context, rootNavigator: true).push<String>(
    _InstantExitExamSelectionRoute<String>(
      barrierLabel: AppLocalizations.of(context).mockLearningResultSelectionClose,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0),
      transitionDuration:
          HarukaMotion.reduced(context, reducedMotion: PreviewStoreScope.of(context).reducedMotion)
          ? Duration.zero
          : HarukaMotion.exit,
      pageBuilder: (overlayContext, animation, secondaryAnimation) {
        final viewport = MediaQuery.sizeOf(overlayContext);
        final panelWidth = compact
            ? (viewport.width - 32).clamp(0.0, 360.0)
            : (viewport.width - 32).clamp(0.0, 350.0);
        final left = anchor.left.clamp(
          16.0,
          (viewport.width - panelWidth - 16).clamp(16.0, double.infinity),
        );
        final top = compact
            ? (anchor.top - 20).clamp(16.0, viewport.height * .5)
            : (anchor.bottom + 8).clamp(16.0, (viewport.height - 316).clamp(16.0, double.infinity));
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: viewport.height - top - 16),
                child: compact
                    ? MobileExamSelectionPopover(text: text)
                    : DesktopExamSelectionPopover(text: text),
              ),
            ),
          ],
        );
      },
    ),
  );
  if (selectedText == null || !context.mounted) return;
  final adapter = context.dependOnInheritedWidgetOfExactType<PreviewSettingsCacheScope>()?.notifier;
  final prefill = adapter == null ? null : QueryPrefill.capture(adapter.coordinator, selectedText);
  if (prefill == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
    return;
  }
  await context.push(AppRoutes.mockQuery, extra: prefill);
}

class MobileExamSelectionPopover extends StatelessWidget {
  const MobileExamSelectionPopover({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('exam-selection-popover'),
    color: Theme.of(context).colorScheme.surface,
    elevation: 12,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: _ExamSelectionBody(text: text),
      ),
    ),
  );
}

class DesktopExamSelectionPopover extends StatelessWidget {
  const DesktopExamSelectionPopover({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('exam-selection-popover'),
    color: Theme.of(context).colorScheme.surface,
    elevation: 12,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: _ExamSelectionBody(text: text),
      ),
    ),
  );
}

class _ExamSelectionBody extends StatefulWidget {
  const _ExamSelectionBody({required this.text});
  final String text;

  @override
  State<_ExamSelectionBody> createState() => _ExamSelectionBodyState();
}

class _ExamSelectionBodyState extends State<_ExamSelectionBody> {
  late final tokens = previewExamTextTokens(widget.text);
  late final graphemes = widget.text.runes.map(String.fromCharCode).toList();
  final selected = <int>{};
  int? rangeStart;
  int? rangeEnd;
  bool audioUnavailable = false;

  bool get invalidRange => rangeStart != null && rangeEnd != null && rangeEnd! <= rangeStart!;

  int get selectedGroups {
    var groups = 0;
    var previous = -2;
    for (final index in selected.toList()..sort()) {
      if (index > previous + 1) groups++;
      previous = index;
    }
    return groups;
  }

  String get selectedText {
    if (rangeStart != null && rangeEnd != null && !invalidRange) {
      return graphemes.sublist(rangeStart!, rangeEnd!).join().trim();
    }
    if (selected.isEmpty) return widget.text.trim();
    final ordered = selected.toList()..sort();
    final ranges = <String>[];
    var groupStart = ordered.first;
    var groupEnd = groupStart;
    for (final index in ordered.skip(1)) {
      if (index == groupEnd + 1) {
        groupEnd = index;
      } else {
        ranges.add(widget.text.substring(tokens[groupStart].start, tokens[groupEnd].end));
        groupStart = groupEnd = index;
      }
    }
    ranges.add(widget.text.substring(tokens[groupStart].start, tokens[groupEnd].end));
    return ranges.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tooMany = selectedGroups > 3;
    final canSubmit = !invalidRange && !tooMany && selectedText.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.mockLearningResultSelectionTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.mockLearningResultSelectionRead,
              onPressed: () => setState(() => audioUnavailable = true),
              icon: const Icon(Icons.volume_up_outlined),
            ),
            IconButton(
              tooltip: l10n.mockLearningResultSelectionClose,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (audioUnavailable) ...[
          const SizedBox(height: 5),
          Text(
            l10n.mockLearningResultSelectionAudioUnavailable,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: [
            for (var index = 0; index < tokens.length; index++)
              FilterChip(
                key: ValueKey('exam-selection-token-$index'),
                label: Text(tokens[index].text),
                selected: selected.contains(index),
                onSelected: (value) => setState(() {
                  rangeStart = null;
                  rangeEnd = null;
                  if (value) {
                    selected.add(index);
                  } else {
                    selected.remove(index);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          invalidRange
              ? l10n.mockLearningResultSelectionInvalidRange
              : tooMany
              ? l10n.mockLearningResultSelectionTooMany
              : selected.isEmpty && rangeStart == null
              ? l10n.mockLearningResultSelectionWhole
              : selectedText,
          style: TextStyle(color: invalidRange || tooMany ? scheme.error : scheme.onSurfaceVariant),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: Text(l10n.mockLearningResultSelectionAdjust),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.mockLearningResultSelectionAdjustHelp,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: l10n.mockLearningResultSelectionStart),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const ValueKey('exam-selection-start'),
                        value: rangeStart ?? 0,
                        isExpanded: true,
                        items: [
                          for (var index = 0; index < graphemes.length; index++)
                            DropdownMenuItem(
                              value: index,
                              child: Text(
                                '${index + 1} · ${graphemes.skip(index).take(10).join()}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          selected.clear();
                          rangeStart = value;
                          rangeEnd ??= graphemes.length;
                        }),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: l10n.mockLearningResultSelectionEnd),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const ValueKey('exam-selection-end'),
                        value: rangeEnd ?? graphemes.length,
                        isExpanded: true,
                        items: [
                          for (var index = 1; index <= graphemes.length; index++)
                            DropdownMenuItem(
                              value: index,
                              child: Text('$index · ${graphemes[index - 1]}'),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          selected.clear();
                          rangeStart ??= 0;
                          rangeEnd = value;
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 13),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canSubmit ? () => Navigator.pop(context, selectedText) : null,
            icon: const Icon(Icons.search),
            label: Text(l10n.mockLearningResultSelectionQuery),
          ),
        ),
      ],
    );
  }
}

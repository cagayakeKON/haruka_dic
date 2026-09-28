import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/exam_fixture.dart';
import 'package:haruka/features/exams/data/exam_projections.dart';

const _examQuestionCount = 3;

class ExamSessionPage extends StatefulWidget {
  const ExamSessionPage({super.key});

  @override
  State<ExamSessionPage> createState() => _ExamSessionPageState();
}

class _ExamSessionPageState extends State<ExamSessionPage> {
  bool _dialogOpen = false;

  Future<bool?> _confirmAction({
    required String title,
    required String body,
    required String confirmLabel,
    bool submit = false,
  }) {
    final l10n = AppLocalizations.of(context);
    if (MediaQuery.sizeOf(context).width >= 760) {
      return showHarukaDialog<bool>(
        context: context,
        animationStyle: HarukaMotion.dialogStyle(
          context,
          reducedMotion: PreviewStoreScope.of(context).reducedMotion,
        ),
        builder: (dialogContext) => AlertDialog(
          constraints: const BoxConstraints(minWidth: 560, maxWidth: 560, minHeight: 208),
          titlePadding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
          contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
          actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          actionsAlignment: MainAxisAlignment.start,
          title: Text(title),
          content: Text(body),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.mockSupportExamContinueAnswering),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    }
    final roles = HarukaColors.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: 235,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.pop(sheetContext, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(body),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: Text(l10n.mockSupportExamContinueAnswering),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: submit
                            ? FilledButton.styleFrom(
                                backgroundColor: roles.bookPeach,
                                foregroundColor: roles.danger,
                              )
                            : null,
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leave([String? destination]) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final l10n = AppLocalizations.of(context);
    final leave = await _confirmAction(
      title: l10n.mockSupportExamLeaveTitle,
      body: l10n.mockSupportExamLeaveBody,
      confirmLabel: MediaQuery.sizeOf(context).width < 760
          ? l10n.mockSupportExamSaveAndLeave
          : l10n.mockSupportExamLeave,
    );
    _dialogOpen = false;
    if (!mounted || leave != true) return;
    final store = PreviewStoreScope.of(context);
    store.saveExamDraft();
    final exam = store.materials.firstWhere((item) => item.type == LearningMaterialType.exam);
    context.go(destination ?? AppRoutes.mockMaterialPath(exam.id));
  }

  Future<void> _submit() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirmAction(
      title: l10n.mockSupportExamSubmitConfirmTitle,
      body: l10n.mockSupportExamSubmitAnsweredBody(
        PreviewStoreScope.of(context).examDraftAnswers.length,
        _examQuestionCount,
      ),
      confirmLabel: l10n.mockSupportExamConfirmSubmit,
      submit: true,
    );
    _dialogOpen = false;
    if (!mounted || confirmed != true) return;
    final store = PreviewStoreScope.of(context);
    store.submitExam(store.examDraftAnswers);
    context.go(AppRoutes.mockExamResult);
  }

  Future<void> _showAnswerCard() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: 300,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l10n.mockSupportExamAnswerCard,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.mockSupportExamAnsweredCount(
                    PreviewStoreScope.of(context).examDraftAnswers.length,
                    _examQuestionCount,
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 26),
                _ExamQuestionGrid(
                  store: PreviewStoreScope.of(context),
                  mobile: true,
                  onSelect: (index) {
                    PreviewStoreScope.of(context).selectExamQuestion(index);
                    Navigator.pop(sheetContext);
                  },
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(l10n.mockSupportExamContinueAnswering),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = PreviewStoreScope.of(context);
    final l10n = AppLocalizations.of(context);
    final paper = previewExamProjection(store, l10n).paper;
    if (paper.isEmpty) {
      final unavailable = Center(child: Text(l10n.mockMaterialUnavailableMessage));
      return PreviewPageFrame(
        location: AppRoutes.mockExamSession,
        title: l10n.mockSupportExamMobileTitle,
        detail: true,
        detailNotifications: false,
        desktopBackLabel: l10n.mockSupportExamBackToPreparation,
        onBack: () => context.go(AppRoutes.mockLibrary),
        mobile: unavailable,
        desktop: unavailable,
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _leave();
      },
      child: PreviewPageFrame(
        location: AppRoutes.mockExamSession,
        title: l10n.mockSupportExamMobileTitle,
        detail: true,
        detailNotifications: false,
        desktopBackLabel: l10n.mockSupportExamBackToPreparation,
        onBack: _leave,
        onNavigate: (path) async {
          await _leave(path);
        },
        mobile: MobileExamSessionView(
          store: store,
          paper: paper,
          onAnswerCard: _showAnswerCard,
          onSubmit: _submit,
        ),
        desktop: DesktopExamSessionView(store: store, paper: paper, onSubmit: _submit),
      ),
    );
  }
}

class MobileExamSessionView extends StatelessWidget {
  const MobileExamSessionView({
    required this.store,
    required this.paper,
    required this.onAnswerCard,
    required this.onSubmit,
    super.key,
  });

  final PreviewFixtureStore store;
  final List<ExamPaperQuestion> paper;
  final VoidCallback onAnswerCard;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final question = store.examCurrentQuestion;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            children: [
              Row(
                children: [
                  Text(
                    l10n.mockSupportExamDuration,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    l10n.mockSupportExamAnsweredCount(
                      store.examDraftAnswers.length,
                      _examQuestionCount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: onAnswerCard,
                    icon: const Icon(Icons.grid_view_outlined),
                    label: Text(l10n.mockSupportExamAnswerCard),
                  ),
                  TextButton.icon(
                    onPressed: store.examSubmitted ? null : store.saveExamDraft,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.mockSupportExamSave),
                  ),
                  TextButton(
                    onPressed: store.examSubmitted ? null : onSubmit,
                    child: Text(l10n.mockSupportExamSubmit),
                  ),
                ],
              ),
              const Divider(height: 18),
              const SizedBox(height: 30),
              Text(
                l10n.mockSupportExamQuestionNumber(question + 1),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${paper[question].sessionGroup} · ${store.examDraftSaved ? l10n.mockSupportExamSaved : l10n.mockSupportExamUnsaved}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paper[question].prompt, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),
                    for (var index = 0; index < 4; index++) ...[
                      _ExamChoiceTile(
                        label: paper[question].options[index],
                        index: index,
                        selected: store.examDraftAnswers[question] == index,
                        onTap: store.examSubmitted
                            ? null
                            : () => store.chooseExamAnswer(question, index),
                      ),
                      if (index < 3) const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: store.examSubmitted ? null : () => store.toggleExamMark(question),
                icon: Icon(
                  store.examMarkedQuestions.contains(question)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
                label: Text(
                  store.examMarkedQuestions.contains(question)
                      ? l10n.mockSupportExamUnmarkQuestion
                      : l10n.mockSupportExamMarkForLater,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: question > 0 ? () => store.selectExamQuestion(question - 1) : null,
                  child: Text(l10n.mockSupportExamPreviousQuestion),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: question < _examQuestionCount - 1
                      ? () => store.selectExamQuestion(question + 1)
                      : null,
                  child: Text(l10n.mockSupportExamNextQuestion),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DesktopExamSessionView extends StatelessWidget {
  const DesktopExamSessionView({
    required this.store,
    required this.paper,
    required this.onSubmit,
    super.key,
  });

  final PreviewFixtureStore store;
  final List<ExamPaperQuestion> paper;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final question = store.examCurrentQuestion;
    return ListView(
      children: [
        Row(
          children: [
            Text(
              l10n.mockSupportExamSessionTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Spacer(),
            Text(l10n.mockSupportExamDuration),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: HarukaSurface(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${paper[question].sessionGroup} · ${l10n.mockSupportExamQuestionNumber(question + 1)}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 24),
                    Text(paper[question].prompt, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 24),
                    for (var row = 0; row < 2; row++) ...[
                      Row(
                        children: [
                          for (var column = 0; column < 2; column++) ...[
                            Expanded(
                              child: _ExamChoiceTile(
                                label: paper[question].options[row * 2 + column],
                                index: row * 2 + column,
                                selected: store.examDraftAnswers[question] == row * 2 + column,
                                onTap: store.examSubmitted
                                    ? null
                                    : () => store.chooseExamAnswer(question, row * 2 + column),
                              ),
                            ),
                            if (column == 0) const SizedBox(width: 12),
                          ],
                        ],
                      ),
                      if (row == 0) const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: store.examSubmitted
                              ? null
                              : () => store.toggleExamMark(question),
                          icon: Icon(
                            store.examMarkedQuestions.contains(question)
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                          label: Text(
                            store.examMarkedQuestions.contains(question)
                                ? l10n.mockSupportExamUnmarkQuestion
                                : l10n.mockSupportExamMarkForLater,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: store.examSubmitted ? null : store.saveExamDraft,
                          child: Text(l10n.mockSupportExamSaveDraft),
                        ),
                        OutlinedButton(
                          onPressed: question > 0
                              ? () => store.selectExamQuestion(question - 1)
                              : null,
                          child: Text(l10n.mockSupportExamPreviousQuestion),
                        ),
                        OutlinedButton(
                          onPressed: question < _examQuestionCount - 1
                              ? () => store.selectExamQuestion(question + 1)
                              : null,
                          child: Text(l10n.mockSupportExamNextQuestion),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HarukaSurface(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mockSupportExamAnswerCard,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.mockSupportExamAnsweredCount(store.examDraftAnswers.length, _examQuestionCount)} · ${store.examDraftSaved ? l10n.mockSupportExamSaved : l10n.mockSupportExamUnsaved}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 28),
                        _ExamQuestionGrid(
                          store: store,
                          mobile: false,
                          onSelect: store.selectExamQuestion,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: store.examSubmitted ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: HarukaColors.of(context).bookPeach,
                      foregroundColor: HarukaColors.of(context).danger,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l10n.mockSupportExamSubmit),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExamChoiceTile extends StatelessWidget {
  const _ExamChoiceTile({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int index;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Material(
      color: selected ? roles.selected : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? scheme.primary : scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 19),
          child: Row(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamQuestionGrid extends StatelessWidget {
  const _ExamQuestionGrid({required this.store, required this.mobile, required this.onSelect});

  final PreviewFixtureStore store;
  final bool mobile;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final l10n = AppLocalizations.of(context);
    Widget tile(int index) {
      final selected = store.examCurrentQuestion == index;
      final foreground = !mobile && selected ? scheme.onPrimary : scheme.onSurface;
      return Material(
        color: selected ? (mobile ? roles.selected : scheme.primary) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline),
        ),
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: mobile ? 15 : 12, horizontal: 4),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (store.examMarkedQuestions.contains(index))
                      Icon(Icons.star, size: 12, color: foreground),
                    Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: foreground),
                    ),
                    if (store.examDraftAnswers.containsKey(index))
                      Icon(Icons.circle, size: 7, color: foreground),
                  ],
                ),
                if (mobile) ...[
                  const SizedBox(height: 5),
                  Text(
                    store.examMarkedQuestions.contains(index)
                        ? l10n.mockSupportExamMarked
                        : store.examDraftAnswers.containsKey(index)
                        ? l10n.mockSupportExamAnswered
                        : l10n.mockSupportExamUnanswered,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (!mobile) {
      return Wrap(
        spacing: 8,
        children: [
          for (var index = 0; index < _examQuestionCount; index++)
            SizedBox(width: 46, height: 48, child: tile(index)),
        ],
      );
    }
    return Row(
      children: [
        for (var index = 0; index < _examQuestionCount; index++) ...[
          Expanded(child: tile(index)),
          if (index < _examQuestionCount - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

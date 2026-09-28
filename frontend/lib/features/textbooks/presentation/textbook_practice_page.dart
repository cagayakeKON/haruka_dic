import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/features/collections/presentation/bookmark_question.dart';
import 'package:haruka/app/preview_shell.dart';

typedef TextbookPracticeContent = ({
  String subtitle,
  String question,
  List<String> options,
  String explanation,
  String collectionId,
  bool splitDesktopOptions,
});

TextbookPracticeContent _practiceContent(AppLocalizations l10n, int unit) => switch (unit) {
  2 => (
    subtitle: l10n.mockLearningPracticeUnit2Subtitle,
    question: l10n.mockLearningPracticeUnit2Question,
    options: [
      l10n.mockLearningPracticeUnit2OptionDirection,
      l10n.mockLearningPracticeUnit2OptionObject,
      l10n.mockLearningPracticeUnit2OptionReason,
      l10n.mockLearningPracticeUnit2OptionRelation,
    ],
    explanation: l10n.mockLearningPracticeUnit2Explanation,
    collectionId: 'd7777777-7777-4777-8777-777777777772',
    splitDesktopOptions: true,
  ),
  3 => (
    subtitle: l10n.mockLearningPracticeUnit3Subtitle,
    question: l10n.mockLearningPracticeUnit3Question,
    options: [
      l10n.mockLearningPracticeUnit3OptionRequest,
      l10n.mockLearningPracticeUnit3OptionWelcome,
      l10n.mockLearningPracticeUnit3OptionFinished,
      l10n.mockLearningPracticeUnit3OptionWait,
    ],
    explanation: l10n.mockLearningPracticeUnit3Explanation,
    collectionId: 'd7777777-7777-4777-8777-777777777773',
    splitDesktopOptions: false,
  ),
  _ => (
    subtitle: l10n.mockLearningPracticeSubtitle,
    question: l10n.mockLearningPracticeQuestion,
    options: [
      l10n.mockLearningPracticeOptionTopic,
      l10n.mockLearningPracticeOptionDirection,
      l10n.mockLearningPracticeOptionPast,
      l10n.mockLearningPracticeOptionJoin,
    ],
    explanation: l10n.mockLearningPracticeExplanation,
    collectionId: 'd7777777-7777-4777-8777-777777777777',
    splitDesktopOptions: false,
  ),
};

/// A textbook exercise keeps an attempt for the selected unit.
class TextbookPracticePage extends StatefulWidget {
  const TextbookPracticePage({super.key});
  @override
  State<TextbookPracticePage> createState() => _TextbookPracticePageState();
}

class _TextbookPracticePageState extends State<TextbookPracticePage> {
  int? selected;
  bool submitted = false;
  int unit = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requested = int.tryParse(GoRouterState.of(context).uri.queryParameters['unit'] ?? '1');
    final next = requested == 2 || requested == 3 ? requested! : 1;
    if (unit == next) return;
    unit = next;
    selected = null;
    submitted = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = _practiceContent(l10n, unit);
    return PreviewPageFrame(
      location: AppRoutes.mockLibrary,
      title: l10n.mockLearningPracticeTitle,
      detail: true,
      detailNotifications: false,
      desktopBackLabel: l10n.mockLearningPracticeBackToTextbook,
      onBack: () => _backToTextbook(context),
      mobile: MobileTextbookPracticeView(
        content: content,
        selected: selected,
        submitted: submitted,
        onChoose: _choose,
        onSubmit: _submit,
        onRetry: _retry,
        onBookmark: () => _bookmark(context),
      ),
      desktop: DesktopTextbookPracticeView(
        content: content,
        selected: selected,
        submitted: submitted,
        onChoose: _choose,
        onSubmit: _submit,
        onRetry: _retry,
        onBookmark: () => _bookmark(context),
      ),
    );
  }

  void _choose(int value) => setState(() => selected = value);
  void _submit() {
    if (selected != null) setState(() => submitted = true);
  }

  void _retry() => setState(() {
    selected = null;
    submitted = false;
  });

  void _backToTextbook(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final store = PreviewStoreScope.of(context);
    for (final item in store.materials) {
      if (item.type == LearningMaterialType.textbook) {
        context.go('${AppRoutes.mockMaterialPath(item.id)}?unit=$unit');
        return;
      }
    }
    context.go(AppRoutes.mockLibrary);
  }

  Future<void> _bookmark(BuildContext context) async {
    final content = _practiceContent(AppLocalizations.of(context), unit);
    await bookmarkQuestion(
      context,
      id: content.collectionId,
      question: content.question,
      meaning: submitted ? content.explanation : '',
      source: content.subtitle,
    );
  }
}

class MobileTextbookPracticeView extends StatelessWidget {
  const MobileTextbookPracticeView({
    required this.content,
    required this.selected,
    required this.submitted,
    required this.onChoose,
    required this.onSubmit,
    required this.onRetry,
    required this.onBookmark,
    super.key,
  });
  final TextbookPracticeContent content;
  final int? selected;
  final bool submitted;
  final ValueChanged<int> onChoose;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
    children: [
      Text(content.subtitle, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 19),
      Text(
        AppLocalizations.of(context).mockLearningPracticeTitle,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 21),
      HarukaSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content.question, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onBookmark,
                icon: const Icon(Icons.bookmark_border),
                label: Text(AppLocalizations.of(context).mockLearningPracticeBookmark),
              ),
            ),
            const SizedBox(height: 24),
            _PracticeOptions(
              options: content.options,
              selected: selected,
              submitted: submitted,
              onChoose: onChoose,
            ),
            const SizedBox(height: 20),
            if (submitted) ...[
              _PracticeFeedback(
                correct: selected == 0,
                explanation: content.explanation,
                compact: true,
              ),
              const SizedBox(height: 15),
            ],
            SizedBox(
              width: double.infinity,
              child: submitted
                  ? OutlinedButton(
                      onPressed: onRetry,
                      child: Text(AppLocalizations.of(context).mockLearningPracticeRetry),
                    )
                  : FilledButton(
                      onPressed: selected == null ? null : onSubmit,
                      child: Text(AppLocalizations.of(context).mockLearningPracticeConfirm),
                    ),
            ),
          ],
        ),
      ),
    ],
  );
}

class DesktopTextbookPracticeView extends StatelessWidget {
  const DesktopTextbookPracticeView({
    required this.content,
    required this.selected,
    required this.submitted,
    required this.onChoose,
    required this.onSubmit,
    required this.onRetry,
    required this.onBookmark,
    super.key,
  });
  final TextbookPracticeContent content;
  final int? selected;
  final bool submitted;
  final ValueChanged<int> onChoose;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).mockLearningPracticeTitle,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 27),
              Text(
                content.subtitle,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 17),
              HarukaSurface(
                padding: const EdgeInsets.all(36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content.question, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 52),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 180,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: onBookmark,
                          icon: const Icon(Icons.bookmark_border),
                          label: Text(AppLocalizations.of(context).mockLearningPracticeBookmark),
                        ),
                      ),
                    ),
                    const SizedBox(height: 39),
                    _PracticeOptions(
                      options: content.options,
                      selected: selected,
                      submitted: submitted,
                      onChoose: onChoose,
                      columns: 2,
                      splitLabels: content.splitDesktopOptions,
                    ),
                    if (submitted) ...[
                      const SizedBox(height: 21),
                      _PracticeFeedback(correct: selected == 0, explanation: content.explanation),
                    ],
                    const SizedBox(height: 30),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 180,
                        height: 48,
                        child: submitted
                            ? OutlinedButton(
                                onPressed: onRetry,
                                child: Text(AppLocalizations.of(context).mockLearningPracticeRetry),
                              )
                            : FilledButton(
                                style: FilledButton.styleFrom(
                                  disabledBackgroundColor: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: .45),
                                  disabledForegroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                                onPressed: selected == null ? null : onSubmit,
                                child: Text(
                                  AppLocalizations.of(context).mockLearningPracticeConfirm,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PracticeOptions extends StatelessWidget {
  const _PracticeOptions({
    required this.options,
    required this.selected,
    required this.submitted,
    required this.onChoose,
    this.columns = 1,
    this.splitLabels = false,
  });
  final List<String> options;
  final int? selected;
  final bool submitted;
  final ValueChanged<int> onChoose;
  final int columns;
  final bool splitLabels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = columns == 1 ? constraints.maxWidth : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < options.length; i++)
              SizedBox(
                width: width,
                child: _PracticeOption(
                  letter: String.fromCharCode(65 + i),
                  label: options[i],
                  selected: selected == i,
                  correct: submitted && i == 0,
                  wrong: submitted && selected == i && i != 0,
                  onTap: submitted ? null : () => onChoose(i),
                  splitLabel: splitLabels,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PracticeOption extends StatelessWidget {
  const _PracticeOption({
    required this.letter,
    required this.label,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
    this.splitLabel = false,
  });
  final String letter;
  final String label;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;
  final bool splitLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final tint = correct
        ? roles.positive
        : wrong
        ? roles.danger
        : selected
        ? scheme.primary
        : scheme.outline;
    return Material(
      color: correct
          ? roles.positive.withValues(alpha: .09)
          : wrong
          ? roles.danger.withValues(alpha: .09)
          : selected
          ? roles.selected
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: tint),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: splitLabel ? 12 : 15),
          child: Row(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : roles.canvas,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  letter,
                  style: TextStyle(color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: splitLabel
                      ? SizedBox(
                          width: 32,
                          child: Text(label, style: const TextStyle(fontSize: 12, height: 1.1)),
                        )
                      : Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeFeedback extends StatelessWidget {
  const _PracticeFeedback({required this.correct, required this.explanation, this.compact = false});
  final bool correct;
  final String explanation;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final tint = correct
        ? roles.positive
        : compact
        ? roles.danger
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            correct ? l10n.mockLearningPracticeCorrect : l10n.mockLearningPracticeWrong,
            style: TextStyle(color: tint, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(explanation),
        ],
      ),
    );
  }
}

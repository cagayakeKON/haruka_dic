import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/app/preview_shell.dart';

class ExercisePage extends StatelessWidget {
  const ExercisePage({super.key});

  @override
  Widget build(BuildContext context) => PreviewPageFrame(
    location: AppRoutes.mockExercise,
    title: AppLocalizations.of(context).mockExerciseTitle,
    mobile: const MobileExerciseView(),
    desktop: const DesktopExerciseView(),
  );
}

class MobileExerciseView extends StatelessWidget {
  const MobileExerciseView({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
    children: [
      Text(
        AppLocalizations.of(context).mockShellJapanese,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Text(
        AppLocalizations.of(context).mockExerciseExisting,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      HarukaSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(AppLocalizations.of(context).mockExerciseSampleTitle),
          subtitle: Text(AppLocalizations.of(context).mockExerciseSampleSummary(1)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.mockPractice),
        ),
      ),
      const SizedBox(height: 16),
      _GenerateExerciseCard(
        compact: true,
        onTap: () => context.push(AppRoutes.mockExerciseBuilder),
      ),
      const SizedBox(height: 20),
      Text(
        AppLocalizations.of(context).mockExerciseHistory,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      HarukaSurface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(AppLocalizations.of(context).mockExerciseMistakes),
              subtitle: Text(AppLocalizations.of(context).mockExerciseMistakesCount(2)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.mockMistakes),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.grid_view_outlined),
              title: Text(AppLocalizations.of(context).mockExerciseDiagnosis),
              subtitle: Text(AppLocalizations.of(context).mockExerciseDiagnosisTopics),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.mockDiagnosis),
            ),
          ],
        ),
      ),
    ],
  );
}

class DesktopExerciseView extends StatelessWidget {
  const DesktopExerciseView({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        AppLocalizations.of(context).mockExerciseTitle,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      Text(
        AppLocalizations.of(context).mockExerciseExisting,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      HarukaSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(AppLocalizations.of(context).mockExerciseSampleTitle),
          subtitle: Text(AppLocalizations.of(context).mockExerciseSampleSummary(1)),
          trailing: const Icon(Icons.arrow_forward),
          onTap: () => context.push(AppRoutes.mockPractice),
        ),
      ),
      const SizedBox(height: 18),
      _GenerateExerciseCard(onTap: () => context.push(AppRoutes.mockExerciseBuilder)),
      const SizedBox(height: 24),
      Text(
        AppLocalizations.of(context).mockExerciseHistory,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 15),
      Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 100,
              child: HarukaSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(AppLocalizations.of(context).mockExerciseMistakes),
                  subtitle: Text(AppLocalizations.of(context).mockExerciseMistakesCount(2)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.mockMistakes),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 100,
              child: HarukaSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.grid_view_outlined),
                  title: Text(AppLocalizations.of(context).mockExerciseDiagnosis),
                  subtitle: Text(AppLocalizations.of(context).mockExerciseDiagnosisTopics),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.mockDiagnosis),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _GenerateExerciseCard extends StatelessWidget {
  const _GenerateExerciseCard({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    if (!compact) {
      return SizedBox(
        height: 104,
        child: Material(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: roles.signal.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.auto_awesome_outlined, color: scheme.onPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).mockExerciseGenerate,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: scheme.onPrimary, fontSize: 22),
                        ),
                        Text(
                          AppLocalizations.of(context).mockExerciseSourceDescription,
                          style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: .84),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context).mockExerciseSelectSource,
                    style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, color: scheme.onPrimary, size: 18),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 118,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 5,
                  decoration: BoxDecoration(
                    color: roles.signal,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                Text(
                  AppLocalizations.of(context).mockExerciseGenerate,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: scheme.onPrimary, fontSize: 22),
                ),
                if (compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).mockExerciseSourceDescription,
                    style: TextStyle(color: scheme.onPrimary, fontSize: 12),
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    Text(
                      AppLocalizations.of(context).mockExerciseSelectSource,
                      style: TextStyle(color: scheme.onPrimary),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward, color: scheme.onPrimary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PracticePage extends StatelessWidget {
  const PracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PreviewStoreScope.of(context);
    final strings = AppLocalizations.of(context);
    final options = [
      strings.mockExerciseOptionA,
      strings.mockExerciseOptionB,
      strings.mockExerciseOptionC,
      strings.mockExerciseOptionD,
    ];
    final submitted = store.exerciseSubmitted;
    final body = HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.mockExerciseSampleTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(strings.mockExerciseQuestionProgress(1, 1)),
          const SizedBox(height: 20),
          Text(strings.mockExerciseQuestionText, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 7),
          Text(strings.mockExerciseQuestionTranslation),
          const SizedBox(height: 18),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: store.selectedAnswer == i
                    ? HarukaColors.of(context).selected
                    : Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: submitted && i == 0
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: submitted ? null : () => store.chooseAnswer(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${String.fromCharCode(65 + i)}  ${options[i]}',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                        if (submitted && store.selectedAnswer == i)
                          Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        if (submitted && i == 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            strings.mockLearningResultReference(options[i]),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (submitted)
            HarukaSurface(
              child: Text(
                store.selectedAnswer == 0
                    ? strings.mockExerciseCorrectFeedback
                    : strings.mockExerciseIncorrectFeedback,
              ),
            ),
          const SizedBox(height: 15),
          Row(
            children: [
              FilledButton(
                onPressed: submitted || store.selectedAnswer == null ? null : store.submitExercise,
                child: Text(strings.mockExerciseSubmit),
              ),
              const SizedBox(width: 10),
              if (submitted)
                OutlinedButton(
                  onPressed: store.resetExercise,
                  child: Text(strings.mockExerciseRetry),
                ),
            ],
          ),
        ],
      ),
    );
    return PreviewPageFrame(
      location: AppRoutes.mockPractice,
      title: strings.mockExerciseStart,
      detail: true,
      mobile: ListView(padding: const EdgeInsets.all(20), children: [body]),
      desktop: ListView(
        children: [
          Text(strings.mockExerciseStart, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 22),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 780), child: body),
        ],
      ),
    );
  }
}

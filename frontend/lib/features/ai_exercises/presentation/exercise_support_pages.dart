import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';

EdgeInsets _desktopContentInset(BuildContext context, double maxWidth) {
  // The persistent shell already constrains and centers its routed content.
  return EdgeInsets.zero;
}

class ExerciseBuilderPage extends StatefulWidget {
  const ExerciseBuilderPage({super.key});
  @override
  State<ExerciseBuilderPage> createState() => _ExerciseBuilderPageState();
}

class _ExerciseBuilderPageState extends State<ExerciseBuilderPage> {
  int step = 0;
  String language = 'ja';
  final selectedSources = <String>{'notebooks'};
  final selectedCollectionIds = <String>{};
  final selectedQuestionTypes = <String>{'contextFill'};
  String? _routeSelection;
  int? _selectedMistakeIndex;
  String? mistakeRange;
  int? textbookUnit;
  bool allOwnWords = false;
  bool diagnosisFocusSelected = false;
  int count = 5;
  bool allowReuse = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final query = GoRouterState.of(context).uri.queryParameters;
    final routeSelection = '${query['source']}:${query['mistake']}';
    if (routeSelection == _routeSelection) return;
    _routeSelection = routeSelection;
    step = 0;
    count = 5;
    allowReuse = false;
    allOwnWords = false;
    diagnosisFocusSelected = false;
    mistakeRange = null;
    textbookUnit = null;
    selectedCollectionIds.clear();
    selectedQuestionTypes
      ..clear()
      ..add('contextFill');
    final mistakeIndex = int.tryParse(query['mistake'] ?? '');
    _selectedMistakeIndex =
        mistakeIndex != null && mistakeIndex >= 0 && mistakeIndex < _mockMistakes(context).length
        ? mistakeIndex
        : null;
    selectedSources
      ..clear()
      ..add(query['source'] == 'mistakes' ? 'mistakes' : 'notebooks');
    if (query['source'] != 'mistakes') {
      final store = PreviewStoreScope.of(context);
      final matching = store.notebooks.where((book) => book.targetLanguage == language);
      if (matching.isNotEmpty) selectedSources.add(matching.first.id);
    }
  }

  void _changeSelection(VoidCallback change) => setState(() {
    change();
    allowReuse = false;
  });

  bool _hasConcreteSources(PreviewFixtureStore store) {
    if (!selectedSources.any(
      (source) =>
          const {'notebooks', 'collections', 'textbook', 'mistakes', 'diagnosis'}.contains(source),
    )) {
      return false;
    }
    if (selectedSources.contains('notebooks') &&
        !allOwnWords &&
        !store.notebooks.any(
          (book) => book.targetLanguage == language && selectedSources.contains(book.id),
        )) {
      return false;
    }
    if (selectedSources.contains('collections') && selectedCollectionIds.isEmpty) return false;
    if (selectedSources.contains('textbook') && textbookUnit == null) return false;
    if (selectedSources.contains('mistakes') &&
        _selectedMistakeIndex == null &&
        mistakeRange == null) {
      return false;
    }
    if (selectedSources.contains('diagnosis') && !diagnosisFocusSelected) return false;
    return true;
  }

  List<_ExerciseCandidate> _candidates(BuildContext context, PreviewFixtureStore store) {
    final strings = AppLocalizations.of(context);
    final candidates = <String, _ExerciseCandidate>{};
    if (selectedSources.contains('notebooks')) {
      final notebookIds = store.notebooks
          .where((book) => book.targetLanguage == language && selectedSources.contains(book.id))
          .map((book) => book.id)
          .toSet();
      for (final item in store.collections.where(
        (item) =>
            item.kind == CollectionKind.word &&
            item.targetLanguage == language &&
            (allOwnWords || item.notebookIds.any(notebookIds.contains)),
      )) {
        candidates.putIfAbsent(
          item.id,
          () => _ExerciseCandidate(
            item.displayText,
            strings.mockSupportExerciseSourceNotebook,
            item.meaning,
          ),
        );
      }
    }
    if (selectedSources.contains('collections')) {
      for (final item in store.collections.where(
        (item) => item.targetLanguage == language && selectedCollectionIds.contains(item.id),
      )) {
        candidates.putIfAbsent(
          item.id,
          () => _ExerciseCandidate(
            item.displayText,
            strings.mockSupportExerciseSourceCollection,
            item.meaning,
          ),
        );
      }
    }
    if (selectedSources.contains('textbook') && textbookUnit != null) {
      final textbook = store.materials.firstWhere(
        (item) => item.type == LearningMaterialType.textbook,
      );
      final title = switch (textbookUnit!) {
        1 => strings.mockMaterialTextbookUnitFirstMeeting,
        2 => strings.mockMaterialTextbookUnitToStation,
        _ => strings.mockMaterialTextbookUnitAtCafe,
      };
      candidates['${textbook.id}:$textbookUnit'] = _ExerciseCandidate(
        strings.mockSupportExerciseUnitLabel(textbookUnit!.toString().padLeft(2, '0'), title),
        strings.mockSupportExerciseSourceTextbook,
        textbook.title,
      );
    }
    if (selectedSources.contains('mistakes')) {
      final mistakes = _mockMistakes(context);
      final indices = _selectedMistakeIndex != null
          ? <int>[_selectedMistakeIndex!]
          : [for (var index = 0; index < mistakes.length; index++) index];
      final favorites = _supportFavorites(store).value;
      for (final index in indices) {
        if (mistakes[index].state != strings.mockSupportMistakeNeedsCorrection) continue;
        if (_selectedMistakeIndex == null &&
            mistakeRange == 'bookmarked' &&
            !favorites.contains(index)) {
          continue;
        }
        candidates['mistake:$index'] = _ExerciseCandidate(
          mistakes[index].title,
          strings.mockSupportExerciseSourceMistakes,
          mistakes[index].source,
        );
      }
    }
    if (selectedSources.contains('diagnosis') && diagnosisFocusSelected) {
      candidates['diagnosis:direction'] = _ExerciseCandidate(
        strings.mockSupportDiagnosisDirectionShortTitle,
        strings.mockSupportExerciseSourceDiagnosis,
        strings.mockSupportDiagnosisDirectionEvidence,
      );
    }
    return candidates.values.toList();
  }

  Widget _reviewSettings(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final types = [
      ('contextFill', strings.mockSupportExerciseTypeContextFill),
      ('meaningChoice', strings.mockSupportExerciseTypeMeaningChoice),
      ('translationJudgement', strings.mockSupportExerciseTypeTranslationJudgement),
    ];
    return HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.mockSupportExerciseSettingsTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('question-type-${selectedQuestionTypes.first}'),
                  initialValue: selectedQuestionTypes.first,
                  decoration: InputDecoration(labelText: strings.mockSupportExerciseQuestionType),
                  items: [
                    for (final type in types)
                      DropdownMenuItem(value: type.$1, child: Text(type.$2)),
                  ],
                  onChanged: (value) => _changeSelection(() {
                    selectedQuestionTypes
                      ..clear()
                      ..add(value ?? 'contextFill');
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('question-count-$count'),
                  initialValue: count,
                  decoration: InputDecoration(labelText: strings.mockSupportExerciseQuestionCount),
                  items: [
                    DropdownMenuItem(value: 1, child: Text(strings.mockSupportExerciseCountOne)),
                    DropdownMenuItem(value: 5, child: Text(strings.mockSupportExerciseCountFive)),
                    DropdownMenuItem(value: 10, child: Text(strings.mockSupportExerciseCountTen)),
                  ],
                  onChanged: (value) => _changeSelection(() => count = value ?? 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          TextButton.icon(
            onPressed: () => setState(() => step = 0),
            icon: const Icon(Icons.chevron_left),
            label: Text(strings.mockSupportExerciseBackToEdit),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _reviewPreview(BuildContext context, List<_ExerciseCandidate> candidates) {
    final strings = AppLocalizations.of(context);
    final store = PreviewStoreScope.of(context);
    final mayConfirm =
        _hasConcreteSources(store) &&
        candidates.isNotEmpty &&
        selectedQuestionTypes.isNotEmpty &&
        (candidates.length >= count || allowReuse);
    final typeLabels = {
      'contextFill': strings.mockSupportExerciseTypeContextFill,
      'meaningChoice': strings.mockSupportExerciseTypeMeaningChoice,
      'translationJudgement': strings.mockSupportExerciseTypeTranslationJudgement,
    };
    final selectedTypeLabels = [for (final type in selectedQuestionTypes) typeLabels[type]!]
        .join('、');
    return HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.mockSupportExercisePreviewTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                strings.mockSupportExerciseCandidateCount(candidates.length),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            strings.mockSupportExercisePreviewSummary(
              language == 'ja'
                  ? strings.mockSupportExerciseBuilderJapanese
                  : strings.mockSupportExerciseBuilderEnglish,
              selectedTypeLabels,
              count,
            ),
          ),
          const SizedBox(height: 12),
          if (candidates.isEmpty) Text(strings.mockSupportExerciseNoCandidates),
          for (final candidate in candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(candidate.title),
              subtitle: Text('${candidate.source} · ${candidate.detail}'),
            ),
          if (candidates.isNotEmpty && candidates.length < count) ...[
            const SizedBox(height: 36),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.mockSupportExerciseCandidateShortage(candidates.length, count)),
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowReuse,
                      title: Text(strings.mockSupportExerciseAllowRepeatedSource),
                      onChanged: (value) => setState(() => allowReuse = value ?? false),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: mayConfirm
                  ? () {
                      store.resetExercise();
                      context.go(AppRoutes.mockPractice);
                    }
                  : null,
              child: Text(strings.mockSupportExerciseConfirmGeneration),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = PreviewStoreScope.of(context);
    final strings = AppLocalizations.of(context);
    final candidates = _candidates(context, store);
    final hasConcreteSources = _hasConcreteSources(store) && candidates.isNotEmpty;
    final content = step == 0
        ? HarukaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).mockSupportStep(step + 1),
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  step == 0
                      ? AppLocalizations.of(context).mockSupportExerciseBuilderChooseContent
                      : AppLocalizations.of(context).mockSupportExerciseBuilderConfirmSettings,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                if (step == 0) ...[
                  DropdownButtonFormField<String>(
                    initialValue: language,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)
                          .mockSupportExerciseBuilderStudyLanguage,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'ja',
                        child: Text(
                          AppLocalizations.of(context).mockSupportExerciseBuilderJapanese,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(AppLocalizations.of(context).mockSupportExerciseBuilderEnglish),
                      ),
                    ],
                    onChanged: (value) => _changeSelection(() => language = value ?? 'ja'),
                  ),
                  const SizedBox(height: 13),
                  for (final source in [
                    (
                      'notebooks',
                      AppLocalizations.of(context).mockSupportExerciseSourceNotebook,
                      AppLocalizations.of(context).mockSupportExerciseSourceNotebookDescription,
                    ),
                    (
                      'collections',
                      AppLocalizations.of(context).mockSupportExerciseSourceCollection,
                      AppLocalizations.of(context).mockSupportExerciseSourceCollectionDescription,
                    ),
                    (
                      'textbook',
                      AppLocalizations.of(context).mockSupportExerciseSourceTextbook,
                      AppLocalizations.of(context).mockSupportExerciseSourceTextbookDescription,
                    ),
                    (
                      'mistakes',
                      AppLocalizations.of(context).mockSupportExerciseSourceMistakes,
                      AppLocalizations.of(context).mockSupportExerciseSourceMistakesDescription,
                    ),
                    (
                      'diagnosis',
                      AppLocalizations.of(context).mockSupportExerciseSourceDiagnosis,
                      AppLocalizations.of(context).mockSupportExerciseSourceDiagnosisDescription,
                    ),
                  ]) ...[
                    CheckboxListTile(
                      value: selectedSources.contains(source.$1),
                      title: Text(source.$2),
                      subtitle: Text(source.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) => _changeSelection(() {
                        if (value == true) {
                          selectedSources.add(source.$1);
                        } else {
                          selectedSources.remove(source.$1);
                        }
                      }),
                    ),
                    if (source.$1 == 'notebooks' && selectedSources.contains('notebooks'))
                      HarukaSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppLocalizations.of(context).mockSupportExerciseChooseNotebook),
                            CheckboxListTile(
                              value: allOwnWords,
                              title: Text(strings.mockSupportExerciseAllOwnWords),
                              onChanged: (value) =>
                                  _changeSelection(() => allOwnWords = value ?? false),
                            ),
                            for (final book in store.notebooks.where(
                              (item) => item.targetLanguage == language,
                            ))
                              CheckboxListTile(
                                value: selectedSources.contains(book.id),
                                title: Text(book.name),
                                onChanged: (value) => _changeSelection(() {
                                  if (value == true) {
                                    selectedSources.add(book.id);
                                  } else {
                                    selectedSources.remove(book.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    if (source.$1 == 'collections' && selectedSources.contains('collections'))
                      HarukaSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(strings.mockSupportExerciseChooseCollections),
                            for (final item in store.collections.where(
                              (item) => item.targetLanguage == language,
                            ))
                              CheckboxListTile(
                                value: selectedCollectionIds.contains(item.id),
                                title: Text(item.displayText),
                                subtitle: Text(item.meaning),
                                onChanged: (value) => _changeSelection(() {
                                  if (value == true) {
                                    selectedCollectionIds.add(item.id);
                                  } else {
                                    selectedCollectionIds.remove(item.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    if (source.$1 == 'textbook' && selectedSources.contains('textbook'))
                      DropdownButtonFormField<int>(
                        key: ValueKey('textbook-unit-$textbookUnit'),
                        initialValue: textbookUnit,
                        decoration: InputDecoration(
                          labelText: strings.mockSupportExerciseSourceTextbook,
                        ),
                        items: [
                          for (final unit in [
                            (1, strings.mockMaterialTextbookUnitFirstMeeting),
                            (2, strings.mockMaterialTextbookUnitToStation),
                            (3, strings.mockMaterialTextbookUnitAtCafe),
                          ])
                            DropdownMenuItem(
                              value: unit.$1,
                              child: Text(
                                strings.mockSupportExerciseUnitLabel(
                                  unit.$1.toString().padLeft(2, '0'),
                                  unit.$2,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) => _changeSelection(() => textbookUnit = value),
                      ),
                    if (source.$1 == 'mistakes' &&
                        selectedSources.contains('mistakes') &&
                        _selectedMistakeIndex != null)
                      HarukaSurface(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_mockMistakes(context)[_selectedMistakeIndex!].title),
                          subtitle: Text(_mockMistakes(context)[_selectedMistakeIndex!].source),
                        ),
                      ),
                    if (source.$1 == 'mistakes' &&
                        selectedSources.contains('mistakes') &&
                        _selectedMistakeIndex == null)
                      DropdownButtonFormField<String>(
                        key: ValueKey('mistake-range-$mistakeRange'),
                        initialValue: mistakeRange,
                        decoration: InputDecoration(
                          labelText: strings.mockSupportExerciseChooseMistakeRange,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'current',
                            child: Text(strings.mockSupportExerciseCurrentMistakes),
                          ),
                          DropdownMenuItem(
                            value: 'bookmarked',
                            child: Text(strings.mockSupportExerciseBookmarkedMistakes),
                          ),
                        ],
                        onChanged: (value) => _changeSelection(() => mistakeRange = value),
                      ),
                    if (source.$1 == 'diagnosis' && selectedSources.contains('diagnosis'))
                      CheckboxListTile(
                        value: diagnosisFocusSelected,
                        title: Text(strings.mockSupportDiagnosisDirectionShortTitle),
                        onChanged: (value) =>
                            _changeSelection(() => diagnosisFocusSelected = value ?? false),
                      ),
                  ],
                ],
              ],
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final settings = _reviewSettings(context);
              final preview = _reviewPreview(context, candidates);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.mockSupportStep(2),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  if (compact) ...[
                    const SizedBox(height: 14),
                    Text(
                      strings.mockSupportExerciseBuilderConfirmSettings,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (compact) ...[
                    settings,
                    const SizedBox(height: 16),
                    preview,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: settings),
                        const SizedBox(width: 20),
                        Expanded(flex: 3, child: preview),
                      ],
                    ),
                ],
              );
            },
          );
    Widget nextAction() => SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1004),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.mockSupportExerciseCandidateCount(candidates.length)),
                      if (!hasConcreteSources)
                        Text(
                          candidates.isEmpty && _hasConcreteSources(store)
                              ? strings.mockSupportExerciseNoCandidates
                              : strings.mockSupportExerciseNeedConcreteSource,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: hasConcreteSources ? () => setState(() => step = 1) : null,
                  child: Text(strings.mockSupportExerciseNextToSettings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PreviewPageFrame(
      location: AppRoutes.mockExerciseBuilder,
      title: AppLocalizations.of(context).mockSupportExerciseBuilderTitle,
      detail: true,
      mobile: Column(
        children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [content]),
          ),
          if (step == 0) nextAction(),
        ],
      ),
      desktop: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1004),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.mockSupportExerciseBuilderHeadline,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 15),
                        content,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (step == 0) nextAction(),
        ],
      ),
    );
  }
}

final class _ExerciseCandidate {
  const _ExerciseCandidate(this.title, this.source, this.detail);
  final String title;
  final String source;
  final String detail;
}

String _exerciseBuilderWithMistakeSource([int? mistakeIndex]) => Uri(
  path: AppRoutes.mockExerciseBuilder,
  queryParameters: {'source': 'mistakes', if (mistakeIndex != null) 'mistake': '$mistakeIndex'},
).toString();

final class MistakeRecord {
  const MistakeRecord(this.title, this.source, this.state, this.answer, this.favorite);
  final String title;
  final String source;
  final String state;
  final String answer;
  final bool favorite;
}

List<MistakeRecord> _mockMistakes(BuildContext context) => [
  MistakeRecord(
    AppLocalizations.of(context).mockSupportMistakeDirectionTopic,
    AppLocalizations.of(context).mockSupportMistakeTextbookSource,
    AppLocalizations.of(context).mockSupportMistakeNeedsCorrection,
    AppLocalizations.of(context).mockSupportMistakeDirectionError,
    false,
  ),
  MistakeRecord(
    AppLocalizations.of(context).mockSupportMistakeReferenceTopic,
    AppLocalizations.of(context).mockSupportMistakeExamSource,
    AppLocalizations.of(context).mockSupportMistakeImproved,
    AppLocalizations.of(context).mockSupportMistakeReferenceError,
    true,
  ),
  MistakeRecord(
    AppLocalizations.of(context).mockSupportMistakeMeaningTopic,
    AppLocalizations.of(context).mockSupportMistakeAiExerciseSource,
    AppLocalizations.of(context).mockSupportMistakeNeedsCorrection,
    AppLocalizations.of(context).mockSupportMistakeMeaningError,
    false,
  ),
];

class MistakesPage extends StatelessWidget {
  const MistakesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mistakes = _mockMistakes(context);
    final favorites = _supportFavorites(PreviewStoreScope.of(context));
    return PreviewPageFrame(
      location: AppRoutes.mockMistakes,
      title: AppLocalizations.of(context).mockSupportMistakeLibraryTitle,
      detail: true,
      detailNotifications: false,
      mobile: MobileMistakesView(mistakes: mistakes, favorites: favorites),
      desktop: DesktopMistakesView(mistakes: mistakes, favorites: favorites),
    );
  }
}

final _favoriteMistakes = Expando<ValueNotifier<Set<int>>>();
ValueNotifier<Set<int>> _supportFavorites(PreviewFixtureStore store) =>
    _favoriteMistakes[store] ??= ValueNotifier(<int>{1});

class MobileMistakesView extends StatelessWidget {
  const MobileMistakesView({required this.mistakes, required this.favorites, super.key});
  final List<MistakeRecord> mistakes;
  final ValueNotifier<Set<int>> favorites;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: favorites,
      builder: (context, saved, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
        children: [
          Text(
            strings.mockSupportMistakeLibraryTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MistakeStat(
                  count: mistakes.length,
                  label: strings.mockSupportMistakeHistoricalExamples,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MistakeStat(
                  count: saved.length,
                  label: strings.mockSupportMistakeBookmarked,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(strings.mockSupportMistakeListTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (var i = 0; i < mistakes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: HarukaSurface(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => context.push(AppRoutes.mockMistakePath(i)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _MistakeStateLabel(label: mistakes[i].state)),
                            if (saved.contains(i))
                              Icon(
                                Icons.bookmark_outline,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(mistakes[i].title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          mistakes[i].source,
                          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          OutlinedButton(
            onPressed: () => context.push(_exerciseBuilderWithMistakeSource()),
            child: Text(strings.mockSupportMistakeChooseAsSource),
          ),
        ],
      ),
    );
  }
}

class DesktopMistakesView extends StatelessWidget {
  const DesktopMistakesView({required this.mistakes, required this.favorites, super.key});
  final List<MistakeRecord> mistakes;
  final ValueNotifier<Set<int>> favorites;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: favorites,
      builder: (context, saved, _) => ListView(
        padding: _desktopContentInset(context, 1320),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.mockSupportMistakeLibraryTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: _MistakeStat(
                        count: mistakes.length,
                        label: strings.mockSupportMistakeHistoricalExamples,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MistakeStat(
                        count: mistakes
                            .where(
                              (item) => item.state == strings.mockSupportMistakeNeedsCorrection,
                            )
                            .length,
                        label: strings.mockSupportMistakeNeedsCorrection,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MistakeStat(
                        count: saved.length,
                        label: strings.mockSupportMistakeBookmarked,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.mockSupportMistakeListTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(_exerciseBuilderWithMistakeSource()),
                      child: Text(strings.mockSupportMistakeChooseAsSource),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                HarukaSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: Text(strings.mockSupportMistakeTopicColumn)),
                            Expanded(flex: 3, child: Text(strings.mockSupportMistakeSourceColumn)),
                            Expanded(flex: 2, child: Text(strings.mockSupportMistakeStatusColumn)),
                            SizedBox(
                              width: 90,
                              child: Text(strings.mockSupportMistakeBookmarkColumn),
                            ),
                            Text(strings.mockSupportMistakeViewColumn),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      for (var i = 0; i < mistakes.length; i++) ...[
                        InkWell(
                          onTap: () => context.push(AppRoutes.mockMistakePath(i)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    mistakes[i].title,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    mistakes[i].source,
                                    style: TextStyle(color: colors.onSurfaceVariant),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _MistakeStateLabel(label: mistakes[i].state),
                                  ),
                                ),
                                SizedBox(
                                  width: 90,
                                  child: saved.contains(i)
                                      ? Icon(Icons.bookmark_outline, color: colors.primary)
                                      : const SizedBox.shrink(),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                        if (i < mistakes.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MistakeStat extends StatelessWidget {
  const _MistakeStat({required this.count, required this.label});
  final int count;
  final String label;
  @override
  Widget build(BuildContext context) => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

class _MistakeStateLabel extends StatelessWidget {
  const _MistakeStateLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final improved = label == AppLocalizations.of(context).mockSupportMistakeImproved;
    final roles = HarukaColors.of(context);
    final statusColor = improved ? roles.positive : roles.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: statusColor, fontSize: 12)),
    );
  }
}

class MistakeDetailPage extends StatefulWidget {
  const MistakeDetailPage({required this.index, super.key});
  final int index;
  @override
  State<MistakeDetailPage> createState() => _MistakeDetailPageState();
}

class _MistakeDetailPageState extends State<MistakeDetailPage> {
  @override
  Widget build(BuildContext context) {
    final mistakes = _mockMistakes(context);
    if (widget.index < 0 || widget.index >= mistakes.length) {
      final notFound = Center(child: Text(AppLocalizations.of(context).apiResourceNotFound));
      return PreviewPageFrame(
        location: AppRoutes.mockMistakePath(widget.index),
        title: AppLocalizations.of(context).mockSupportMistakeDetailTitle,
        detail: true,
        detailNotifications: false,
        mobile: notFound,
        desktop: notFound,
      );
    }
    final mistake = mistakes[widget.index];
    final favorites = _supportFavorites(PreviewStoreScope.of(context));
    void toggleFavorite() {
      final next = {...favorites.value};
      if (!next.remove(widget.index)) next.add(widget.index);
      favorites.value = next;
    }

    return PreviewPageFrame(
      location: AppRoutes.mockMistakePath(widget.index),
      title: AppLocalizations.of(context).mockSupportMistakeDetailTitle,
      detail: true,
      detailNotifications: false,
      mobile: MobileMistakeDetailView(
        mistake: mistake,
        index: widget.index,
        favorites: favorites,
        onFavorite: toggleFavorite,
      ),
      desktop: DesktopMistakeDetailView(
        mistake: mistake,
        index: widget.index,
        favorites: favorites,
        onFavorite: toggleFavorite,
      ),
    );
  }
}

class MobileMistakeDetailView extends StatelessWidget {
  const MobileMistakeDetailView({
    required this.mistake,
    required this.index,
    required this.favorites,
    required this.onFavorite,
    super.key,
  });
  final MistakeRecord mistake;
  final int index;
  final ValueNotifier<Set<int>> favorites;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: favorites,
      builder: (context, saved, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
        children: [
          Text(mistake.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            mistake.source,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _MistakeStateLabel(label: mistake.state),
          ),
          const SizedBox(height: 16),
          _MistakeAnswer(mistake: mistake),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onFavorite,
                  icon: Icon(saved.contains(index) ? Icons.bookmark : Icons.bookmark_outline),
                  label: Text(
                    saved.contains(index)
                        ? strings.mockSupportMistakeRemoveBookmark
                        : strings.mockSupportMistakeBookmarkAction,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push(_exerciseBuilderWithMistakeSource(index)),
                  child: Text(strings.mockSupportMistakeGenerateTargeted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DesktopMistakeDetailView extends StatelessWidget {
  const DesktopMistakeDetailView({
    required this.mistake,
    required this.index,
    required this.favorites,
    required this.onFavorite,
    super.key,
  });
  final MistakeRecord mistake;
  final int index;
  final ValueNotifier<Set<int>> favorites;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: favorites,
      builder: (context, saved, _) => ListView(
        padding: _desktopContentInset(context, 1320),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mistake.title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  mistake.source,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MistakeStateLabel(label: mistake.state),
                          const SizedBox(height: 14),
                          _MistakeAnswer(mistake: mistake),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: HarukaSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.mockSupportDiagnosisNextStep,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: onFavorite,
                                icon: Icon(
                                  saved.contains(index) ? Icons.bookmark : Icons.bookmark_outline,
                                ),
                                label: Text(
                                  saved.contains(index)
                                      ? strings.mockSupportMistakeRemoveBookmark
                                      : strings.mockSupportMistakeBookmarkAction,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () =>
                                    context.push(_exerciseBuilderWithMistakeSource(index)),
                                child: Text(strings.mockSupportMistakeGenerateTargeted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MistakeAnswer extends StatelessWidget {
  const _MistakeAnswer({required this.mistake});
  final MistakeRecord mistake;
  @override
  Widget build(BuildContext context) => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).mockSupportMistakePreviousAnswer,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        Text(mistake.answer),
        const SizedBox(height: 38),
        const Divider(),
      ],
    ),
  );
}

class DiagnosisPage extends StatelessWidget {
  const DiagnosisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PreviewPageFrame(
      location: AppRoutes.mockDiagnosis,
      title: AppLocalizations.of(context).mockSupportDiagnosisTitle,
      detail: true,
      detailNotifications: false,
      mobile: const MobileDiagnosisView(),
      desktop: const DesktopDiagnosisView(),
    );
  }
}

class MobileDiagnosisView extends StatelessWidget {
  const MobileDiagnosisView({super.key});
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      children: [
        Text(strings.mockSupportDiagnosisTitle, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        _DiagnosisFocusCard(mobile: true),
        const SizedBox(height: 14),
        HarukaSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.mockSupportDiagnosisStrengths,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(strings.mockSupportDiagnosisStrengthDescription),
            ],
          ),
        ),
        const SizedBox(height: 14),
        HarukaSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.mockSupportDiagnosisNextStep,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(strings.mockSupportDiagnosisNextStepDescription),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(AppRoutes.mockExerciseBuilder),
                  child: Text(strings.mockSupportDiagnosisChooseSource),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DesktopDiagnosisView extends StatelessWidget {
  const DesktopDiagnosisView({super.key});
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListView(
      padding: _desktopContentInset(context, 1320),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.mockSupportDiagnosisTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: _DiagnosisFocusCard(mobile: false)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: HarukaSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(strings.mockSupportDiagnosisStrengths),
                          const SizedBox(height: 18),
                          Text(
                            strings.mockSupportDiagnosisStrengthTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(strings.mockSupportDiagnosisStrengthDescription),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: HarukaSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(strings.mockSupportDiagnosisNextStep),
                          const SizedBox(height: 18),
                          Text(
                            strings.mockSupportDiagnosisNextStepTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(strings.mockSupportDiagnosisNextStepDescription),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => context.push(AppRoutes.mockExerciseBuilder),
                            child: Text(strings.mockSupportDiagnosisChooseSource),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosisFocusCard extends StatelessWidget {
  const _DiagnosisFocusCard({required this.mobile});
  final bool mobile;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mobile
                ? strings.mockSupportDiagnosisRecentSevenDays
                : strings.mockSupportDiagnosisWeakness,
          ),
          const SizedBox(height: 18),
          Text(
            mobile
                ? strings.mockSupportDiagnosisDirectionFocus
                : strings.mockSupportDiagnosisDirectionShortTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(strings.mockSupportDiagnosisDirectionEvidence),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go(
              Uri(
                path: AppRoutes.mockMaterialPath(PreviewStoreScope.of(context).materials[1].id),
                queryParameters: const {'unit': '2'},
              ).toString(),
            ),
            child: Text(strings.mockSupportDiagnosisReturnToTextbook),
          ),
        ],
      ),
    );
  }
}

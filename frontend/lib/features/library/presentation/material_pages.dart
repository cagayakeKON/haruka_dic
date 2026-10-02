import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/query_prefill.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/features/novels/presentation/selection_overlay.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/features/library/presentation/material_catalog_access.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/collections/reference_feature_scope.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/identified.dart';

import 'published_novel_reader.dart';
import '../../../core/api/learning_models.dart' as published;
import 'material_management_controls.dart';

void _unused() {}
void _unusedBool(bool _) {}
void _unusedInt(int _) {}
void _unusedDouble(double _) {}
void _unusedCard(LearningCard _) {}

List<String> _mockChapters(BuildContext context) => [
  AppLocalizations.of(context).mockMaterialChapterSeasideMailbox,
  AppLocalizations.of(context).mockMaterialChapterAfterRain,
  AppLocalizations.of(context).mockMaterialChapterBeyondWindow,
  AppLocalizations.of(context).mockMaterialChapterLetterToFuture,
];
List<String> _mockNovelSentences(BuildContext context) => [
  AppLocalizations.of(context).mockMaterialNovelMorningLightSentence,
  AppLocalizations.of(context).mockMaterialNovelSummerWindSentence,
  AppLocalizations.of(context).mockMaterialNovelLetterOnDeskSentence,
  AppLocalizations.of(context).mockMaterialNovelFamiliarHandwritingSentence,
  AppLocalizations.of(context).mockMaterialNovelUnfamiliarWordsSentence,
];
List<String> _mockNovelTranslations(BuildContext context) => [
  AppLocalizations.of(context).mockMaterialNovelMorningLightTranslation,
  AppLocalizations.of(context).mockMaterialNovelSummerWindTranslation,
  AppLocalizations.of(context).mockMaterialNovelLetterOnDeskTranslation,
  AppLocalizations.of(context).mockMaterialNovelFamiliarHandwritingTranslation,
  AppLocalizations.of(context).mockMaterialNovelUnfamiliarWordsTranslation,
];
List<String> _mockNovelRubySegments(BuildContext context) => [
  AppLocalizations.of(context).mockMaterialNovelMorningLightRubySegments,
  AppLocalizations.of(context).mockMaterialNovelSummerWindRubySegments,
  AppLocalizations.of(context).mockMaterialNovelLetterOnDeskRubySegments,
  AppLocalizations.of(context).mockMaterialNovelFamiliarHandwritingRubySegments,
  AppLocalizations.of(context).mockMaterialNovelUnfamiliarWordsRubySegments,
];

List<String> _splitKnownNovelWords(String text, Iterable<String> words) {
  var parts = [text];
  for (final word in words.where((value) => value.isNotEmpty)) {
    final next = <String>[];
    for (final part in parts) {
      if (part == word || !part.contains(word)) {
        next.add(part);
        continue;
      }
      final pieces = part.split(word);
      for (var index = 0; index < pieces.length; index++) {
        if (pieces[index].isNotEmpty) next.add(pieces[index]);
        if (index < pieces.length - 1) next.add(word);
      }
    }
    parts = next;
  }
  return parts;
}

class RubySentence extends StatelessWidget {
  const RubySentence({required this.segments, required this.fontSize, super.key});

  final String segments;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grouped = <(String, String, String)>[];
    final closingPunctuation = RegExp(r'^[、。！？!?，．,.））」』】〕》〉…]+$');
    for (final segment in segments.split('|')) {
      final parts = segment.split('~');
      final base = parts.first;
      final reading = parts.length > 1 ? parts[1] : '';
      if (grouped.isNotEmpty && reading.isEmpty && closingPunctuation.hasMatch(base)) {
        final previous = grouped.removeLast();
        grouped.add((previous.$1, previous.$2, previous.$3 + base));
      } else {
        grouped.add((base, reading, ''));
      }
    }
    return Wrap(
      runSpacing: 2,
      children: [
        for (final segment in grouped)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectionContainer.disabled(
                    child: Text(
                      segment.$2,
                      style: TextStyle(
                        fontSize: fontSize * .48,
                        color: scheme.onSurfaceVariant,
                        height: 1,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  Text(
                    segment.$1,
                    style: TextStyle(fontSize: fontSize, height: 1.6, fontFamily: 'serif'),
                  ),
                ],
              ),
              if (segment.$3.isNotEmpty)
                Text(
                  segment.$3,
                  style: TextStyle(fontSize: fontSize, height: 1.6, fontFamily: 'serif'),
                ),
            ],
          ),
      ],
    );
  }
}

class MaterialEntryPage extends StatefulWidget {
  const MaterialEntryPage({required this.materialId, super.key});
  final String materialId;

  @override
  State<MaterialEntryPage> createState() => _MaterialEntryPageState();
}

class _MaterialEntryPageState extends State<MaterialEntryPage> {
  Object? _scopeIdentity;
  (String, int, String)? _materialIdentity;
  NovelReadingLocation? _novelLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ReferenceFeatureScope.maybeOf(context) != null) return;
    final coordinator = PreviewSettingsCacheScope.of(context).coordinator;
    final scope = coordinator.scope;
    final identity = (
      coordinator.scopeGeneration,
      scope?.binding,
      scope?.securityEpoch,
      scope?.authzVersion,
      scope?.policyVersion,
    );
    if (_scopeIdentity != identity) {
      _scopeIdentity = identity;
      _materialIdentity = null;
      _novelLocation = null;
    }
    final catalog = MaterialCatalogScope.of(context);
    if (catalog.status == MaterialCatalogStatus.blocked ||
        (catalog.status == MaterialCatalogStatus.ready &&
            catalog.findById(widget.materialId) == null)) {
      _materialIdentity = null;
      _novelLocation = null;
    }
  }

  @override
  void didUpdateWidget(covariant MaterialEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.materialId != widget.materialId) {
      _materialIdentity = null;
      _novelLocation = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = ReferenceFeatureScope.maybeOf(context);
    final live = liveMaterialCatalog(context);
    if (live != null) {
      return LiveMaterialDetailsPage(
        materialId: widget.materialId,
        catalog: live,
        reader: reference == null
            ? null
            : (row) => PublishedNovelReader(
                materialId: widget.materialId,
                reference: reference,
                available: published.MaterialSummary(
                  id: row.id,
                  libraryId: row.libraryId,
                  revisionId: row.contentRevisionId!,
                  firstChapterId: row.firstChapterId!,
                  title: row.title,
                  language: row.language!,
                ),
              ),
      );
    }
    if (reference != null) {
      return PublishedNovelReader(materialId: widget.materialId, reference: reference);
    }
    return MaterialCatalogAccess(
      builder: (context, catalog) {
        final item = catalog.findById(widget.materialId);
        if (item == null) {
          _materialIdentity = null;
          _novelLocation = null;
          return PreviewPageFrame(
            location: AppRoutes.mockLibrary,
            title: AppLocalizations.of(context).mockMaterialUnavailableTitle,
            detail: true,
            desktopBackLabel: AppLocalizations.of(context).mockLibraryTitle,
            onBack: () => _returnToLibrary(context),
            mobile: Center(
              child: Text(AppLocalizations.of(context).mockMaterialUnavailableMessage),
            ),
            desktop: Center(
              child: Text(AppLocalizations.of(context).mockMaterialUnavailableMessage),
            ),
          );
        }
        if (item.type == LearningMaterialType.novel) {
          final identity = (item.id, item.revision, item.status);
          if (_materialIdentity != identity) {
            _materialIdentity = identity;
            _novelLocation = NovelReadingLocation();
          }
          return NovelPage(item: item, location: _novelLocation!);
        }
        _materialIdentity = null;
        _novelLocation = null;
        return switch (item.type) {
          LearningMaterialType.novel => throw StateError('Novel material is handled above'),
          LearningMaterialType.textbook => TextbookPage(item: item),
          LearningMaterialType.exam => ExamPrepPage(item: item),
        };
      },
    );
  }
}

class MaterialDetailsPage extends StatelessWidget {
  const MaterialDetailsPage({required this.materialId, super.key});
  final String materialId;

  @override
  Widget build(BuildContext context) {
    final live = liveMaterialCatalog(context);
    if (live != null) return LiveMaterialDetailsPage(materialId: materialId, catalog: live);
    return MaterialCatalogAccess(
      builder: (context, catalog) {
        final item = catalog.findById(materialId);
        if (item == null) {
          final l10n = AppLocalizations.of(context);
          return PreviewPageFrame(
            location: AppRoutes.mockLibrary,
            title: l10n.mockMaterialUnavailableTitle,
            detail: true,
            desktopBackLabel: l10n.mockLibraryTitle,
            onBack: () => _returnToLibrary(context),
            mobile: Center(child: Text(l10n.mockMaterialDeletedMessage)),
            desktop: Center(child: Text(l10n.mockMaterialDeletedMessage)),
          );
        }
        final content = HarukaSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(item.description),
              const SizedBox(height: 15),
              Text(
                AppLocalizations.of(context)
                    .mockMaterialTypeDetail(materialTypeLabel(context, item.type)),
              ),
              Text(
                AppLocalizations.of(context).mockMaterialLanguageDetail(
                  item.language == 'ja'
                      ? AppLocalizations.of(context).mockMaterialJapanese
                      : AppLocalizations.of(context).mockMaterialEnglish,
                ),
              ),
              Text(
                AppLocalizations.of(context)
                    .mockMaterialStatusDetail(materialStatusLabel(context, item)),
              ),
              Text(AppLocalizations.of(context).mockMaterialCurrentRevision(item.revision)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.push(AppRoutes.mockMaterialPath(item.id)),
                child: Text(switch (item.type) {
                  LearningMaterialType.novel => AppLocalizations.of(
                    context,
                  ).mockMaterialStartReading,
                  LearningMaterialType.textbook => AppLocalizations.of(
                    context,
                  ).mockMaterialStartLearning,
                  LearningMaterialType.exam => AppLocalizations.of(
                    context,
                  ).mockMaterialViewExamPreparation,
                }),
              ),
            ],
          ),
        );
        return PreviewPageFrame(
          location: AppRoutes.mockMaterialDetailsPath(item.id),
          title: AppLocalizations.of(context).mockMaterialDetailsTitle,
          detail: true,
          mobile: ListView(padding: const EdgeInsets.all(20), children: [content]),
          desktop: ListView(
            children: [
              Text(
                AppLocalizations.of(context).mockMaterialDetailsTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              content,
            ],
          ),
        );
      },
    );
  }
}

void _returnToLibrary(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.mockLibrary);
  }
}

/// Route-local view location. The material gate can unmount the reader while
/// revalidating access; this holds only indices and is discarded on scope or
/// material revision changes.
final class NovelReadingLocation {
  int chapter = 2;
  int? selectedSentence;
  bool restoreSentenceSheet = false;
}

/// The root navigator keeps a bottom sheet mounted when the reader is gated.
/// Its body must recheck the same private scope and material revision itself.
final class _NovelSheetAccess {
  _NovelSheetAccess.capture(BuildContext context, this.item)
    : adapter = PreviewSettingsCacheScope.of(context),
      catalog = MaterialCatalogScope.of(context),
      scopeStamp = _scopeStamp(PreviewSettingsCacheScope.of(context).coordinator),
      materialStamp = (item.id, item.revision, item.status);

  final MaterialSummary item;
  final PreviewSettingsCacheAdapter adapter;
  final MaterialCatalog catalog;
  final Object scopeStamp;
  final (String, int, String) materialStamp;

  static Object _scopeStamp(CacheCoordinator coordinator) {
    final scope = coordinator.scope;
    return (
      coordinator.scopeGeneration,
      scope?.binding,
      scope?.securityEpoch,
      scope?.authzVersion,
      scope?.policyVersion,
    );
  }

  bool isReadable([BuildContext? context]) {
    if (context != null &&
        (!identical(PreviewSettingsCacheScope.of(context), adapter) ||
            !identical(MaterialCatalogScope.of(context), catalog))) {
      return false;
    }
    final current = catalog.findById(item.id);
    return adapter.coordinator.accessReady &&
        catalog.status == MaterialCatalogStatus.ready &&
        _scopeStamp(adapter.coordinator) == scopeStamp &&
        current != null &&
        (current.id, current.revision, current.status) == materialStamp;
  }

  Widget gate(WidgetBuilder content, {double? heightFraction}) =>
      _NovelAccessGate(access: this, content: content, heightFraction: heightFraction);
}

class _NovelAccessGate extends StatefulWidget {
  const _NovelAccessGate({required this.access, required this.content, this.heightFraction});

  final _NovelSheetAccess access;
  final WidgetBuilder content;
  final double? heightFraction;

  @override
  State<_NovelAccessGate> createState() => _NovelAccessGateState();
}

class _NovelAccessGateState extends State<_NovelAccessGate> {
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    widget.access.adapter.addListener(_onAccessChanged);
    widget.access.catalog.addListener(_onAccessChanged);
  }

  @override
  void didUpdateWidget(covariant _NovelAccessGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.access, widget.access)) return;
    oldWidget.access.adapter.removeListener(_onAccessChanged);
    oldWidget.access.catalog.removeListener(_onAccessChanged);
    widget.access.adapter.addListener(_onAccessChanged);
    widget.access.catalog.addListener(_onAccessChanged);
  }

  void _onAccessChanged() {
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.access.adapter.removeListener(_onAccessChanged);
    widget.access.catalog.removeListener(_onAccessChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access.isReadable(context)) return widget.content(context);
    final unavailable = Center(
      child: Text(AppLocalizations.of(context).mockMaterialUnavailableMessage),
    );
    final heightFraction = widget.heightFraction;
    return heightFraction == null
        ? unavailable
        : SizedBox(height: MediaQuery.sizeOf(context).height * heightFraction, child: unavailable);
  }
}

Key _novelScrollKey(BuildContext context, MaterialSummary item, int chapter, bool mobile) {
  final coordinator = PreviewSettingsCacheScope.of(context).coordinator;
  final scope = coordinator.scope;
  return PageStorageKey<Object>((
    mobile,
    item.id,
    item.revision,
    chapter,
    coordinator.scopeGeneration,
    scope?.binding,
    scope?.securityEpoch,
    scope?.authzVersion,
    scope?.policyVersion,
  ));
}

class NovelPage extends StatefulWidget {
  const NovelPage({required this.item, required this.location, super.key});
  final MaterialSummary item;
  final NovelReadingLocation location;
  @override
  State<NovelPage> createState() => _NovelPageState();
}

class _NovelPageState extends State<NovelPage> {
  int chapter = 2;
  bool analysis = false;
  bool modeInitialized = false;
  int? selectedSentence;
  int? selectedRangeSentence;
  NovelNativeSelection? selectedNativeSelection;
  Set<int> selectedTokens = {};
  int rangeStart = 0;
  int rangeEnd = 0;
  String? selectedQueryText;
  LearningCard? selectedQueryCard;
  _NovelSheetAccess? selectedQueryAccess;
  bool bookmark = false;
  bool playbackVisible = false;
  bool playbackPaused = false;
  bool playbackFinished = false;
  bool playbackContinuous = true;
  int playbackSentence = 0;
  double playbackProgress = 0;
  double playbackSpeed = 1;
  double fontSize = 18;
  final Map<int, int> analysisReadyByChapter = {};
  final Map<int, int> audioReadyByChapter = {};
  Timer? preparationTimer;
  Timer? playbackTimer;
  bool preparing = false;
  bool _restoreSheetScheduled = false;

  @override
  void initState() {
    super.initState();
    chapter = widget.location.chapter;
    selectedSentence = widget.location.selectedSentence;
  }

  @override
  void didUpdateWidget(covariant NovelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.location, widget.location)) {
      preparationTimer?.cancel();
      playbackTimer?.cancel();
      chapter = widget.location.chapter;
      selectedSentence = widget.location.selectedSentence;
      selectedRangeSentence = null;
      selectedNativeSelection = null;
      selectedQueryText = null;
      selectedQueryCard = null;
      selectedQueryAccess = null;
      playbackVisible = false;
    }
  }

  void _restoreSentenceSheet() {
    if (_restoreSheetScheduled ||
        !widget.location.restoreSentenceSheet ||
        selectedSentence == null) {
      return;
    }
    _restoreSheetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSheetScheduled = false;
      if (!mounted ||
          !widget.location.restoreSentenceSheet ||
          selectedSentence == null ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      widget.location.restoreSentenceSheet = false;
      selectSentence(selectedSentence!, mobile: true);
    });
  }

  bool get playing => playbackVisible && !playbackPaused && !playbackFinished;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!modeInitialized) {
      analysis = MediaQuery.sizeOf(context).width >= 760;
      modeInitialized = true;
    }
  }

  List<String> tokensFor(BuildContext context, int index) {
    final knownWords = PreviewStoreScope.of(context).cards
        .where((card) => card.kind == CollectionKind.word)
        .map((card) => card.title);
    return [
      for (final segment in _mockNovelRubySegments(context)[index].split('|'))
        for (final part
            in segment
                .split('~')
                .first
                .replaceAllMapped(RegExp(r'[、。！？,.!?]'), (match) => '|${match[0]}|')
                .split('|'))
          if (part.isNotEmpty)
            for (final token in _splitKnownNovelWords(part, knownWords))
              if (token.isNotEmpty) token,
    ];
  }

  void pausePlayback() {
    if (playing) setState(() => playbackPaused = true);
  }

  void stopPlayback() {
    playbackTimer?.cancel();
    setState(() {
      playbackVisible = false;
      playbackPaused = false;
      playbackFinished = false;
      playbackProgress = 0;
    });
  }

  void startPlayback({required bool continuous, int? sentence}) {
    playbackTimer?.cancel();
    setState(() {
      playbackVisible = true;
      playbackPaused = false;
      playbackFinished = false;
      playbackContinuous = continuous;
      playbackSentence = sentence ?? selectedSentence ?? 0;
      playbackProgress = 0;
      selectedRangeSentence = null;
      selectedNativeSelection = null;
    });
    playbackTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (playbackPaused) return;
      setState(() {
        playbackProgress += .075 * playbackSpeed;
        if (playbackProgress < 1) return;
        if (playbackContinuous && playbackSentence < _mockNovelSentences(context).length - 1) {
          playbackSentence++;
          playbackProgress = 0;
        } else {
          playbackProgress = 1;
          playbackPaused = true;
          playbackFinished = true;
          timer.cancel();
        }
      });
    });
  }

  void togglePlayback() {
    if (!playbackVisible || playbackFinished) {
      startPlayback(
        continuous: playbackContinuous,
        sentence: playbackFinished && playbackContinuous ? 0 : playbackSentence,
      );
    } else {
      setState(() => playbackPaused = !playbackPaused);
    }
  }

  void selectRange(int index) {
    final tokens = tokensFor(context, index);
    setState(() {
      selectedRangeSentence = index;
      selectedNativeSelection = null;
      selectedTokens = {};
      rangeStart = 0;
      rangeEnd = tokens.length - 1;
      selectedQueryText = null;
      selectedQueryAccess = null;
      playbackPaused = playbackVisible;
    });
  }

  void selectRangeFromKeyboard(int index, NovelNativeSelection? selection) {
    selectRange(index);
    if (selection == null) return;
    final sentences = _mockNovelSentences(context);
    final sentence = sentences[index];
    final source = selection.endOffset > sentence.length && index + 1 < sentences.length
        ? '$sentence ${sentences[index + 1]}'
        : sentence;
    final exact =
        selection.startOffset >= 0 &&
        selection.endOffset <= source.length &&
        selection.endOffset > selection.startOffset &&
        source.substring(selection.startOffset, selection.endOffset) == selection.text;
    if (exact) {
      setState(() => selectedNativeSelection = selection);
    }
  }

  void toggleToken(int index) => setState(() {
    selectedNativeSelection = null;
    selectedTokens = {...selectedTokens};
    if (!selectedTokens.add(index)) selectedTokens.remove(index);
  });

  void changeRangeStart(int index) => setState(() {
    selectedNativeSelection = null;
    rangeStart = index;
    if (rangeEnd < index) rangeEnd = index;
    selectedTokens = {};
  });

  void changeRangeEnd(int index) => setState(() {
    selectedNativeSelection = null;
    rangeEnd = index;
    if (rangeStart > index) rangeStart = index;
    selectedTokens = {};
  });

  void querySelection({required bool mobile}) {
    final index = selectedRangeSentence;
    if (index == null) return;
    final tokens = tokensFor(context, index);
    final selected = selectedTokens.toList()..sort();
    final text =
        selectedNativeSelection?.text ??
        (selected.isNotEmpty
            ? selected.map((value) => tokens[value]).join('')
            : rangeStart == 0 && rangeEnd == tokens.length - 1
            ? _mockNovelSentences(context)[index]
            : tokens.sublist(rangeStart, rangeEnd + 1).join(''));
    final cards = PreviewStoreScope.of(context).cards;
    final l10n = AppLocalizations.of(context);
    final matched =
        cards.where((card) => card.title == text).firstOrNull ??
        (text == l10n.mockMaterialNovelWindowWord
            ? LearningCard(
                id: 'f6666666-6666-4666-8666-666666666666',
                kind: CollectionKind.word,
                title: l10n.mockMaterialNovelWindowWord,
                explanation: l10n.mockMaterialNovelWindowMeaning,
                examples: [
                  l10n.mockMaterialNovelSummerWindSentence,
                  l10n.mockMaterialNovelSummerWindTranslation,
                ],
                version: 1,
              )
            : null);
    final access = _NovelSheetAccess.capture(context, widget.item);
    setState(() {
      selectedRangeSentence = null;
      selectedNativeSelection = null;
      selectedSentence = null;
      selectedQueryText = text;
      selectedQueryCard = matched;
      selectedQueryAccess = access;
      playbackPaused = playbackVisible;
    });
    if (mobile) {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          sheetAnimationStyle: HarukaMotion.sheetStyle(
            context,
            reducedMotion: PreviewStoreScope.of(context).reducedMotion,
          ),
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => access.gate(
            (sheetContext) => SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .72,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      AppLocalizations.of(sheetContext).mockMaterialNovelQueryResultTitle,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    NovelSelectionResultBody(
                      selectedText: text,
                      source: AppLocalizations.of(sheetContext).mockMaterialSentenceSource(
                        widget.item.title,
                        chapter + 1,
                        _mockChapters(sheetContext)[chapter],
                      ),
                      card: matched,
                      onSave: () {
                        if (matched != null) _saveQueryCard(matched, access);
                      },
                    ),
                  ],
                ),
              ),
            ),
            heightFraction: .72,
          ),
        ),
      );
    }
  }

  void _saveQueryCard(LearningCard card, _NovelSheetAccess access) {
    if (!mounted || !access.isReadable()) return;
    if (selectedQueryCard?.id != card.id || selectedQueryCard?.version != card.version) return;
    PreviewStoreScope.of(context).saveCard(card);
  }

  @override
  void dispose() {
    preparationTimer?.cancel();
    playbackTimer?.cancel();
    super.dispose();
  }

  void selectSentence(int index, {bool mobile = false}) {
    setState(() {
      selectedSentence = index;
      selectedRangeSentence = null;
      selectedNativeSelection = null;
      selectedQueryText = null;
      playbackPaused = playbackVisible;
    });
    if (mobile) {
      unawaited(_showSentenceDialog(index));
    }
  }

  Future<void> _showSentenceDialog(int index) async {
    final access = _NovelSheetAccess.capture(context, widget.item);

    TransitionRoute<dynamic>? sheetRoute;
    final queryIndex = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext) as TransitionRoute<dynamic>?;
        return access.gate(
          (context) => SentenceDialog(item: widget.item, chapter: chapter, index: index),
          heightFraction: .88,
        );
      },
    );
    if (queryIndex == null || !access.isReadable()) return;
    await sheetRoute?.completed;
    if (!mounted || !access.isReadable(context)) return;
    setState(() => selectedSentence = queryIndex);
    widget.location.selectedSentence = queryIndex;
    await _querySentence(queryIndex, reopenMobile: true);
  }

  Future<void> _querySentence(int index, {bool reopenMobile = false}) async {
    final adapter = context
        .dependOnInheritedWidgetOfExactType<PreviewSettingsCacheScope>()
        ?.notifier;
    final coordinator = adapter?.coordinator;
    final prefill = coordinator == null
        ? null
        : QueryPrefill.capture(coordinator, _mockNovelSentences(context)[index]);
    if (prefill == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      return;
    }
    if (reopenMobile) widget.location.restoreSentenceSheet = true;
    await context.push(AppRoutes.mockQuery, extra: prefill);
    if (reopenMobile) {
      if (prefill.read(coordinator!) == null) {
        widget.location.restoreSentenceSheet = false;
      } else if (mounted) {
        _restoreSentenceSheet();
      }
    }
  }

  Future<void> prepareChapter() async {
    final access = _NovelSheetAccess.capture(context, widget.item);
    bool analysisChecked = true;
    bool audioChecked = true;
    int targetChapter = chapter;
    StateSetter? refreshSheet;
    Widget content(BuildContext sheetContext, StateSetter update) {
      refreshSheet = update;
      final l10n = AppLocalizations.of(sheetContext);
      final scheme = Theme.of(sheetContext).colorScheme;
      final analysisReady = analysisReadyByChapter[targetChapter] ?? 0;
      final audioReady = audioReadyByChapter[targetChapter] ?? 0;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.mockMaterialPrepareChapter,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.mockMaterialClose,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.mockMaterialSelectChapter,
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 7),
                DropdownMenu<int>(
                  initialSelection: targetChapter,
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (var i = 0; i < _mockChapters(sheetContext).length; i++)
                      DropdownMenuEntry(
                        value: i,
                        label: l10n.mockMaterialChapterTitle(i + 1, _mockChapters(sheetContext)[i]),
                      ),
                  ],
                  onSelected: (value) {
                    if (mounted && access.isReadable()) {
                      update(() => targetChapter = value ?? targetChapter);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.mockMaterialPreparationCacheOptions,
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _PreparationChoice(
                  selected: analysisChecked,
                  title: l10n.mockMaterialAiExplanation,
                  description: l10n.mockMaterialAiExplanationDescription,
                  onChanged: (value) {
                    if (mounted && access.isReadable()) update(() => analysisChecked = value);
                  },
                ),
                const SizedBox(height: 8),
                _PreparationChoice(
                  selected: audioChecked,
                  title: l10n.mockMaterialSentenceAudio,
                  description: l10n.mockMaterialSentenceAudioDescription,
                  onChanged: (value) {
                    if (mounted && access.isReadable()) update(() => audioChecked = value);
                  },
                ),
                const SizedBox(height: 20),
                _PreparationProgress(
                  title: l10n.mockMaterialAiExplanation,
                  ready: analysisReady,
                  scheme: scheme,
                ),
                const SizedBox(height: 16),
                _PreparationProgress(
                  title: l10n.mockMaterialSentenceAudio,
                  ready: audioReady,
                  scheme: scheme,
                ),
                if (!preparing && (analysisReady > 0 || audioReady > 0)) ...[
                  const SizedBox(height: 16),
                  Text(
                    (analysisChecked || audioChecked) &&
                            (!analysisChecked || analysisReady == 5) &&
                            (!audioChecked || audioReady == 5)
                        ? l10n.mockMaterialPreparationComplete
                        : l10n.mockMaterialPreparationPaused,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            preparing ||
                                (!analysisChecked && !audioChecked) ||
                                ((!analysisChecked || analysisReady == 5) &&
                                    (!audioChecked || audioReady == 5))
                            ? null
                            : () {
                                if (!mounted || !access.isReadable()) return;
                                final runningChapter = targetChapter;
                                final useAnalysis = analysisChecked;
                                final useAudio = audioChecked;
                                preparationTimer?.cancel();
                                setState(() => preparing = true);
                                update(() {});
                                preparationTimer = Timer.periodic(
                                  const Duration(milliseconds: 550),
                                  (timer) {
                                    if (!mounted || !access.isReadable()) {
                                      timer.cancel();
                                      return;
                                    }
                                    setState(() {
                                      if (useAnalysis &&
                                          (analysisReadyByChapter[runningChapter] ?? 0) < 5) {
                                        analysisReadyByChapter[runningChapter] =
                                            (analysisReadyByChapter[runningChapter] ?? 0) + 1;
                                      }
                                      if (useAudio &&
                                          (audioReadyByChapter[runningChapter] ?? 0) < 5) {
                                        audioReadyByChapter[runningChapter] =
                                            (audioReadyByChapter[runningChapter] ?? 0) + 1;
                                      }
                                      if ((!useAnalysis ||
                                              (analysisReadyByChapter[runningChapter] ?? 0) == 5) &&
                                          (!useAudio ||
                                              (audioReadyByChapter[runningChapter] ?? 0) == 5)) {
                                        preparing = false;
                                        timer.cancel();
                                      }
                                    });
                                    refreshSheet?.call(() {});
                                  },
                                );
                              },
                        child: Text(
                          analysisReady > 0 || audioReady > 0
                              ? l10n.mockMaterialContinuePreparation
                              : l10n.mockMaterialStartPreparation,
                        ),
                      ),
                    ),
                    if (preparing) ...[
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () {
                          if (!mounted || !access.isReadable()) return;
                          preparationTimer?.cancel();
                          setState(() => preparing = false);
                          update(() {});
                        },
                        child: Text(l10n.mockMaterialPausePreparation),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width < 760) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        sheetAnimationStyle: HarukaMotion.sheetStyle(
          context,
          reducedMotion: PreviewStoreScope.of(context).reducedMotion,
        ),
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) =>
            access.gate((context) => StatefulBuilder(builder: content), heightFraction: .88),
      );
    } else {
      await showHarukaDialog<void>(
        context: context,
        animationStyle: HarukaMotion.dialogStyle(
          context,
          reducedMotion: PreviewStoreScope.of(context).reducedMotion,
        ),
        builder: (dialogContext) => access.gate(
          (context) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: StatefulBuilder(builder: content),
            ),
          ),
          heightFraction: .6,
        ),
      );
    }
    refreshSheet = null;
  }

  @override
  Widget build(BuildContext context) {
    widget.location.chapter = chapter;
    widget.location.selectedSentence = selectedSentence;
    if (widget.location.restoreSentenceSheet) _restoreSentenceSheet();
    final playback = playbackVisible
        ? NovelPlaybackSnapshot(
            sentence: _mockNovelSentences(context)[playbackSentence],
            position: playbackSentence + 1,
            total: _mockNovelSentences(context).length,
            progress: playbackProgress,
            continuous: playbackContinuous,
            paused: playbackPaused,
            finished: playbackFinished,
            speed: playbackSpeed,
          )
        : null;
    final selectionWords = selectedRangeSentence == null
        ? const <String>[]
        : tokensFor(context, selectedRangeSentence!);
    return PreviewPageFrame(
      location: AppRoutes.mockMaterialPath(widget.item.id),
      title: widget.item.title,
      detail: true,
      detailNotifications: false,
      mobileBackground: Theme.of(context).colorScheme.surface,
      mobile: MobileNovelView(
        item: widget.item,
        chapter: chapter,
        analysis: analysis,
        analysisReady: analysisReadyByChapter[chapter] ?? 0,
        audioReady: audioReadyByChapter[chapter] ?? 0,
        bookmark: bookmark,
        playing: playing,
        playback: playback,
        selectedRangeSentence: selectedRangeSentence,
        nativeSelectionText: selectedNativeSelection?.text,
        selectedTokens: selectedTokens,
        selectionWords: selectionWords,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        fontSize: fontSize,
        onMode: (value) => setState(() => analysis = value),
        onSentence: (index) => selectSentence(index, mobile: true),
        onLongSentence: selectRange,
        onKeyboardSentence: selectRangeFromKeyboard,
        onToken: toggleToken,
        onRangeStart: changeRangeStart,
        onRangeEnd: changeRangeEnd,
        onQuerySelection: () => querySelection(mobile: true),
        onReadSelection: () => startPlayback(continuous: false, sentence: selectedRangeSentence),
        onCloseSelection: () => setState(() {
          selectedRangeSentence = null;
          selectedNativeSelection = null;
        }),
        onPrepare: prepareChapter,
        onChapter: (value) {
          playbackTimer?.cancel();
          setState(() {
            chapter = value;
            selectedRangeSentence = null;
            selectedNativeSelection = null;
            selectedSentence = null;
            playbackVisible = false;
          });
        },
        onBookmark: () => setState(() => bookmark = !bookmark),
        onPlayback: () {
          if (playbackVisible && playbackContinuous) {
            togglePlayback();
          } else {
            startPlayback(continuous: true, sentence: selectedSentence ?? 0);
          }
        },
        onPauseResume: togglePlayback,
        onSpeed: (value) => setState(() => playbackSpeed = value),
        onStopPlayback: stopPlayback,
        onFont: (value) => setState(() => fontSize = value),
      ),
      desktop: DesktopNovelView(
        item: widget.item,
        chapter: chapter,
        analysis: analysis,
        analysisReady: analysisReadyByChapter[chapter] ?? 0,
        audioReady: audioReadyByChapter[chapter] ?? 0,
        selectedSentence: selectedSentence,
        bookmark: bookmark,
        playing: playing,
        playback: playback,
        selectedRangeSentence: selectedRangeSentence,
        nativeSelectionText: selectedNativeSelection?.text,
        selectedTokens: selectedTokens,
        selectionWords: selectionWords,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        selectedQueryText: selectedQueryText,
        selectedQueryCard: selectedQueryCard,
        onSaveQueryCard: (card) {
          final access = selectedQueryAccess;
          if (access != null) _saveQueryCard(card, access);
        },
        fontSize: fontSize,
        onMode: (value) => setState(() => analysis = value),
        onSentence: selectSentence,
        onQuerySentence: (index) => unawaited(_querySentence(index)),
        onLongSentence: selectRange,
        onKeyboardSentence: selectRangeFromKeyboard,
        onToken: toggleToken,
        onRangeStart: changeRangeStart,
        onRangeEnd: changeRangeEnd,
        onQuerySelection: () => querySelection(mobile: false),
        onReadSelection: () => startPlayback(continuous: false, sentence: selectedRangeSentence),
        onCloseSelection: () => setState(() {
          selectedRangeSentence = null;
          selectedNativeSelection = null;
        }),
        onCloseSentence: () => setState(() => selectedSentence = null),
        onPrepare: prepareChapter,
        onChapter: (value) {
          playbackTimer?.cancel();
          setState(() {
            chapter = value;
            selectedRangeSentence = null;
            selectedNativeSelection = null;
            selectedSentence = null;
            selectedQueryText = null;
            playbackVisible = false;
          });
        },
        onBookmark: () => setState(() => bookmark = !bookmark),
        onPlayback: () {
          if (playbackVisible && playbackContinuous) {
            togglePlayback();
          } else {
            startPlayback(continuous: true, sentence: selectedSentence ?? 0);
          }
        },
        onPauseResume: togglePlayback,
        onSpeed: (value) => setState(() => playbackSpeed = value),
        onStopPlayback: stopPlayback,
        onFont: (value) => setState(() => fontSize = value),
      ),
    );
  }
}

class _PreparationChoice extends StatelessWidget {
  const _PreparationChoice({
    required this.selected,
    required this.title,
    required this.description,
    required this.onChanged,
  });

  final bool selected;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Material(
      color: selected ? roles.selected : scheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? scheme.primary : scheme.outline.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title),
        subtitle: Text(description),
      ),
    );
  }
}

class _PreparationProgress extends StatelessWidget {
  const _PreparationProgress({required this.title, required this.ready, required this.scheme});

  final String title;
  final int ready;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              l10n.mockMaterialPreparationReadyCount(ready, 5),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 9),
        LinearProgressIndicator(
          value: ready / 5,
          minHeight: 3,
          color: scheme.primary,
          backgroundColor: scheme.outline.withValues(alpha: .65),
        ),
        const SizedBox(height: 7),
        Text(
          l10n.mockMaterialPreparationPreparedCount(ready, 5),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

class _ReadingModeSelector extends StatelessWidget {
  const _ReadingModeSelector({required this.analysis, required this.onMode});

  final bool analysis;
  final ValueChanged<bool> onMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: roles.canvas, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in [false, true])
            TextButton(
              onPressed: () => onMode(choice),
              style: TextButton.styleFrom(
                foregroundColor: analysis == choice ? scheme.primary : scheme.onSurfaceVariant,
                backgroundColor: analysis == choice ? scheme.surface : roles.canvas,
                minimumSize: const Size(61, 37),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              child: Text(choice ? l10n.mockMaterialAnalysisMode : l10n.mockMaterialReadingMode),
            ),
        ],
      ),
    );
  }
}

class MobileNovelView extends StatelessWidget {
  const MobileNovelView({
    required this.item,
    required this.chapter,
    required this.analysis,
    required this.analysisReady,
    required this.audioReady,
    required this.bookmark,
    required this.playing,
    required this.playback,
    required this.selectedRangeSentence,
    required this.nativeSelectionText,
    required this.selectedTokens,
    required this.selectionWords,
    required this.rangeStart,
    required this.rangeEnd,
    required this.fontSize,
    required this.onMode,
    required this.onSentence,
    required this.onLongSentence,
    required this.onKeyboardSentence,
    required this.onToken,
    required this.onRangeStart,
    required this.onRangeEnd,
    required this.onQuerySelection,
    required this.onReadSelection,
    required this.onCloseSelection,
    required this.onPrepare,
    required this.onChapter,
    required this.onBookmark,
    required this.onPlayback,
    required this.onPauseResume,
    required this.onSpeed,
    required this.onStopPlayback,
    required this.onFont,
    this.publishedData,
    super.key,
  });
  MobileNovelView.published({required PublishedNovelViewData data, super.key})
    : publishedData = data,
      item = null,
      chapter = 0,
      analysis = false,
      analysisReady = 0,
      audioReady = 0,
      bookmark = false,
      playing = false,
      playback = null,
      selectedRangeSentence = data.selectedIndex,
      nativeSelectionText = data.selectedText,
      selectedTokens = const {},
      selectionWords = const [],
      rangeStart = 0,
      rangeEnd = 0,
      fontSize = data.fontSize,
      onMode = _unusedBool,
      onSentence = _unusedInt,
      onLongSentence = data.onWholeBlock,
      onKeyboardSentence = data.onNativeSelection,
      onToken = _unusedInt,
      onRangeStart = _unusedInt,
      onRangeEnd = _unusedInt,
      onQuerySelection = data.onQuery,
      onReadSelection = null,
      onCloseSelection = data.onClear,
      onPrepare = _unused,
      onChapter = _unusedInt,
      onBookmark = _unused,
      onPlayback = _unused,
      onPauseResume = _unused,
      onSpeed = _unusedDouble,
      onStopPlayback = _unused,
      onFont = data.onFont;
  final MaterialSummary? item;
  final PublishedNovelViewData? publishedData;
  final int chapter;
  final bool analysis;
  final int analysisReady;
  final int audioReady;
  final bool bookmark;
  final bool playing;
  final NovelPlaybackSnapshot? playback;
  final int? selectedRangeSentence;
  final String? nativeSelectionText;
  final Set<int> selectedTokens;
  final List<String> selectionWords;
  final int rangeStart;
  final int rangeEnd;
  final double fontSize;
  final ValueChanged<bool> onMode;
  final ValueChanged<int> onSentence;
  final ValueChanged<int> onLongSentence;
  final NovelKeyboardSelectionCallback onKeyboardSentence;
  final ValueChanged<int> onToken;
  final ValueChanged<int> onRangeStart;
  final ValueChanged<int> onRangeEnd;
  final VoidCallback onQuerySelection;
  final VoidCallback? onReadSelection;
  final VoidCallback onCloseSelection;
  final VoidCallback onPrepare;
  final ValueChanged<int> onChapter;
  final VoidCallback onBookmark;
  final VoidCallback onPlayback;
  final VoidCallback onPauseResume;
  final ValueChanged<double> onSpeed;
  final VoidCallback onStopPlayback;
  final ValueChanged<double> onFont;

  @override
  Widget build(BuildContext context) {
    final published = publishedData;
    final item = this.item;
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final sentences =
        published?.blocks.map((block) => block.text).toList() ?? _mockNovelSentences(context);
    final chapters = published == null ? _mockChapters(context) : [published.chapter.title];
    final currentChapter = published == null ? chapter : 0;
    Widget selectionToolbar() => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: NovelSelectionToolbar(
        compact: true,
        showTokenControls: published == null,
        nativeSelectionText: nativeSelectionText,
        tokens: selectionWords,
        selectedTokens: selectedTokens,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        onToken: onToken,
        onStart: onRangeStart,
        onEnd: onRangeEnd,
        onRead: onReadSelection,
        onQuery: onQuerySelection,
        onClose: onCloseSelection,
        queryTestId: published == null ? null : UiTestIds.referenceQuery,
      ),
    );
    Widget readingParagraph(int start) {
      final content = NovelReadingParagraph(
        first: sentences[start],
        second: published == null && start + 1 < sentences.length ? sentences[start + 1] : null,
        firstIndex: start,
        fontSize: fontSize,
        lineHeight: 1.8,
        highlightedIndex: playback?.position == null ? null : playback!.position - 1,
        selectedIndex: selectedRangeSentence,
        onLongSentence: onLongSentence,
        onKeyboardSentence: onKeyboardSentence,
        onNativeSelectionChanged: published == null ? null : onKeyboardSentence,
        nativeSelectionOnly: published != null,
      );
      return published == null
          ? content
          : Identified(id: UiTestIds.referenceBlock(published.blocks[start].id), child: content);
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: published == null
                ? _novelScrollKey(context, item!, chapter, true)
                : PageStorageKey(
                    'published-novel:${published.openingScope}:${published.item.id}:${published.item.revisionId}:mobile',
                  ),
            padding: const EdgeInsets.fromLTRB(21, 12, 21, 25),
            children: [
              Row(
                children: [
                  if (published == null) _ReadingModeSelector(analysis: analysis, onMode: onMode),
                  const Spacer(),
                  TextButton(
                    onPressed: published == null ? onPrepare : null,
                    child: Text(AppLocalizations.of(context).mockMaterialPrepareChapter),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                analysis
                    ? AppLocalizations.of(context).mockMaterialAnalysisModeHint
                    : AppLocalizations.of(context).mockMaterialReadingModeHint,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              if (published == null)
                Text(
                  AppLocalizations.of(context)
                      .mockMaterialChapterProgress(analysisReady, audioReady, 5),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              const SizedBox(height: 26),
              if (published == null)
                Text(
                  AppLocalizations.of(context).mockMaterialChapterCountOf(chapter + 1, 12),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              const SizedBox(height: 9),
              Text(
                chapters[currentChapter],
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFamily: 'serif'),
              ),
              const SizedBox(height: 28),
              if (analysis)
                for (final sentence in sentences.asMap().entries) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: sentence.key == 0 || sentence.key == 2 ? 2 : 18,
                    ),
                    child: NovelKeyboardSentence(
                      onOpenSelection: (selection) => onKeyboardSentence(sentence.key, selection),
                      child: InkWell(
                        onTap: () => onSentence(sentence.key),
                        onLongPress: () => onLongSentence(sentence.key),
                        child: ColoredBox(
                          color: playback?.position == sentence.key + 1
                              ? roles.bookGreen.withValues(alpha: .48)
                              : selectedRangeSentence == sentence.key
                              ? roles.selected
                              : scheme.surface,
                          child: RubySentence(
                            segments: _mockNovelRubySegments(context)[sentence.key],
                            fontSize: fontSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selectedRangeSentence == sentence.key) selectionToolbar(),
                ]
              else
                for (
                  var start = 0;
                  start < sentences.length;
                  start += published == null ? 2 : 1
                ) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: readingParagraph(start),
                  ),
                  if (selectedRangeSentence == start ||
                      (published == null && selectedRangeSentence == start + 1))
                    selectionToolbar(),
                ],
              const SizedBox(height: 20),
              Divider(color: scheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Text(
                      chapters[currentChapter],
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const Spacer(),
                    if (published == null)
                      Text(
                        AppLocalizations.of(context).mockMaterialChapterFooter(chapter + 1, 12),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (playback != null && selectedRangeSentence == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: MobileNovelPlaybackPanel(
              sentence: playback!.sentence,
              position: playback!.position,
              total: playback!.total,
              progress: playback!.progress,
              continuous: playback!.continuous,
              paused: playback!.paused,
              finished: playback!.finished,
              speed: playback!.speed,
              onPauseResume: onPauseResume,
              onSpeed: onSpeed,
              onStop: onStopPlayback,
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              MobileReaderAction(
                tooltip: playing
                    ? AppLocalizations.of(context).mockMaterialPauseContinuousPlayback
                    : AppLocalizations.of(context).mockMaterialContinuousPlayback,
                onPressed: published == null ? onPlayback : null,
                icon: Icon(playing ? Icons.pause_circle_outline : Icons.play_circle_outline),
              ),
              MobileReaderAction(
                tooltip: AppLocalizations.of(context).mockMaterialContentsTooltip,
                onPressed: () {
                  if (published != null) {
                    showPublishedContents(context, published);
                    return;
                  }
                  final access = _NovelSheetAccess.capture(context, item!);
                  unawaited(
                    showModalBottomSheet<void>(
                      context: context,
                      useRootNavigator: true,
                      sheetAnimationStyle: HarukaMotion.sheetStyle(
                        context,
                        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
                      ),
                      builder: (sheetContext) => access.gate(
                        (sheetContext) => ListView(
                          shrinkWrap: true,
                          children: [
                            for (var i = 0; i < _mockChapters(sheetContext).length; i++)
                              ListTile(
                                title: Text(
                                  AppLocalizations.of(
                                    sheetContext,
                                  ).mockMaterialChapterTitle(i + 1, _mockChapters(sheetContext)[i]),
                                ),
                                onTap: () {
                                  if (!context.mounted || !access.isReadable()) return;
                                  onChapter(i);
                                  Navigator.pop(sheetContext);
                                },
                              ),
                          ],
                        ),
                        heightFraction: .6,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt_outlined),
              ),
              MobileReaderAction(
                tooltip: AppLocalizations.of(context).mockMaterialTypographyTooltip,
                onPressed: () {
                  if (published != null) {
                    showPublishedFont(context, published);
                    return;
                  }
                  final access = _NovelSheetAccess.capture(context, item!);
                  var selectedSize = fontSize;
                  unawaited(
                    showModalBottomSheet<void>(
                      context: context,
                      useRootNavigator: true,
                      sheetAnimationStyle: HarukaMotion.sheetStyle(
                        context,
                        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
                      ),
                      showDragHandle: true,
                      builder: (sheetContext) => access.gate(
                        (sheetContext) => StatefulBuilder(
                          builder: (sheetContext, update) => Padding(
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                            child: ReaderFontControl(
                              value: selectedSize,
                              preview: item.title,
                              onChanged: (value) {
                                if (!context.mounted || !access.isReadable()) return;
                                update(() => selectedSize = value);
                                onFont(value);
                              },
                            ),
                          ),
                        ),
                        heightFraction: .3,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.text_fields),
              ),
              MobileReaderAction(
                tooltip: bookmark
                    ? AppLocalizations.of(context).mockMaterialRemoveBookmark
                    : AppLocalizations.of(context).mockMaterialAddBookmark,
                label: AppLocalizations.of(context).mockMaterialBookmarkLabel,
                onPressed: published == null ? onBookmark : null,
                icon: Icon(bookmark ? Icons.bookmark : Icons.bookmark_border),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReaderFontControl extends StatelessWidget {
  const ReaderFontControl({
    required this.value,
    required this.preview,
    required this.onChanged,
    super.key,
  });

  final double value;
  final String preview;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).mockMaterialReadingFontSize,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${value.round()}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(value: value, min: 14, max: 24, divisions: 10, onChanged: onChanged),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: HarukaColors.of(context).canvas,
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: value, height: 1.4, fontFamily: 'serif'),
          ),
        ),
      ],
    );
  }
}

class MobileReaderAction extends StatelessWidget {
  const MobileReaderAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.label,
    super.key,
  });

  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(vertical: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: Theme.of(context).colorScheme.primary),
            child: icon,
          ),
          const SizedBox(height: 2),
          Text(
            label ?? tooltip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class DesktopReaderAction extends StatelessWidget {
  const DesktopReaderAction({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    ),
  );
}

class DesktopNovelView extends StatelessWidget {
  const DesktopNovelView({
    required this.item,
    required this.chapter,
    required this.analysis,
    required this.analysisReady,
    required this.audioReady,
    required this.selectedSentence,
    required this.bookmark,
    required this.playing,
    required this.playback,
    required this.selectedRangeSentence,
    required this.nativeSelectionText,
    required this.selectedTokens,
    required this.selectionWords,
    required this.rangeStart,
    required this.rangeEnd,
    required this.selectedQueryText,
    required this.selectedQueryCard,
    required this.onSaveQueryCard,
    required this.fontSize,
    required this.onMode,
    required this.onSentence,
    required this.onQuerySentence,
    required this.onLongSentence,
    required this.onKeyboardSentence,
    required this.onToken,
    required this.onRangeStart,
    required this.onRangeEnd,
    required this.onQuerySelection,
    required this.onReadSelection,
    required this.onCloseSelection,
    required this.onCloseSentence,
    required this.onPrepare,
    required this.onChapter,
    required this.onBookmark,
    required this.onPlayback,
    required this.onPauseResume,
    required this.onSpeed,
    required this.onStopPlayback,
    required this.onFont,
    this.publishedData,
    super.key,
  });
  DesktopNovelView.published({required PublishedNovelViewData data, super.key})
    : publishedData = data,
      item = null,
      chapter = 0,
      analysis = false,
      analysisReady = 0,
      audioReady = 0,
      selectedSentence = data.selectedIndex,
      bookmark = false,
      playing = false,
      playback = null,
      selectedRangeSentence = data.selectedIndex,
      nativeSelectionText = data.selectedText,
      selectedTokens = const {},
      selectionWords = const [],
      rangeStart = 0,
      rangeEnd = 0,
      selectedQueryText = null,
      selectedQueryCard = null,
      onSaveQueryCard = _unusedCard,
      fontSize = data.fontSize,
      onMode = _unusedBool,
      onSentence = _unusedInt,
      onQuerySentence = _unusedInt,
      onLongSentence = data.onWholeBlock,
      onKeyboardSentence = data.onNativeSelection,
      onToken = _unusedInt,
      onRangeStart = _unusedInt,
      onRangeEnd = _unusedInt,
      onQuerySelection = data.onQuery,
      onReadSelection = null,
      onCloseSelection = data.onClear,
      onCloseSentence = data.onClear,
      onPrepare = _unused,
      onChapter = _unusedInt,
      onBookmark = _unused,
      onPlayback = _unused,
      onPauseResume = _unused,
      onSpeed = _unusedDouble,
      onStopPlayback = _unused,
      onFont = data.onFont;
  final MaterialSummary? item;
  final PublishedNovelViewData? publishedData;
  final int chapter;
  final bool analysis;
  final int analysisReady;
  final int audioReady;
  final int? selectedSentence;
  final bool bookmark;
  final bool playing;
  final NovelPlaybackSnapshot? playback;
  final int? selectedRangeSentence;
  final String? nativeSelectionText;
  final Set<int> selectedTokens;
  final List<String> selectionWords;
  final int rangeStart;
  final int rangeEnd;
  final String? selectedQueryText;
  final LearningCard? selectedQueryCard;
  final ValueChanged<LearningCard> onSaveQueryCard;
  final double fontSize;
  final ValueChanged<bool> onMode;
  final ValueChanged<int> onSentence;
  final ValueChanged<int> onQuerySentence;
  final ValueChanged<int> onLongSentence;
  final NovelKeyboardSelectionCallback onKeyboardSentence;
  final ValueChanged<int> onToken;
  final ValueChanged<int> onRangeStart;
  final ValueChanged<int> onRangeEnd;
  final VoidCallback onQuerySelection;
  final VoidCallback? onReadSelection;
  final VoidCallback onCloseSelection;
  final VoidCallback onCloseSentence;
  final VoidCallback onPrepare;
  final ValueChanged<int> onChapter;
  final VoidCallback onBookmark;
  final VoidCallback onPlayback;
  final VoidCallback onPauseResume;
  final ValueChanged<double> onSpeed;
  final VoidCallback onStopPlayback;
  final ValueChanged<double> onFont;

  @override
  Widget build(BuildContext context) {
    final published = publishedData;
    final item = this.item;
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final sentences =
        published?.blocks.map((block) => block.text).toList() ?? _mockNovelSentences(context);
    final chapters = published == null ? _mockChapters(context) : [published.chapter.title];
    final currentChapter = published == null ? chapter : 0;
    final title = published?.item.title ?? item!.title;
    final access = published == null ? _NovelSheetAccess.capture(context, item!) : null;
    Widget selectionToolbar() => NovelSelectionToolbar(
      compact: false,
      showTokenControls: published == null,
      queryTestId: published == null ? null : UiTestIds.referenceQuery,
      nativeSelectionText: nativeSelectionText,
      tokens: selectionWords,
      selectedTokens: selectedTokens,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      onToken: onToken,
      onStart: onRangeStart,
      onEnd: onRangeEnd,
      onRead: onReadSelection,
      onQuery: onQuerySelection,
      onClose: onCloseSelection,
    );
    Widget readingParagraph(int start) {
      final content = NovelReadingParagraph(
        first: sentences[start],
        second: published == null && start + 1 < sentences.length ? sentences[start + 1] : null,
        firstIndex: start,
        fontSize: fontSize,
        lineHeight: 1.9,
        highlightedIndex: playback?.position == null ? null : playback!.position - 1,
        selectedIndex: selectedRangeSentence,
        onLongSentence: onLongSentence,
        onKeyboardSentence: onKeyboardSentence,
        onNativeSelectionChanged: published == null ? null : onKeyboardSentence,
        nativeSelectionOnly: published != null,
      );
      return published == null
          ? content
          : Identified(id: UiTestIds.referenceBlock(published.blocks[start].id), child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: published == null
                        ? _novelScrollKey(context, item!, chapter, false)
                        : PageStorageKey(
                            'published-novel:${published.openingScope}:${published.item.id}:${published.item.revisionId}:desktop',
                          ),
                    children: [
                      Row(
                        children: [
                          Text(title, style: Theme.of(context).textTheme.headlineMedium),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: published == null ? onPlayback : null,
                            icon: Icon(playing ? Icons.pause_outlined : Icons.headphones_outlined),
                            label: Text(
                              playing
                                  ? AppLocalizations.of(context).mockMaterialPauseContinuousPlayback
                                  : AppLocalizations.of(context).mockMaterialContinuousPlayback,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (published != null)
                            TextButton.icon(
                              onPressed: () => showPublishedContents(context, published),
                              icon: const Icon(Icons.library_books_outlined),
                              label: Text(AppLocalizations.of(context).mockMaterialContentsTooltip),
                            )
                          else
                            PopupMenuButton<int>(
                              useRootNavigator: true,
                              tooltip: AppLocalizations.of(context).mockMaterialContentsTooltip,
                              onSelected: (chapterIndex) {
                                if (context.mounted && access!.isReadable(context)) {
                                  onChapter(chapterIndex);
                                }
                              },
                              itemBuilder: (menuContext) => [
                                for (var i = 0; i < chapters.length; i++)
                                  PopupMenuItem(
                                    value: i,
                                    child: access!.gate(
                                      (menuContext) => Text(
                                        AppLocalizations.of(menuContext)
                                            .mockMaterialChapterTitle(i + 1, chapters[i]),
                                      ),
                                    ),
                                  ),
                              ],
                              child: DesktopReaderAction(
                                icon: Icons.library_books_outlined,
                                label: AppLocalizations.of(context).mockMaterialContentsTooltip,
                              ),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: AppLocalizations.of(context).mockMaterialTypographyTooltip,
                            onPressed: () {
                              if (published != null) {
                                showPublishedFont(context, published);
                                return;
                              }
                              var selectedSize = fontSize;
                              unawaited(
                                showHarukaDialog<void>(
                                  context: context,
                                  animationStyle: HarukaMotion.dialogStyle(
                                    context,
                                    reducedMotion: PreviewStoreScope.of(context).reducedMotion,
                                  ),
                                  builder: (dialogContext) => access!.gate(
                                    (dialogContext) => HarukaDialogSurface(
                                      title: AppLocalizations.of(dialogContext)
                                          .mockMaterialReadingFontSize,
                                      size: HarukaDialogSize.compact,
                                      child: StatefulBuilder(
                                        builder: (dialogContext, update) => ReaderFontControl(
                                          value: selectedSize,
                                          preview: title,
                                          onChanged: (value) {
                                            if (!context.mounted || !access.isReadable()) return;
                                            update(() => selectedSize = value);
                                            onFont(value);
                                          },
                                        ),
                                      ),
                                    ),
                                    heightFraction: .3,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.text_fields),
                          ),
                          IconButton(
                            tooltip: bookmark
                                ? AppLocalizations.of(context).mockMaterialRemoveBookmark
                                : AppLocalizations.of(context).mockMaterialAddBookmark,
                            onPressed: published == null ? onBookmark : null,
                            icon: Icon(bookmark ? Icons.bookmark : Icons.bookmark_border),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (published == null)
                            _ReadingModeSelector(analysis: analysis, onMode: onMode),
                          const SizedBox(width: 12),
                          const Spacer(),
                          TextButton(
                            onPressed: published == null ? onPrepare : null,
                            child: Text(AppLocalizations.of(context).mockMaterialPrepareChapter),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        analysis
                            ? AppLocalizations.of(context).mockMaterialAnalysisModeHint
                            : AppLocalizations.of(context).mockMaterialReadingModeHint,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      if (published == null)
                        Text(
                          AppLocalizations.of(context)
                              .mockMaterialChapterProgress(analysisReady, audioReady, 5),
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) => HarukaSurface(
                          padding: EdgeInsets.fromLTRB(
                            ((constraints.maxWidth - 720) / 2).clamp(36.0, double.infinity),
                            36,
                            ((constraints.maxWidth - 720) / 2).clamp(36.0, double.infinity),
                            30,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (published == null)
                                Text(
                                  AppLocalizations.of(context)
                                      .mockMaterialChapterCountOf(chapter + 1, 12),
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                chapters[currentChapter],
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontFamily: 'serif'),
                              ),
                              const SizedBox(height: 30),
                              if (analysis)
                                for (final sentence in sentences.asMap().entries) ...[
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: sentence.key == 0 || sentence.key == 2 ? 2 : 20,
                                    ),
                                    child: NovelSelectionAnchor(
                                      selected: selectedRangeSentence == sentence.key,
                                      toolbar: selectionToolbar(),
                                      child: NovelKeyboardSentence(
                                        onOpenSelection: (selection) =>
                                            onKeyboardSentence(sentence.key, selection),
                                        child: InkWell(
                                          onTap: () => onSentence(sentence.key),
                                          onLongPress: () => onLongSentence(sentence.key),
                                          child: ColoredBox(
                                            color: playback?.position == sentence.key + 1
                                                ? roles.bookGreen.withValues(alpha: .48)
                                                : selectedRangeSentence == sentence.key
                                                ? roles.selected
                                                : selectedSentence == sentence.key
                                                ? roles.selected
                                                : scheme.surface,
                                            child: RubySentence(
                                              segments: _mockNovelRubySegments(
                                                context,
                                              )[sentence.key],
                                              fontSize: fontSize,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                              else
                                for (
                                  var start = 0;
                                  start < sentences.length;
                                  start += published == null ? 2 : 1
                                ) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 28),
                                    child: NovelSelectionAnchor(
                                      selected:
                                          selectedRangeSentence == start ||
                                          (published == null && selectedRangeSentence == start + 1),
                                      toolbar: selectionToolbar(),
                                      child: readingParagraph(start),
                                    ),
                                  ),
                                ],
                              const SizedBox(height: 26),
                              Divider(color: scheme.outlineVariant),
                              Row(
                                children: [
                                  Text(
                                    chapters[currentChapter],
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                  const Spacer(),
                                  if (published == null)
                                    Text(
                                      AppLocalizations.of(context)
                                          .mockMaterialChapterFooter(chapter + 1, 12),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (playback != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DesktopNovelPlaybackPanel(
                      sentence: playback!.sentence,
                      position: playback!.position,
                      total: playback!.total,
                      progress: playback!.progress,
                      continuous: playback!.continuous,
                      paused: playback!.paused,
                      finished: playback!.finished,
                      speed: playback!.speed,
                      onPauseResume: onPauseResume,
                      onSpeed: onSpeed,
                      onStop: onStopPlayback,
                    ),
                  ),
              ],
            ),
          ),
          if (selectedQueryText != null) ...[
            const SizedBox(width: 18),
            SizedBox(
              width: 320,
              child: HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppLocalizations.of(context).mockMaterialNovelQueryResultTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    NovelSelectionResultBody(
                      selectedText: selectedQueryText!,
                      source: AppLocalizations.of(context)
                          .mockMaterialSentenceSource(title, chapter + 1, chapters[currentChapter]),
                      card: selectedQueryCard,
                      onSave: () {
                        final card = selectedQueryCard;
                        if (card != null && access!.isReadable()) onSaveQueryCard(card);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (selectedSentence != null) ...[
            const SizedBox(width: 18),
            SizedBox(
              width: 286,
              child: HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context).mockMaterialSentenceAnalysisTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(onPressed: onCloseSentence, icon: const Icon(Icons.close)),
                      ],
                    ),
                    if (published == null)
                      Text(
                        AppLocalizations.of(context)
                            .mockMaterialSentencePosition(selectedSentence! + 1, 5),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    if (published == null)
                      Row(
                        children: [
                          TextButton(
                            onPressed: selectedSentence == 0
                                ? null
                                : () => onSentence(selectedSentence! - 1),
                            child: Text(AppLocalizations.of(context).mockMaterialPreviousSentence),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: selectedSentence == 4
                                ? null
                                : () => onSentence(selectedSentence! + 1),
                            child: Text(AppLocalizations.of(context).mockMaterialNextSentence),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Text(
                      sentences[selectedSentence!],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 15),
                    if (published == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: roles.selected,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context).mockMaterialTranslation,
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            const SizedBox(height: 5),
                            Text(_mockNovelTranslations(context)[selectedSentence!]),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (published == null)
                      OutlinedButton.icon(
                        onPressed:
                            _isSentenceCollected(
                              context,
                              _mockNovelSentences(context)[selectedSentence!],
                            )
                            ? null
                            : () => _collectSentence(context, item!, selectedSentence!),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(
                          _isSentenceCollected(
                                context,
                                _mockNovelSentences(context)[selectedSentence!],
                              )
                              ? AppLocalizations.of(context).mockMaterialCollectedSentence
                              : AppLocalizations.of(context).mockMaterialCollectSentence,
                        ),
                      ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: published == null
                          ? () => onQuerySentence(selectedSentence!)
                          : published.reference.busy || !published.reference.canResolve
                          ? null
                          : published.onQuery,
                      child: Text(AppLocalizations.of(context).mockMaterialQuerySelection),
                    ),
                    if (published?.reference.error != null)
                      Text(
                        AppLocalizations.of(context).authUnavailableShort,
                        style: TextStyle(color: scheme.error),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (constraints.maxWidth >= 960 &&
              selectedQueryText == null &&
              selectedSentence == null) ...[
            const SizedBox(width: 18),
            SizedBox(
              width: 240,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight.clamp(0, 720).toDouble()
                      : 720,
                ),
                child: HarukaSurface(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          AppLocalizations.of(context).mockMaterialContentsTooltip,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        fit: FlexFit.loose,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: chapters.length,
                          itemBuilder: (context, index) => ListTile(
                            dense: true,
                            selected: index == currentChapter,
                            title: Text(
                              AppLocalizations.of(context)
                                  .mockMaterialChapterTitle(index + 1, chapters[index]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              if (published == null && access!.isReadable(context)) {
                                onChapter(index);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

bool _isSentenceCollected(BuildContext context, String sentence) =>
    PreviewStoreScope.of(context).collections
        .any((item) => item.kind == CollectionKind.sentence && item.displayText == sentence);

void _collectSentence(BuildContext context, MaterialSummary item, int index) {
  final sentence = _mockNovelSentences(context)[index];
  if (_isSentenceCollected(context, sentence)) return;
  PreviewStoreScope.of(context).addCollection(
    CollectionEntry(
      id: '77777777-7777-4777-8777-${DateTime.now().microsecondsSinceEpoch.remainder(1000000000000).toString().padLeft(12, '0')}',
      kind: CollectionKind.sentence,
      displayText: sentence,
      targetLanguage: item.language,
      meaning: _mockNovelTranslations(context)[index],
      createdAt: DateTime.now().toUtc(),
      sourceTitle: item.title,
      context: sentence,
    ),
  );
}

class SentenceDialog extends StatefulWidget {
  const SentenceDialog({required this.item, required this.chapter, required this.index, super.key});
  final MaterialSummary item;
  final int chapter;
  final int index;

  @override
  State<SentenceDialog> createState() => _SentenceDialogState();
}

class _SentenceDialogState extends State<SentenceDialog> {
  late int index = widget.index;
  bool listening = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final sentence = _mockNovelSentences(context)[index];
    final collected = _isSentenceCollected(context, sentence);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 5),
              child: Row(
                children: [
                  Text(
                    l10n.mockMaterialSentenceAnalysisTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.mockMaterialClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.mockMaterialSentencePosition(index + 1, 5),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => listening = !listening),
                        icon: Icon(listening ? Icons.pause : Icons.volume_up_outlined),
                        label: Text(
                          listening
                              ? l10n.mockMaterialPauseOriginal
                              : l10n.mockMaterialListenOriginal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: index == 0
                            ? null
                            : () => setState(() {
                                index--;
                                listening = false;
                              }),
                        child: Text(l10n.mockMaterialPreviousSentence),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: index == 4
                            ? null
                            : () => setState(() {
                                index++;
                                listening = false;
                              }),
                        child: Text(l10n.mockMaterialNextSentence),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: roles.bookGreen.withValues(alpha: .25),
                      border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mockMaterialSentenceSource(
                            widget.item.title,
                            widget.chapter + 1,
                            _mockChapters(context)[widget.chapter],
                          ),
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(sentence),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  HarukaSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(17),
                          color: roles.selected,
                          child: Text(
                            l10n.mockMaterialSentenceAnalysisTitle,
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sentence, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 20),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: roles.selected,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.mockMaterialTranslation,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _mockNovelTranslations(context)[index],
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                l10n.mockMaterialSelectionQueryHint,
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(
                                onPressed: collected
                                    ? null
                                    : () => setState(
                                        () => _collectSentence(context, widget.item, index),
                                      ),
                                icon: Icon(
                                  collected ? Icons.bookmark : Icons.bookmark_add_outlined,
                                ),
                                label: Text(
                                  collected
                                      ? l10n.mockMaterialCollectedSentence
                                      : l10n.mockMaterialCollectSentence,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, index),
                    child: Text(l10n.mockMaterialQuerySelection),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _mockTextbookUnits(BuildContext context) => [
  AppLocalizations.of(context).mockMaterialTextbookUnitFirstMeeting,
  AppLocalizations.of(context).mockMaterialTextbookUnitToStation,
  AppLocalizations.of(context).mockMaterialTextbookUnitAtCafe,
];
List<String> _mockTextbookTopics(BuildContext context, int unit) {
  final l10n = AppLocalizations.of(context);
  return switch (unit) {
    1 => [
      l10n.mockMaterialTextbookUnitTwoTopicText,
      l10n.mockMaterialTextbookUnitTwoTopicVocabulary,
      l10n.mockMaterialTextbookUnitTwoTopicGrammar,
      l10n.mockMaterialTextbookUnitTwoTopicExercise,
    ],
    2 => [
      l10n.mockMaterialTextbookUnitThreeTopicConversation,
      l10n.mockMaterialTextbookUnitThreeTopicExamples,
      l10n.mockMaterialTextbookUnitThreeTopicGrammar,
      l10n.mockMaterialTextbookUnitThreeTopicExercise,
    ],
    _ => [
      l10n.mockMaterialTextbookTopicConversation,
      l10n.mockMaterialTextbookTopicVocabulary,
      l10n.mockMaterialTextbookTopicGrammar,
      l10n.mockMaterialTextbookTopicExercise,
    ],
  };
}

IconData _textbookTopicIcon(int index) => switch (index) {
  0 => Icons.menu_book_outlined,
  1 => Icons.library_books_outlined,
  2 => Icons.auto_awesome_outlined,
  _ => Icons.edit_outlined,
};

String _textbookTopicSubtitle(AppLocalizations l10n, int index) => switch (index) {
  0 => l10n.mockMaterialTextbookConversationSubtitle,
  1 => l10n.mockMaterialTextbookVocabularySubtitle,
  2 => l10n.mockMaterialTextbookGrammarSubtitle,
  _ => l10n.mockMaterialTextbookExerciseSubtitle,
};

String _textbookTopicContent(AppLocalizations l10n, int unit, int index, {required bool mobile}) =>
    switch ((unit, index, mobile)) {
      (1, 0, _) => l10n.mockMaterialTextbookUnitTwoTextExample,
      (1, 2, true) => l10n.mockMaterialTextbookUnitTwoMobileGrammar,
      (1, 2, false) => l10n.mockMaterialTextbookUnitTwoGrammarExample,
      (2, 0, true) => l10n.mockMaterialTextbookUnitThreeMobileConversation,
      (2, 0, false) => l10n.mockMaterialTextbookUnitThreeDesktopConversation,
      (2, 2, true) => l10n.mockMaterialTextbookUnitThreeMobileGrammar,
      (2, 2, false) => l10n.mockMaterialTextbookUnitThreeDesktopGrammar,
      (_, 0, _) => l10n.mockMaterialTextbookConversationExample,
      (_, 1, _) => l10n.mockMaterialTextbookVocabularyExample,
      (_, 2, _) => l10n.mockMaterialTextbookGrammarExample,
      _ => l10n.mockMaterialTextbookExerciseHint,
    };

List<({String word, String meaning})> _textbookVocabularyEntries(AppLocalizations l10n, int unit) =>
    switch (unit) {
      1 => [
        (
          word: l10n.mockMaterialTextbookUnitTwoExampleStation,
          meaning: l10n.mockMaterialTextbookUnitTwoExampleStationMeaning,
        ),
        (
          word: l10n.mockMaterialTextbookUnitTwoExampleRight,
          meaning: l10n.mockMaterialTextbookUnitTwoExampleRightMeaning,
        ),
        (
          word: l10n.mockMaterialTextbookUnitTwoExampleLeft,
          meaning: l10n.mockMaterialTextbookUnitTwoExampleLeftMeaning,
        ),
      ],
      2 => [
        (
          word: l10n.mockMaterialTextbookUnitThreeExampleOrder,
          meaning: l10n.mockMaterialTextbookUnitThreeExampleOrderMeaning,
        ),
        (
          word: l10n.mockMaterialTextbookUnitThreeExampleWater,
          meaning: l10n.mockMaterialTextbookUnitThreeExampleWaterMeaning,
        ),
        (
          word: l10n.mockMaterialTextbookUnitThreeExampleCoffee,
          meaning: l10n.mockMaterialTextbookUnitThreeExampleCoffeeMeaning,
        ),
      ],
      _ => [],
    };

class TextbookPage extends StatefulWidget {
  const TextbookPage({required this.item, super.key});
  final MaterialSummary item;
  @override
  State<TextbookPage> createState() => _TextbookPageState();
}

class _TextbookPageState extends State<TextbookPage> {
  int unit = 0;
  String? lastRouteUnit;
  bool showMobileUnits = true;

  String get practicePath => '${AppRoutes.mockTextbookPractice}?unit=${unit + 1}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeUnit = GoRouterState.of(context).uri.queryParameters['unit'];
    if (routeUnit == lastRouteUnit) return;
    lastRouteUnit = routeUnit;
    final parsed = int.tryParse(routeUnit ?? '');
    unit = parsed != null && parsed >= 1 && parsed <= _mockTextbookUnits(context).length
        ? parsed - 1
        : 0;
    showMobileUnits = parsed == null || parsed < 1 || parsed > _mockTextbookUnits(context).length;
  }

  void openTopic(int index) {
    if (index == 3) {
      unawaited(context.push(practicePath));
      return;
    }
    final unitLabel = AppLocalizations.of(context).mockMaterialUnitTitle(
      (unit + 1).toString().padLeft(2, '0'),
      _mockTextbookUnits(context)[unit],
    );
    if (MediaQuery.sizeOf(context).width < 760) {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          sheetAnimationStyle: HarukaMotion.sheetStyle(
            context,
            reducedMotion: PreviewStoreScope.of(context).reducedMotion,
          ),
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => MobileTextbookTopicSheet(unit: unit, index: index, unitLabel: unitLabel),
        ),
      );
    } else {
      unawaited(
        showHarukaDialog<void>(
          context: context,
          animationStyle: HarukaMotion.dialogStyle(
            context,
            reducedMotion: PreviewStoreScope.of(context).reducedMotion,
          ),
          builder: (_) =>
              DesktopTextbookTopicDialog(unit: unit, index: index, unitLabel: unitLabel),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mobileDirectory = ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      children: [
        Text(l10n.mockMaterialTextbookJapaneseLabel, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(widget.item.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.mockMaterialUnitContents,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              l10n.mockMaterialTextbookAvailableUnitCount(_mockTextbookUnits(context).length),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        HarukaSurface(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            children: [
              for (var i = 0; i < _mockTextbookUnits(context).length; i++) ...[
                if (i > 0)
                  Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: HarukaColors.of(context).selected,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      (i + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(_mockTextbookUnits(context)[i]),
                  subtitle: Text(l10n.mockMaterialTextbookUnitSections),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => setState(() {
                    unit = i;
                    showMobileUnits = false;
                  }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final mobileContent = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
            children: [
              Text(
                AppLocalizations.of(context).mockMaterialUnitTitle(
                  (unit + 1).toString().padLeft(2, '0'),
                  _mockTextbookUnits(context)[unit],
                ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 29),
              Text(
                AppLocalizations.of(context).mockMaterialUnitContentTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              HarukaSurface(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < _mockTextbookTopics(context, unit).length;
                      index++
                    ) ...[
                      if (index > 0)
                        Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: HarukaColors.of(context).selected,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _textbookTopicIcon(index),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(_mockTextbookTopics(context, unit)[index]),
                        subtitle: Text(_textbookTopicSubtitle(AppLocalizations.of(context), index)),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => openTopic(index),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
            ),
          ),
          child: FilledButton(
            onPressed: () => unawaited(context.push(practicePath)),
            child: Text(AppLocalizations.of(context).mockMaterialDoUnitExercises),
          ),
        ),
      ],
    );
    final desktop = ListView(
      children: [
        Text(widget.item.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 25),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 190,
              child: HarukaSurface(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    for (var i = 0; i < _mockTextbookUnits(context).length; i++)
                      TextButton(
                        onPressed: () => setState(() => unit = i),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size(double.infinity, 43),
                          backgroundColor: unit == i ? HarukaColors.of(context).selected : null,
                          foregroundColor: unit == i
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: Text(
                          AppLocalizations.of(context).mockMaterialNumberedTitle(
                            (i + 1).toString().padLeft(2, '0'),
                            _mockTextbookUnits(context)[i],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: HarukaSurface(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).mockMaterialUnitTitle(
                              (unit + 1).toString().padLeft(2, '0'),
                              _mockTextbookUnits(context)[unit],
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        FilledButton(
                          onPressed: () => context.push(practicePath),
                          child: Text(AppLocalizations.of(context).mockMaterialDoUnitExercises),
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    for (
                      var index = 0;
                      index < _mockTextbookTopics(context, unit).length;
                      index++
                    ) ...[
                      if (index > 0)
                        Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: .2)),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        leading: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: HarukaColors.of(context).selected,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _textbookTopicIcon(index),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(_mockTextbookTopics(context, unit)[index]),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openTopic(index),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final returnToMobileUnits = MediaQuery.sizeOf(context).width < 760 && !showMobileUnits;
    return PopScope(
      canPop: !returnToMobileUnits,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && returnToMobileUnits) setState(() => showMobileUnits = true);
      },
      child: PreviewPageFrame(
        location: AppRoutes.mockMaterialPath(widget.item.id),
        title: l10n.mockMaterialUnitContentTitle,
        detail: true,
        detailNotifications: false,
        mobileHeader: Row(
          children: [
            IconButton(
              tooltip: l10n.mockShellBack,
              onPressed: () {
                if (!showMobileUnits) {
                  setState(() => showMobileUnits = true);
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.mockLibrary);
                }
              },
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
            ),
            Expanded(
              child: Text(
                showMobileUnits
                    ? l10n.mockMaterialTextbookTitle
                    : l10n.mockMaterialUnitContentTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        mobile: showMobileUnits ? mobileDirectory : mobileContent,
        desktop: desktop,
      ),
    );
  }
}

class MobileTextbookTopicSheet extends StatefulWidget {
  const MobileTextbookTopicSheet({
    required this.unit,
    required this.index,
    required this.unitLabel,
    super.key,
  });

  final int unit;
  final int index;
  final String unitLabel;

  @override
  State<MobileTextbookTopicSheet> createState() => _MobileTextbookTopicSheetState();
}

class _MobileTextbookTopicSheetState extends State<MobileTextbookTopicSheet> {
  String? activeWord;
  int playbackSequence = 0;
  int get unit => widget.unit;
  int get index => widget.index;
  String get unitLabel => widget.unitLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final vocabulary = _textbookVocabularyEntries(l10n, unit);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _mockTextbookTopics(context, unit)[index],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.mockMaterialClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if ((unit == 1 || unit == 2) && index == 1)
                TextbookVocabularyWord(
                  word: vocabulary.first.word,
                  meaning: vocabulary.first.meaning,
                  onRead: () => setState(() {
                    activeWord = vocabulary.first.word;
                    playbackSequence++;
                  }),
                )
              else
                for (final line in _textbookTopicContent(
                  l10n,
                  unit,
                  index,
                  mobile: true,
                ).split('\n')) ...[
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: line.contains(RegExp(r'[\u3040-\u30ff\u4e00-\u9faf]')) ? 18 : 15,
                      height: 1.9,
                      fontFamily: 'serif',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HarukaColors.of(context).selected,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.mockMaterialTextbookSource(unitLabel),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.mockMaterialTextbookBackToUnit),
              ),
              if (activeWord != null) ...[
                const SizedBox(height: 16),
                TextbookPlaybackPanel(
                  key: ValueKey('$activeWord-$playbackSequence'),
                  word: activeWord!,
                  onStop: () => setState(() => activeWord = null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopTextbookTopicDialog extends StatefulWidget {
  const DesktopTextbookTopicDialog({
    required this.unit,
    required this.index,
    required this.unitLabel,
    super.key,
  });

  final int unit;
  final int index;
  final String unitLabel;

  @override
  State<DesktopTextbookTopicDialog> createState() => _DesktopTextbookTopicDialogState();
}

class _DesktopTextbookTopicDialogState extends State<DesktopTextbookTopicDialog> {
  String? activeWord;
  int playbackSequence = 0;
  int get unit => widget.unit;
  int get index => widget.index;
  String get unitLabel => widget.unitLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vocabulary = _textbookVocabularyEntries(l10n, unit);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _mockTextbookTopics(context, unit)[index],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.mockMaterialClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if ((unit == 1 || unit == 2) && index == 1) ...[
                for (var i = 0; i < vocabulary.length; i++) ...[
                  TextbookVocabularyWord(
                    word: vocabulary[i].word,
                    meaning: vocabulary[i].meaning,
                    onRead: () => setState(() {
                      activeWord = vocabulary[i].word;
                      playbackSequence++;
                    }),
                  ),
                  if (i < vocabulary.length - 1) const SizedBox(height: 18),
                ],
              ] else ...[
                Text(
                  unitLabel,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 25),
                Text(
                  _textbookTopicContent(l10n, unit, index, mobile: false),
                  style: const TextStyle(fontSize: 18, height: 1.7),
                ),
              ],
              if (activeWord != null) ...[
                const SizedBox(height: 20),
                TextbookPlaybackPanel(
                  key: ValueKey('$activeWord-$playbackSequence'),
                  word: activeWord!,
                  onStop: () => setState(() => activeWord = null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TextbookVocabularyWord extends StatelessWidget {
  const TextbookVocabularyWord({
    required this.word,
    required this.meaning,
    required this.onRead,
    super.key,
  });

  final String word;
  final String meaning;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(word, style: Theme.of(context).textTheme.titleSmall),
              Text(meaning, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.mockMaterialTextbookReadWord(word),
          onPressed: onRead,
          icon: const Icon(Icons.volume_up_outlined),
          color: scheme.primary,
        ),
      ],
    );
  }
}

class TextbookPlaybackPanel extends StatefulWidget {
  const TextbookPlaybackPanel({required this.word, required this.onStop, super.key});

  final String word;
  final VoidCallback onStop;

  @override
  State<TextbookPlaybackPanel> createState() => _TextbookPlaybackPanelState();
}

class _TextbookPlaybackPanelState extends State<TextbookPlaybackPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController progress;
  double speed = 1;
  bool playing = true;

  @override
  void initState() {
    super.initState();
    progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) setState(() => playing = false);
      })
      ..forward();
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }

  void togglePlayback() {
    if (progress.isCompleted) {
      progress.forward(from: 0);
      setState(() => playing = true);
    } else if (playing) {
      progress.stop();
      setState(() => playing = false);
    } else {
      progress.forward();
      setState(() => playing = true);
    }
  }

  void changeSpeed(double? value) {
    if (value == null) return;
    progress.stop();
    progress.duration = Duration(milliseconds: (4600 / value).round());
    if (playing && !progress.isCompleted) progress.forward();
    setState(() => speed = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final finished = progress.isCompleted;
    final controlLabel = finished
        ? l10n.mockMaterialTextbookPlaybackReplay
        : playing
        ? l10n.mockMaterialTextbookPlaybackPause
        : l10n.mockMaterialTextbookPlaybackResume;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outline.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.mockMaterialTextbookPlaybackTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              Text(
                finished
                    ? l10n.mockMaterialTextbookPlaybackFinished
                    : playing
                    ? l10n.mockMaterialTextbookPlaybackPlaying
                    : l10n.mockMaterialTextbookPlaybackPaused,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(widget.word),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) => LinearProgressIndicator(
              value: progress.value,
              color: scheme.primary,
              backgroundColor: scheme.primary.withValues(alpha: .12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                l10n.mockMaterialTextbookPlaybackOnce,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(l10n.mockMaterialTextbookPlaybackSpeed),
              const SizedBox(width: 6),
              DropdownButton<double>(
                value: speed,
                items: [
                  for (final rate in const [0.7, 1.0, 1.2, 1.5])
                    DropdownMenuItem(
                      value: rate,
                      child: Text(l10n.mockSettingPlaybackRate(rate.toStringAsFixed(1))),
                    ),
                ],
                onChanged: changeSpeed,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: togglePlayback,
                icon: Icon(finished || !playing ? Icons.play_arrow_outlined : Icons.pause_outlined),
                label: Text(controlLabel),
              ),
              TextButton.icon(
                onPressed: widget.onStop,
                icon: const Icon(Icons.close),
                label: Text(l10n.mockMaterialTextbookPlaybackStop),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum ExamQuestionGroup { language, reading, listening }

class ExamQuestionDraft {
  const ExamQuestionDraft({required this.number, required this.group, required this.score});

  final int number;
  final ExamQuestionGroup group;
  final double score;
}

String examQuestionGroupLabel(AppLocalizations l10n, ExamQuestionGroup group) => switch (group) {
  ExamQuestionGroup.language => l10n.mockMaterialExamGroupLanguage,
  ExamQuestionGroup.reading => l10n.mockMaterialExamGroupReading,
  ExamQuestionGroup.listening => l10n.mockMaterialExamGroupListening,
};

class MobileExamQuestionReviewSheet extends StatelessWidget {
  const MobileExamQuestionReviewSheet({required this.questions, super.key});

  final List<ExamQuestionDraft> questions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final availableHeight = (media.size.height - keyboard - media.padding.top).clamp(
      0.0,
      double.infinity,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: availableHeight * .88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ExamQuestionReviewForm(questions: questions, compact: true),
          ),
        ),
      ),
    );
  }
}

class DesktopExamQuestionReviewDialog extends StatelessWidget {
  const DesktopExamQuestionReviewDialog({required this.questions, super.key});

  final List<ExamQuestionDraft> questions;

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 740),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ExamQuestionReviewForm(questions: questions, compact: false),
      ),
    ),
  );
}

class ExamQuestionReviewForm extends StatefulWidget {
  const ExamQuestionReviewForm({required this.questions, required this.compact, super.key});

  final List<ExamQuestionDraft> questions;
  final bool compact;

  @override
  State<ExamQuestionReviewForm> createState() => _ExamQuestionReviewFormState();
}

class _ExamQuestionReviewFormState extends State<ExamQuestionReviewForm> {
  final formKey = GlobalKey<FormState>();
  bool missingListeningGroup = false;
  late final List<TextEditingController> numberControllers;
  late final List<TextEditingController> scoreControllers;
  late final List<ExamQuestionGroup> groups;

  @override
  void initState() {
    super.initState();
    numberControllers = [
      for (final question in widget.questions) TextEditingController(text: '${question.number}'),
    ];
    scoreControllers = [
      for (final question in widget.questions)
        TextEditingController(
          text: question.score == question.score.roundToDouble()
              ? '${question.score.toInt()}'
              : '${question.score}',
        ),
    ];
    groups = [for (final question in widget.questions) question.group];
  }

  @override
  void dispose() {
    for (final controller in [...numberControllers, ...scoreControllers]) {
      controller.dispose();
    }
    super.dispose();
  }

  void confirm() {
    if (!formKey.currentState!.validate()) return;
    if (!groups.contains(ExamQuestionGroup.listening)) {
      setState(() => missingListeningGroup = true);
      return;
    }
    Navigator.pop(context, [
      for (var index = 0; index < widget.questions.length; index++)
        ExamQuestionDraft(
          number: int.parse(numberControllers[index].text.trim()),
          group: groups[index],
          score: double.parse(scoreControllers[index].text.trim()),
        ),
    ]);
  }

  Widget numberField(int index, AppLocalizations l10n) => TextFormField(
    controller: numberControllers[index],
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: l10n.mockMaterialExamQuestionNumber),
    validator: (value) {
      final number = int.tryParse(value?.trim() ?? '');
      if (number == null || number < 1) return l10n.mockMaterialExamQuestionNumberInvalid;
      if (numberControllers.where((entry) => int.tryParse(entry.text.trim()) == number).length >
          1) {
        return l10n.mockMaterialExamQuestionNumberDuplicate;
      }
      return null;
    },
  );

  Widget groupField(int index, AppLocalizations l10n) => DropdownButtonFormField<ExamQuestionGroup>(
    initialValue: groups[index],
    decoration: InputDecoration(labelText: l10n.mockMaterialExamQuestionGroup),
    items: [
      for (final group in ExamQuestionGroup.values)
        DropdownMenuItem(value: group, child: Text(examQuestionGroupLabel(l10n, group))),
    ],
    onChanged: (value) {
      if (value != null) {
        setState(() {
          groups[index] = value;
          missingListeningGroup = false;
        });
      }
    },
  );

  Widget scoreField(int index, AppLocalizations l10n) => TextFormField(
    controller: scoreControllers[index],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: l10n.mockMaterialExamQuestionScore),
    validator: (value) {
      final score = double.tryParse(value?.trim() ?? '');
      return score == null || !score.isFinite || score <= 0
          ? l10n.mockMaterialExamQuestionScoreInvalid
          : null;
    },
  );

  Widget mobileQuestion(int index, AppLocalizations l10n) => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mockMaterialExamQuestionEntry(index + 1),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        numberField(index, l10n),
        const SizedBox(height: 8),
        groupField(index, l10n),
        const SizedBox(height: 8),
        scoreField(index, l10n),
      ],
    ),
  );

  Widget desktopQuestion(int index, AppLocalizations l10n) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Text(l10n.mockMaterialExamQuestionEntry(index + 1)),
        ),
      ),
      Expanded(child: numberField(index, l10n)),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: groupField(index, l10n)),
      const SizedBox(width: 12),
      Expanded(child: scoreField(index, l10n)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.mockMaterialExamReviewQuestions,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: l10n.mockMaterialClose,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (var index = 0; index < widget.questions.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          widget.compact ? mobileQuestion(index, l10n) : desktopQuestion(index, l10n),
        ],
        if (missingListeningGroup) ...[
          const SizedBox(height: 12),
          Text(
            l10n.mockMaterialExamListeningGroupRequired,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
    final actions = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.mockMaterialExamReviewCancel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(onPressed: confirm, child: Text(l10n.mockMaterialExamReviewConfirm)),
        ),
      ],
    );
    return Form(
      key: formKey,
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SingleChildScrollView(child: fields)),
                const SizedBox(height: 12),
                actions,
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [fields, const SizedBox(height: 20), actions],
              ),
            ),
    );
  }
}

enum ExamScriptReviewAction { confirmed, rejected }

class ExamScriptReviewResult {
  const ExamScriptReviewResult({required this.action, required this.linkedItem});

  final ExamScriptReviewAction action;
  final int linkedItem;
}

class MobileExamScriptReviewSheet extends StatelessWidget {
  const MobileExamScriptReviewSheet({required this.linkedItem, super.key});

  final int linkedItem;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: ExamScriptCandidateReview(linkedItem: linkedItem, desktop: false),
    ),
  );
}

class DesktopExamScriptReviewDialog extends StatelessWidget {
  const DesktopExamScriptReviewDialog({
    required this.linkedItem,
    required this.questionNumber,
    super.key,
  });

  final int linkedItem;
  final int questionNumber;

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ExamScriptCandidateReview(
          linkedItem: linkedItem,
          desktop: true,
          questionNumber: questionNumber,
        ),
      ),
    ),
  );
}

class ExamScriptCandidateReview extends StatefulWidget {
  const ExamScriptCandidateReview({
    required this.linkedItem,
    required this.desktop,
    this.questionNumber,
    super.key,
  });

  final int linkedItem;
  final bool desktop;
  final int? questionNumber;

  @override
  State<ExamScriptCandidateReview> createState() => _ExamScriptCandidateReviewState();
}

class _ExamScriptCandidateReviewState extends State<ExamScriptCandidateReview> {
  bool verified = false;
  bool editingBinding = false;
  late int linkedItem;

  @override
  void initState() {
    super.initState();
    linkedItem = widget.linkedItem;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mockMaterialReviewListeningCandidate,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.mockMaterialClose,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (!widget.desktop) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: roles.selected,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(l10n.mockMaterialExamScriptReviewNotice),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              l10n.mockMaterialExamDesktopCandidateGroup(
                (widget.questionNumber ?? 3).toString().padLeft(2, '0'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: roles.selected,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.desktop
                      ? l10n.mockMaterialExamDesktopCandidateTitle
                      : l10n.mockMaterialExamScriptCandidateTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.desktop
                      ? l10n.mockMaterialExamDesktopCandidateText
                      : l10n.mockMaterialExamScriptCandidateText,
                  style: const TextStyle(fontSize: 16, height: 1.6, fontFamily: 'serif'),
                ),
                if (!widget.desktop) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.mockMaterialExamScriptCandidateLinkForItem(
                      linkedItem.toString().padLeft(2, '0'),
                    ),
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (widget.desktop) ...[
            const SizedBox(height: 16),
            Text(
              l10n.mockMaterialExamDesktopCandidateSource,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => setState(() => editingBinding = !editingBinding),
                child: Text(l10n.mockMaterialExamChangeBinding),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  ExamScriptReviewResult(
                    action: ExamScriptReviewAction.rejected,
                    linkedItem: linkedItem,
                  ),
                ),
                child: Text(l10n.mockMaterialExamRejectCandidate),
              ),
            ],
          ),
          if (editingBinding) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: linkedItem,
              decoration: InputDecoration(labelText: l10n.mockMaterialExamBoundQuestion),
              items: [
                for (var number = 1; number <= 3; number++)
                  DropdownMenuItem(
                    value: number,
                    child: Text(
                      l10n.mockMaterialExamBoundQuestionOption(number.toString().padLeft(2, '0')),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    linkedItem = value;
                    verified = false;
                  });
                }
              },
            ),
          ],
          const SizedBox(height: 10),
          Material(
            color: scheme.surface,
            child: CheckboxListTile(
              value: verified,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                widget.desktop
                    ? l10n.mockMaterialExamDesktopScriptVerified
                    : l10n.mockMaterialExamScriptVerified,
              ),
              onChanged: (value) => setState(() => verified = value ?? false),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: verified
                ? () => Navigator.pop(
                    context,
                    ExamScriptReviewResult(
                      action: ExamScriptReviewAction.confirmed,
                      linkedItem: linkedItem,
                    ),
                  )
                : null,
            child: Text(
              widget.desktop
                  ? l10n.mockMaterialExamDesktopConfirmMatch
                  : l10n.mockMaterialConfirmCandidateMatch,
            ),
          ),
        ],
      ),
    );
  }
}

class ExamPrepPage extends StatefulWidget {
  const ExamPrepPage({required this.item, super.key});
  final MaterialSummary item;
  @override
  State<ExamPrepPage> createState() => _ExamPrepPageState();
}

class _ExamPrepPageState extends State<ExamPrepPage> {
  bool prepHydrated = false;
  List<ExamQuestionDraft> questions = const [
    ExamQuestionDraft(number: 1, group: ExamQuestionGroup.language, score: 1),
    ExamQuestionDraft(number: 2, group: ExamQuestionGroup.reading, score: 1),
    ExamQuestionDraft(number: 3, group: ExamQuestionGroup.listening, score: 1),
  ];
  bool questionsReviewed = false;
  bool scriptConfirmed = false;
  bool scriptRejected = false;
  bool audioReady = false;
  int linkedItem = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prepHydrated) return;
    prepHydrated = true;
    final snapshot = PreviewStoreScope.of(context).examPrepFor(widget.item.id);
    if (snapshot == null) return;
    questions = [
      for (final question in snapshot.questions)
        ExamQuestionDraft(
          number: question.number,
          group: ExamQuestionGroup.values.byName(question.group.name),
          score: question.score,
        ),
    ];
    questionsReviewed = snapshot.questionsReviewed;
    scriptConfirmed = snapshot.scriptConfirmed;
    scriptRejected = snapshot.scriptRejected;
    linkedItem = snapshot.linkedItem;
    audioReady = snapshot.audioReady;
  }

  void savePreparation() {
    PreviewStoreScope.of(context).saveExamPrep(
      widget.item.id,
      ExamPrepSnapshot(
        questions: [
          for (final question in questions)
            ExamPrepQuestion(
              number: question.number,
              group: ExamPrepQuestionGroup.values.byName(question.group.name),
              score: question.score,
            ),
        ],
        questionsReviewed: questionsReviewed,
        scriptConfirmed: scriptConfirmed,
        scriptRejected: scriptRejected,
        linkedItem: linkedItem,
        audioReady: audioReady,
      ),
    );
  }

  void generateAudio() {
    setState(() => audioReady = true);
    savePreparation();
  }

  Future<void> reviewQuestions() async {
    final reviewed = MediaQuery.sizeOf(context).width < 760
        ? await showModalBottomSheet<List<ExamQuestionDraft>>(
            context: context,
            useRootNavigator: true,
            sheetAnimationStyle: HarukaMotion.sheetStyle(
              context,
              reducedMotion: PreviewStoreScope.of(context).reducedMotion,
            ),
            isScrollControlled: true,
            showDragHandle: true,
            builder: (sheetContext) => MobileExamQuestionReviewSheet(questions: questions),
          )
        : await showHarukaDialog<List<ExamQuestionDraft>>(
            context: context,
            animationStyle: HarukaMotion.dialogStyle(
              context,
              reducedMotion: PreviewStoreScope.of(context).reducedMotion,
            ),
            builder: (dialogContext) => DesktopExamQuestionReviewDialog(questions: questions),
          );
    if (reviewed == null || !mounted) return;
    final changed = reviewed.asMap().entries.any((entry) {
      final previous = questions[entry.key];
      final current = entry.value;
      return previous.number != current.number ||
          previous.group != current.group ||
          previous.score != current.score;
    });
    setState(() {
      questions = reviewed;
      questionsReviewed = true;
      if (changed) {
        scriptConfirmed = false;
        audioReady = false;
      }
    });
    savePreparation();
  }

  Future<void> confirmScript() async {
    final reviewed = MediaQuery.sizeOf(context).width < 760
        ? await showModalBottomSheet<ExamScriptReviewResult>(
            context: context,
            useRootNavigator: true,
            sheetAnimationStyle: HarukaMotion.sheetStyle(
              context,
              reducedMotion: PreviewStoreScope.of(context).reducedMotion,
            ),
            isScrollControlled: true,
            showDragHandle: true,
            builder: (sheetContext) => MobileExamScriptReviewSheet(linkedItem: linkedItem),
          )
        : await showHarukaDialog<ExamScriptReviewResult>(
            context: context,
            animationStyle: HarukaMotion.dialogStyle(
              context,
              reducedMotion: PreviewStoreScope.of(context).reducedMotion,
            ),
            builder: (dialogContext) => DesktopExamScriptReviewDialog(
              linkedItem: linkedItem,
              questionNumber: questions
                  .firstWhere((question) => question.group == ExamQuestionGroup.listening)
                  .number,
            ),
          );
    if (reviewed == null || !mounted) return;
    setState(() {
      if (reviewed.action == ExamScriptReviewAction.rejected) {
        scriptConfirmed = false;
        scriptRejected = true;
        audioReady = false;
      } else {
        if (linkedItem != reviewed.linkedItem) audioReady = false;
        linkedItem = reviewed.linkedItem;
        scriptConfirmed = true;
        scriptRejected = false;
      }
    });
    savePreparation();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final store = PreviewStoreScope.of(context);
    final canContinue = store.examDraftSaved && !store.examSubmitted;
    final canStart = questionsReviewed && audioReady;
    final mobileSteps = [
      (
        l10n.mockMaterialQuestionNumbersAndScores,
        questionsReviewed
            ? l10n.mockMaterialExamQuestionsReviewed
            : l10n.mockMaterialExtractedNeedsReview,
      ),
      (
        l10n.mockMaterialListeningTranscript,
        scriptConfirmed
            ? l10n.mockMaterialScriptMatched
            : scriptRejected
            ? l10n.mockMaterialExamCandidateRejected
            : l10n.mockMaterialScriptMatchPending,
      ),
      (
        l10n.mockMaterialPrivateSpeechAudio,
        audioReady
            ? l10n.mockMaterialAudioGenerated
            : scriptConfirmed
            ? l10n.mockMaterialAudioPending
            : l10n.mockMaterialWaitingForScriptConfirmation,
      ),
    ];
    final desktopSteps = [
      (
        l10n.mockMaterialExamDesktopQuestionStep,
        questionsReviewed
            ? l10n.mockMaterialExamQuestionsReviewed
            : l10n.mockMaterialExamDesktopNeedsQuestionReview,
      ),
      (
        l10n.mockMaterialExamDesktopScriptStep,
        scriptConfirmed
            ? l10n.mockMaterialExamDesktopConfirmed
            : scriptRejected
            ? l10n.mockMaterialExamCandidateRejected
            : l10n.mockMaterialNeedsReviewStatus,
      ),
      (
        l10n.mockMaterialExamDesktopAudioStep,
        audioReady
            ? l10n.mockMaterialExamDesktopAudioReady
            : scriptConfirmed
            ? l10n.mockMaterialAudioPending
            : l10n.mockMaterialExamDesktopAudioMissing,
      ),
    ];
    final mobileChecklist = HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < mobileSteps.length; index++)
            Padding(
              padding: EdgeInsets.only(bottom: index == mobileSteps.length - 1 ? 0 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9, right: 17),
                    child: Icon(Icons.circle, size: 8, color: scheme.primary),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mobileSteps[index].$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mobileSteps[index].$2,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final mobile = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.item.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(AppLocalizations.of(context).mockMaterialListeningPreparationRequired),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${questions.length}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    Text(AppLocalizations.of(context).mockMaterialIncludedSampleQuestions),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '60',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    Text(AppLocalizations.of(context).mockMaterialMinutesLabel),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(l10n.mockMaterialPreparationChecklist, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        mobileChecklist,
        const SizedBox(height: 16),
        if (canContinue) ...[
          FilledButton(
            onPressed: () => context.push(AppRoutes.mockExamSession),
            child: Text(l10n.mockMaterialExamContinueSession),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: reviewQuestions,
          child: Text(l10n.mockMaterialExamReviewQuestions),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: confirmScript,
          child: Text(AppLocalizations.of(context).mockMaterialReviewListeningScript),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: scriptConfirmed ? generateAudio : null,
          child: Text(AppLocalizations.of(context).mockMaterialGenerateListeningAudioMock),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(
            disabledBackgroundColor: scheme.primary.withValues(alpha: .5),
            disabledForegroundColor: scheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: canStart ? () => context.push(AppRoutes.mockExamSession) : null,
          child: Text(AppLocalizations.of(context).mockMaterialConfirmVersionAndStart),
        ),
      ],
    );
    final desktop = ListView(
      children: [
        Text(widget.item.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        Row(
          children: [
            for (final value in [
              (
                '${questions.length}',
                AppLocalizations.of(context).mockMaterialIncludedSampleQuestions,
              ),
              ('60', AppLocalizations.of(context).mockMaterialSampleTimeLimit),
              (
                canStart
                    ? l10n.mockMaterialExamDesktopAudioReady
                    : l10n.mockMaterialNeedsReviewStatus,
                AppLocalizations.of(context).mockMaterialExamStatus,
              ),
            ]) ...[
              Expanded(
                child: HarukaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.$1,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: Theme.of(context).colorScheme.primary),
                      ),
                      Text(value.$2),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  HarukaSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mockMaterialPreparationChecklist,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 18),
                        for (var index = 0; index < desktopSteps.length; index++) ...[
                          if (index > 0) Divider(color: scheme.outline.withValues(alpha: .4)),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  [Icons.check, Icons.menu_book_outlined, Icons.headphones][index],
                                  color: scheme.onSurfaceVariant,
                                  size: 21,
                                ),
                                const SizedBox(width: 16),
                                Expanded(child: Text(desktopSteps[index].$1)),
                                Container(
                                  width: 180,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color:
                                        (index == 0 && questionsReviewed) ||
                                            (index == 1 && scriptConfirmed) ||
                                            (index == 2 && audioReady)
                                        ? roles.positive.withValues(alpha: .1)
                                        : roles.bookPeach,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    desktopSteps[index].$2,
                                    style: TextStyle(
                                      color:
                                          (index == 0 && questionsReviewed) ||
                                              (index == 1 && scriptConfirmed) ||
                                              (index == 2 && audioReady)
                                          ? roles.positive
                                          : roles.warning,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: [
                            OutlinedButton(
                              onPressed: reviewQuestions,
                              child: Text(l10n.mockMaterialExamReviewQuestions),
                            ),
                            OutlinedButton(
                              onPressed: confirmScript,
                              child: Text(l10n.mockMaterialReviewListeningCandidate),
                            ),
                            OutlinedButton(
                              onPressed: scriptConfirmed ? generateAudio : null,
                              child: Text(l10n.mockMaterialGenerateAudioMock),
                            ),
                            FilledButton(
                              onPressed: canStart
                                  ? () => context.push(AppRoutes.mockExamSession)
                                  : null,
                              child: Text(l10n.mockMaterialConfirmAndFreezeVersion),
                            ),
                            if (canContinue)
                              FilledButton.tonal(
                                onPressed: () => context.push(AppRoutes.mockExamSession),
                                child: Text(l10n.mockMaterialExamContinueSession),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: roles.bookPeach,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, color: roles.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.mockMaterialSampleExamAnswerHint,
                        style: TextStyle(color: roles.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return PreviewPageFrame(
      location: AppRoutes.mockMaterialPath(widget.item.id),
      title: AppLocalizations.of(context).mockMaterialExamPreparationTitle,
      detail: true,
      detailNotifications: false,
      mobile: mobile,
      desktop: desktop,
    );
  }
}

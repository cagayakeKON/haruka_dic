import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/features/agent/application/query_images.dart';
import 'package:haruka/core/platform/query_paste.dart';
import 'package:haruka/core/platform/query_paste_stub.dart'
    if (dart.library.js_interop) 'package:haruka/core/platform/query_paste_web.dart'
    as paste_adapter;
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/agent/data/cached_query_result_repository.dart';
import 'package:haruka/features/agent/data/query_card_collection_repository.dart';
import 'package:haruka/features/agent/domain/query_history_entry.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';

import 'query_card_collection_scope.dart';
import 'query_result_scope.dart';

bool _queryReducedMotion(BuildContext context) => HarukaMotion.reduced(
  context,
  reducedMotion:
      SettingsRepositoryScope.maybeOf(context)
          ?.snapshot(SettingsGroup.preferences)
          ?.fields['reduce_motion'] ==
      'on',
);

class _QueryPinScope extends InheritedWidget {
  const _QueryPinScope({required this.repository, required super.child});
  final CachedQueryResultRepository? repository;
  static CachedQueryResultRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_QueryPinScope>()?.repository;
  @override
  bool updateShouldNotify(_QueryPinScope oldWidget) => !identical(repository, oldWidget.repository);
}

List<String> queryExamples(BuildContext context) {
  final strings = AppLocalizations.of(context);
  return [
    strings.mockQueryExampleWord,
    strings.mockQueryExampleTranslation,
    strings.mockQueryExampleGrammar,
    strings.mockQueryExampleCorrection,
  ];
}

String queryCardKind(BuildContext context, CollectionKind kind) {
  final strings = AppLocalizations.of(context);
  return switch (kind) {
    CollectionKind.word => strings.mockQueryCardKindWord,
    CollectionKind.phrase => strings.mockQueryCardKindPhrase,
    CollectionKind.grammar => strings.mockQueryCardKindGrammar,
    CollectionKind.sentence => strings.mockQueryCardKindSentence,
    CollectionKind.excerpt => strings.mockQueryCardKindExcerpt,
    CollectionKind.exercise => strings.mockQueryCardKindExercise,
  };
}

class QueryPage extends StatefulWidget {
  const QueryPage({
    this.imagePort,
    this.pasteSource,
    this.initialText,
    this.queryResults,
    super.key,
  });
  final QueryImagePort? imagePort;
  final QueryPasteSource? pasteSource;
  final String? initialText;
  final QueryResultRepository? queryResults;
  @override
  State<QueryPage> createState() => _QueryPageState();
}

class _QueryPageState extends State<QueryPage> with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: _scheduleResultCheck,
    onReturned: _scheduleResultCheck,
  );
  CachedQueryResultRepository? _cachedResults;
  Timer? _visibleResultTimer;
  bool _foreground = true;
  CachedSettingsRepository? _settings;
  int? _settingsScopeGeneration;
  bool _scopeObserved = false;
  int _draftEpoch = 0;
  final input = TextEditingController();
  final contextInput = TextEditingController();
  final inputFocus = FocusNode();
  final contextFocus = FocusNode();
  final _latestResultKey = GlobalKey();
  bool contextOpen = false;
  final images = <QueryImageAttachment>[];
  QueryImageProblem? imageProblem;
  bool imagePending = false;
  bool imageUnanalysed = false;
  bool queryPending = false;
  late final QueryImagePort _imagePort = widget.imagePort ?? const SystemQueryImagePort();
  late final QueryPasteSource _pasteSource =
      widget.pasteSource ?? paste_adapter.createQueryPasteSource();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    input.text = widget.initialText ?? '';
    input.addListener(_refreshInputState);
    _startPasteSource();
    unawaited(_recoverLostPhotos());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageActivity.bind(context);
    _bindResultRepository();
    final settings = SettingsRepositoryScope.maybeOf(context);
    final scopeGeneration = settings?.scopeGeneration;
    if (_scopeObserved &&
        (!identical(settings, _settings) || scopeGeneration != _settingsScopeGeneration)) {
      _clearAccountDraft();
      _startPasteSource();
    }
    _scopeObserved = true;
    if (settings == null) {
      _settings = null;
      _settingsScopeGeneration = null;
      return;
    }
    if (identical(settings, _settings) && scopeGeneration == _settingsScopeGeneration) return;
    _settings = settings;
    _settingsScopeGeneration = scopeGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_settings, settings)) return;
      unawaited(settings.refresh(SettingsGroup.studyProfile));
      unawaited(settings.refresh(SettingsGroup.preferences));
    });
  }

  void _bindResultRepository() {
    final repository = widget.queryResults ?? QueryResultScope.of(context);
    final cached = repository is CachedQueryResultRepository ? repository : null;
    if (identical(cached, _cachedResults)) {
      _scheduleResultCheck();
      return;
    }
    _cachedResults?.removeListener(_onResultsChanged);
    _cachedResults?.setVisible(false);
    _cachedResults = cached;
    cached?.addListener(_onResultsChanged);
    _scheduleResultCheck();
  }

  void _onResultsChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleResultCheck() {
    _visibleResultTimer?.cancel();
    _visibleResultTimer = null;
    final cached = _cachedResults;
    // Window focus does not change which page owns its displayed result pins.
    // Account invalidation is still handled by the repository itself.
    final visible = _pageActivity.isCurrent;
    cached?.setVisible(visible);
    if (cached == null || !visible) return;
    _visibleResultTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_pageActivity.isCurrent) {
        cached.setVisible(false);
        return;
      }
      if (!_foreground) {
        return;
      }
      if (!cached.isVisible) {
        cached.setVisible(true);
        return;
      }
      unawaited(cached.revalidateVisible());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void didUpdateWidget(covariant QueryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.queryResults, widget.queryResults)) _bindResultRepository();
    if (widget.initialText != oldWidget.initialText && widget.initialText != null) {
      input.text = widget.initialText!;
    }
  }

  void _refreshInputState() {
    if (mounted) setState(() {});
  }

  void _clearAccountDraft() {
    _draftEpoch++;
    input.removeListener(_refreshInputState);
    input.clear();
    input.addListener(_refreshInputState);
    contextInput.clear();
    images.clear();
    imageProblem = null;
    imagePending = false;
    imageUnanalysed = false;
    queryPending = false;
    contextOpen = false;
  }

  bool _currentDraft(int epoch) => mounted && epoch == _draftEpoch;

  void _startPasteSource() {
    final epoch = _draftEpoch;
    _pasteSource.start(
      canAccept: () =>
          _currentDraft(epoch) &&
          _settings?.snapshot(SettingsGroup.studyProfile) != null &&
          (inputFocus.hasFocus || contextFocus.hasFocus),
      onImages: (selected) => unawaited(_appendImages(selected, epoch: epoch)),
      onReadError: (problem) {
        if (_currentDraft(epoch)) _setImageProblem(problem);
      },
    );
  }

  @override
  void dispose() {
    _visibleResultTimer?.cancel();
    _cachedResults?.removeListener(_onResultsChanged);
    _cachedResults?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    _pageActivity.dispose();
    input.removeListener(_refreshInputState);
    _pasteSource.dispose();
    input.dispose();
    contextInput.dispose();
    inputFocus.dispose();
    contextFocus.dispose();
    super.dispose();
  }

  void useExample(String example) {
    final existing = input.text.trimRight();
    if (existing.length + example.length + (existing.isEmpty ? 0 : 1) > 2000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockQueryInputTooLong)));
      return;
    }
    input.text = existing.isEmpty ? example : '$existing\n$example';
    input.selection = TextSelection.collapsed(offset: input.text.length);
    setState(() {
      imageUnanalysed = false;
      imageProblem = null;
    });
  }

  void _setImageProblem(QueryImageProblem problem) {
    if (mounted) setState(() => imageProblem = problem);
  }

  Future<void> _recoverLostPhotos() async {
    final epoch = _draftEpoch;
    try {
      final recovered = await _imagePort.recoverLostPhotos();
      if (_currentDraft(epoch) && recovered.isNotEmpty) {
        await _appendImages(recovered, epoch: epoch);
      }
    } on QueryImageException catch (error) {
      if (_currentDraft(epoch)) _setImageProblem(error.problem);
    } catch (_) {
      if (_currentDraft(epoch)) _setImageProblem(QueryImageProblem.invalid);
    }
  }

  Future<void> _pickImages() async {
    if (imagePending) return;
    final epoch = _draftEpoch;
    setState(() => imagePending = true);
    try {
      final selected = await _imagePort.pickImages();
      if (_currentDraft(epoch)) await _appendImages(selected, epoch: epoch);
    } on QueryImageException catch (error) {
      if (_currentDraft(epoch)) _setImageProblem(error.problem);
    } catch (_) {
      if (_currentDraft(epoch)) _setImageProblem(QueryImageProblem.invalid);
    } finally {
      if (_currentDraft(epoch)) setState(() => imagePending = false);
    }
  }

  Future<void> _takePhoto() async {
    if (imagePending) return;
    final epoch = _draftEpoch;
    setState(() => imagePending = true);
    try {
      final photo = await _imagePort.takePhoto();
      if (_currentDraft(epoch) && photo != null) await _appendImages([photo], epoch: epoch);
    } on QueryImageException catch (error) {
      if (_currentDraft(epoch)) _setImageProblem(error.problem);
    } catch (_) {
      if (_currentDraft(epoch)) _setImageProblem(QueryImageProblem.cameraUnavailable);
    } finally {
      if (_currentDraft(epoch)) setState(() => imagePending = false);
    }
  }

  Future<void> _appendImages(List<RawQueryImage> selected, {int? epoch}) async {
    final requestEpoch = epoch ?? _draftEpoch;
    if (selected.isEmpty || !_currentDraft(requestEpoch)) return;
    if (images.length + selected.length > queryImageLimit) {
      _setImageProblem(QueryImageProblem.tooMany);
      return;
    }
    try {
      final validated = await Future.wait(selected.map(validateQueryImage));
      if (!_currentDraft(requestEpoch)) return;
      setState(() {
        images.addAll(validated);
        imageProblem = null;
        imageUnanalysed = false;
      });
    } on QueryImageException catch (error) {
      if (_currentDraft(requestEpoch)) _setImageProblem(error.problem);
    }
  }

  void _removeImage(int index) => setState(() {
    images.removeAt(index);
    imageProblem = null;
    imageUnanalysed = false;
  });

  void _previewImage(int index) {
    if (index < 0 || index >= images.length) return;
    final settings = _settings;
    if (settings == null || settings.snapshot(SettingsGroup.studyProfile) == null) return;
    final generation = settings.scopeGeneration;
    final epoch = _draftEpoch;
    final image = images[index];
    unawaited(
      showHarukaDialog<void>(
        context: context,
        animationStyle: HarukaMotion.dialogStyle(
          context,
          reducedMotion: _queryReducedMotion(context),
        ),
        builder: (dialogContext) => AnimatedBuilder(
          animation: settings,
          builder: (dialogContext, _) {
            final available =
                _currentDraft(epoch) &&
                settings.scopeGeneration == generation &&
                settings.snapshot(SettingsGroup.studyProfile) != null;
            if (!available) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted && ModalRoute.of(dialogContext)?.isCurrent == true) {
                  Navigator.of(dialogContext).pop();
                }
              });
              return const SizedBox.shrink();
            }
            return Dialog(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.8,
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => InteractiveViewer(
                          child: Image.memory(
                            image.bytes,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> send() async {
    final epoch = _draftEpoch;
    final value = input.text.trim();
    if ((value.isEmpty && images.isEmpty) || imagePending || queryPending) return;
    if (images.isNotEmpty) {
      setState(() {
        imageProblem = null;
        imageUnanalysed = true;
      });
      return;
    }
    final repository = widget.queryResults ?? QueryResultScope.of(context);
    final study = _settings?.snapshot(SettingsGroup.studyProfile);
    final targetLanguage = study?.fields['active_target_language'];
    final explanationLanguage = study?.fields['explanation_language'];
    if ((targetLanguage is! String ||
            (targetLanguage.isNotEmpty && !const {'ja', 'en'}.contains(targetLanguage))) ||
        explanationLanguage is! String ||
        explanationLanguage.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      return;
    }
    setState(() {
      imageProblem = null;
      queryPending = true;
    });
    try {
      await repository.submit(
        QueryRequest(
          text: value,
          context: contextInput.text.trim(),
          targetLanguage: targetLanguage,
          explanationLanguage: explanationLanguage,
        ),
      );
      if (!_currentDraft(epoch)) return;
      input.clear();
      setState(() {
        imageUnanalysed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _latestResultKey.currentContext;
        if (!_currentDraft(epoch) || target == null) return;
        unawaited(
          Scrollable.ensureVisible(
            target,
            duration: HarukaMotion.reduced(target, reducedMotion: _queryReducedMotion(target))
                ? Duration.zero
                : const Duration(milliseconds: 240),
            alignment: MediaQuery.sizeOf(target).width < 760 ? 0 : .08,
            curve: Curves.easeOut,
          ),
        );
      });
    } on Object {
      if (mounted && _currentDraft(epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mockQueryRequestFailed)),
        );
      }
    } finally {
      if (_currentDraft(epoch)) setState(() => queryPending = false);
    }
  }

  void again() {
    input.clear();
    contextInput.clear();
    setState(() {
      imageUnanalysed = false;
      imageProblem = null;
      images.clear();
    });
    inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_foreground &&
        _cachedResults != null &&
        !_cachedResults!.isVisible &&
        _pageActivity.isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageActivity.isCurrent) {
          _cachedResults?.setVisible(true);
        }
      });
    }
    final entries = (widget.queryResults ?? QueryResultScope.of(context)).history;
    final result = entries.lastOrNull?.card;
    return _QueryPinScope(
      repository: _cachedResults,
      child: PreviewPageFrame(
        location: AppRoutes.mockQuery,
        title: AppLocalizations.of(context).mockQueryTitle,
        mobile: MobileQueryView(
          input: input,
          contextInput: contextInput,
          inputFocus: inputFocus,
          contextFocus: contextFocus,
          contextOpen: contextOpen,
          images: images,
          imageProblem: imageProblem,
          imagePending: imagePending,
          imageUnanalysed: imageUnanalysed,
          result: result,
          entries: entries,
          latestCardKey: _latestResultKey,
          onExample: useExample,
          onToggleContext: () => setState(() => contextOpen = !contextOpen),
          onAttachImage: _pickImages,
          onTakePhoto: _takePhoto,
          onRemoveImage: _removeImage,
          onPreviewImage: _previewImage,
          onSend: send,
          onAgain: again,
        ),
        desktop: DesktopQueryView(
          input: input,
          contextInput: contextInput,
          inputFocus: inputFocus,
          contextFocus: contextFocus,
          contextOpen: contextOpen,
          images: images,
          imageProblem: imageProblem,
          imagePending: imagePending,
          imageUnanalysed: imageUnanalysed,
          result: result,
          entries: entries,
          latestCardKey: _latestResultKey,
          onExample: useExample,
          onToggleContext: () => setState(() => contextOpen = !contextOpen),
          onAttachImage: _pickImages,
          onRemoveImage: _removeImage,
          onPreviewImage: _previewImage,
          onSend: send,
          onAgain: again,
        ),
      ),
    );
  }
}

class MobileQueryView extends StatelessWidget {
  const MobileQueryView({
    required this.input,
    required this.contextInput,
    required this.inputFocus,
    required this.contextFocus,
    required this.contextOpen,
    required this.images,
    required this.imageProblem,
    required this.imagePending,
    required this.imageUnanalysed,
    required this.result,
    required this.entries,
    required this.latestCardKey,
    required this.onExample,
    required this.onToggleContext,
    required this.onAttachImage,
    required this.onTakePhoto,
    required this.onRemoveImage,
    required this.onPreviewImage,
    required this.onSend,
    required this.onAgain,
    super.key,
  });
  final TextEditingController input;
  final TextEditingController contextInput;
  final FocusNode inputFocus;
  final FocusNode contextFocus;
  final bool contextOpen;
  final List<QueryImageAttachment> images;
  final QueryImageProblem? imageProblem;
  final bool imagePending;
  final bool imageUnanalysed;
  final LearningCard? result;
  final List<QueryHistoryEntry> entries;
  final Key latestCardKey;
  final ValueChanged<String> onExample;
  final VoidCallback onToggleContext;
  final VoidCallback onAttachImage;
  final VoidCallback onTakePhoto;
  final ValueChanged<int> onRemoveImage;
  final ValueChanged<int> onPreviewImage;
  final VoidCallback onSend;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    if (entries.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 35),
        children: [
          for (final entry in entries) ...[
            _QueryPromptBubble(text: entry.prompt),
            const SizedBox(height: 17),
            QueryResultCard(
              key: identical(entry, entries.last) ? latestCardKey : null,
              card: entry.card,
              targetLanguage: entry.targetLanguage,
              motionIdentity: entry,
              onAgain: onAgain,
            ),
            const SizedBox(height: 24),
          ],
          if (imageUnanalysed) ...[const _QueryImagePendingResult(), const SizedBox(height: 24)],
          _CompactQueryComposer(
            input: input,
            inputFocus: inputFocus,
            contextInput: contextInput,
            contextFocus: contextFocus,
            contextOpen: contextOpen,
            images: images,
            imageProblem: imageProblem,
            imagePending: imagePending,
            onToggleContext: onToggleContext,
            onAttachImage: onAttachImage,
            onTakePhoto: onTakePhoto,
            onRemoveImage: onRemoveImage,
            onPreviewImage: onPreviewImage,
            onSend: onSend,
            mobile: true,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 35),
      children: [
        Text(strings.mockQuerySubtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        HarukaSurface(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: input,
                focusNode: inputFocus,
                maxLines: null,
                minLines: 2,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: strings.mockQueryInputHint,
                  border: InputBorder.none,
                ),
              ),
              TextButton.icon(
                onPressed: onToggleContext,
                icon: Icon(contextOpen ? Icons.expand_less : Icons.expand_more, size: 17),
                label: Text(strings.mockQueryContextToggle),
              ),
              if (contextOpen)
                TextField(
                  controller: contextInput,
                  focusNode: contextFocus,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: strings.mockQueryContextHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (images.isNotEmpty) ...[
                _QueryImageStrip(
                  images: images,
                  onRemove: onRemoveImage,
                  onPreview: onPreviewImage,
                ),
                const SizedBox(height: 12),
              ],
              if (imageProblem case final problem?) ...[
                Text(
                  _queryImageProblemText(strings, problem),
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: imagePending ? null : onAttachImage,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.primary,
                    ),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(strings.mockQueryGallery),
                  ),
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: imagePending ? null : onTakePhoto,
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.primary,
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(strings.mockQueryCamera),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: !imagePending && (input.text.trim().isNotEmpty || images.isNotEmpty)
                        ? onSend
                        : null,
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: scheme.primary.withValues(alpha: 0.45),
                      disabledForegroundColor: scheme.onPrimary,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings.mockQuerySend),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                strings.mockQueryMobileImageHint,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (imageUnanalysed)
          const _QueryImagePendingResult()
        else if (result == null) ...[
          Text(strings.mockQueryExamplesTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 11),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.7,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            children: [
              for (final example in queryExamples(context))
                HarukaSurface(
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () => onExample(example),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          example,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ] else
          QueryResultCard(card: result!, onAgain: onAgain),
      ],
    );
  }
}

class DesktopQueryView extends StatelessWidget {
  const DesktopQueryView({
    required this.input,
    required this.contextInput,
    required this.inputFocus,
    required this.contextFocus,
    required this.contextOpen,
    required this.images,
    required this.imageProblem,
    required this.imagePending,
    required this.imageUnanalysed,
    required this.result,
    required this.entries,
    required this.latestCardKey,
    required this.onExample,
    required this.onToggleContext,
    required this.onAttachImage,
    required this.onRemoveImage,
    required this.onPreviewImage,
    required this.onSend,
    required this.onAgain,
    super.key,
  });
  final TextEditingController input;
  final TextEditingController contextInput;
  final FocusNode inputFocus;
  final FocusNode contextFocus;
  final bool contextOpen;
  final List<QueryImageAttachment> images;
  final QueryImageProblem? imageProblem;
  final bool imagePending;
  final bool imageUnanalysed;
  final LearningCard? result;
  final List<QueryHistoryEntry> entries;
  final Key latestCardKey;
  final ValueChanged<String> onExample;
  final VoidCallback onToggleContext;
  final VoidCallback onAttachImage;
  final ValueChanged<int> onRemoveImage;
  final ValueChanged<int> onPreviewImage;
  final VoidCallback onSend;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    if (entries.isNotEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: HarukaLayout.queryMaxWidth),
          child: ListView(
            children: [
              const SizedBox(height: 24),
              for (final entry in entries) ...[
                _QueryPromptBubble(text: entry.prompt),
                const SizedBox(height: 17),
                QueryResultCard(
                  key: identical(entry, entries.last) ? latestCardKey : null,
                  card: entry.card,
                  targetLanguage: entry.targetLanguage,
                  motionIdentity: entry,
                  onAgain: onAgain,
                ),
                const SizedBox(height: 26),
              ],
              if (imageUnanalysed) ...[
                const _QueryImagePendingResult(),
                const SizedBox(height: 26),
              ],
              _CompactQueryComposer(
                input: input,
                inputFocus: inputFocus,
                contextInput: contextInput,
                contextFocus: contextFocus,
                contextOpen: contextOpen,
                images: images,
                imageProblem: imageProblem,
                imagePending: imagePending,
                onToggleContext: onToggleContext,
                onAttachImage: onAttachImage,
                onTakePhoto: null,
                onRemoveImage: onRemoveImage,
                onPreviewImage: onPreviewImage,
                onSend: onSend,
                mobile: false,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: HarukaLayout.queryMaxWidth),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.mockQueryTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Text(
                  strings.mockQueryLearningLabel,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(strings.mockQuerySubtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            HarukaSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: input,
                    focusNode: inputFocus,
                    maxLines: null,
                    minLines: 2,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      hintText: strings.mockQueryInputHint,
                      border: InputBorder.none,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onToggleContext,
                    icon: Icon(contextOpen ? Icons.arrow_drop_up : Icons.arrow_right),
                    label: Text(strings.mockQueryContextToggle),
                  ),
                  if (contextOpen)
                    TextField(
                      controller: contextInput,
                      focusNode: contextFocus,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: strings.mockQueryContextHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  if (images.isNotEmpty) ...[
                    _QueryImageStrip(
                      images: images,
                      onRemove: onRemoveImage,
                      onPreview: onPreviewImage,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (imageProblem case final problem?) ...[
                    Text(
                      _queryImageProblemText(strings, problem),
                      style: TextStyle(color: scheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: imagePending ? null : onAttachImage,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.primary,
                        ),
                        icon: const Icon(Icons.image_outlined),
                        label: Text(strings.mockQueryImage),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed:
                            !imagePending && (input.text.trim().isNotEmpty || images.isNotEmpty)
                            ? onSend
                            : null,
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.45),
                          disabledForegroundColor: scheme.onPrimary,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(strings.mockQuerySend),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    strings.mockQueryDesktopImageHint,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            if (imageUnanalysed)
              const _QueryImagePendingResult()
            else if (result == null) ...[
              Text(strings.mockQueryExamplesTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 4.8,
                children: [
                  for (final example in queryExamples(context))
                    HarukaSurface(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () => onExample(example),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(example, style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                ],
              ),
            ] else
              QueryResultCard(card: result!, onAgain: onAgain),
          ],
        ),
      ),
    );
  }
}

String _queryImageProblemText(AppLocalizations strings, QueryImageProblem problem) =>
    switch (problem) {
      QueryImageProblem.tooMany => strings.mockQueryImageTooMany,
      QueryImageProblem.tooLarge => strings.mockQueryImageTooLarge,
      QueryImageProblem.unsupported => strings.mockQueryImageUnsupported,
      QueryImageProblem.invalid => strings.mockQueryImageInvalid,
      QueryImageProblem.cameraUnavailable => strings.mockQueryCameraUnavailable,
      QueryImageProblem.permissionDenied => strings.mockQueryCameraPermissionDenied,
    };

class _QueryImageStrip extends StatelessWidget {
  const _QueryImageStrip({required this.images, required this.onRemove, required this.onPreview});

  final List<QueryImageAttachment> images;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPreview;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Stack(
          children: [
            Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: Ink.image(
                image: MemoryImage(images[index].bytes),
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                child: InkWell(
                  key: ValueKey('query-image-preview-$index'),
                  onTap: () => onPreview(index),
                  child: Semantics(label: strings.mockQueryImagePreview),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: colors.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  key: ValueKey('query-image-remove-$index'),
                  onPressed: () => onRemove(index),
                  tooltip: strings.mockQueryImageRemove,
                  icon: const Icon(Icons.close, size: 17),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryImagePendingResult extends StatelessWidget {
  const _QueryImagePendingResult();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return HarukaSurface(
      child: Row(
        children: [
          Icon(Icons.image_search_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(AppLocalizations.of(context).mockQueryImageUnanalysed)),
        ],
      ),
    );
  }
}

class _QueryPromptBubble extends StatelessWidget {
  const _QueryPromptBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          child: Text(text, style: TextStyle(color: colors.onPrimaryContainer)),
        ),
      ),
    );
  }
}

class _CompactQueryComposer extends StatelessWidget {
  const _CompactQueryComposer({
    required this.input,
    required this.inputFocus,
    required this.contextInput,
    required this.contextFocus,
    required this.contextOpen,
    required this.images,
    required this.imageProblem,
    required this.imagePending,
    required this.onToggleContext,
    required this.onAttachImage,
    required this.onTakePhoto,
    required this.onRemoveImage,
    required this.onPreviewImage,
    required this.onSend,
    required this.mobile,
  });
  final TextEditingController input;
  final FocusNode inputFocus;
  final TextEditingController contextInput;
  final FocusNode contextFocus;
  final bool contextOpen;
  final List<QueryImageAttachment> images;
  final QueryImageProblem? imageProblem;
  final bool imagePending;
  final VoidCallback onToggleContext;
  final VoidCallback onAttachImage;
  final VoidCallback? onTakePhoto;
  final ValueChanged<int> onRemoveImage;
  final ValueChanged<int> onPreviewImage;
  final VoidCallback onSend;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    return HarukaSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: input,
            focusNode: inputFocus,
            maxLines: 2,
            minLines: 2,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: strings.mockQueryInputHint,
              border: InputBorder.none,
            ),
          ),
          TextButton.icon(
            onPressed: onToggleContext,
            icon: Icon(contextOpen ? Icons.expand_less : Icons.expand_more, size: 17),
            label: Text(strings.mockQueryContextToggle),
          ),
          if (contextOpen)
            TextField(
              controller: contextInput,
              focusNode: contextFocus,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: strings.mockQueryContextHint,
                border: const OutlineInputBorder(),
              ),
            ),
          if (images.isNotEmpty) ...[
            _QueryImageStrip(images: images, onRemove: onRemoveImage, onPreview: onPreviewImage),
            const SizedBox(height: 10),
          ],
          if (imageProblem case final problem?)
            Text(_queryImageProblemText(strings, problem), style: TextStyle(color: colors.error)),
          Row(
            children: [
              TextButton.icon(
                onPressed: imagePending ? null : onAttachImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(mobile ? strings.mockQueryGallery : strings.mockQueryImage),
              ),
              if (mobile && !kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                IconButton(
                  tooltip: strings.mockQueryCamera,
                  onPressed: imagePending ? null : onTakePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                ),
              const Spacer(),
              FilledButton(
                onPressed: !imagePending && (input.text.trim().isNotEmpty || images.isNotEmpty)
                    ? onSend
                    : null,
                child: Text(strings.mockQuerySend),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final Expando<bool> _playedQueryResultMotion = Expando<bool>();

class QueryResultCard extends StatefulWidget {
  const QueryResultCard({
    required this.card,
    required this.onAgain,
    this.targetLanguage = '',
    this.motionIdentity,
    this.inOverlay = false,
    super.key,
  });
  final LearningCard card;
  final String targetLanguage;
  final VoidCallback onAgain;
  final Object? motionIdentity;
  final bool inOverlay;

  @override
  State<QueryResultCard> createState() => _QueryResultCardState();
}

class _QueryResultCardState extends State<QueryResultCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late final Animation<double> _mainOpacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<double> _bodyOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.1875, 1, curve: Curves.easeOut),
  );
  late final Animation<double> _actionOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.375, 1, curve: Curves.easeOut),
  );
  bool _initialized = false;
  bool _bookmarkPending = false;
  CachedQueryResultRepository? _pinRepository;

  Object get _identity => widget.motionIdentity ?? widget.card;

  bool _reducedMotion() => _queryReducedMotion(context);

  void _startForIdentity() {
    if (_playedQueryResultMotion[_identity] == true || _reducedMotion()) {
      _playedQueryResultMotion[_identity] = true;
      _controller.value = 1;
      return;
    }
    _playedQueryResultMotion[_identity] = true;
    _controller.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cached = _QueryPinScope.maybeOf(context);
    if (!identical(_pinRepository, cached)) {
      _pinRepository?.unmountCard(widget.card);
      _pinRepository = cached;
      cached?.mountCard(widget.card);
    }
    if (!_initialized) {
      _initialized = true;
      _startForIdentity();
    } else if (_reducedMotion()) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant QueryResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id || oldWidget.card.version != widget.card.version) {
      _pinRepository?.unmountCard(oldWidget.card);
      _pinRepository?.mountCard(widget.card);
    }
    if (!identical(oldWidget.motionIdentity ?? oldWidget.card, _identity)) {
      _startForIdentity();
    }
  }

  @override
  void dispose() {
    _pinRepository?.unmountCard(widget.card);
    _controller.dispose();
    super.dispose();
  }

  void _readAloud(BuildContext context) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockQueryAudioUnavailable)));

  Future<void> _bookmark() async {
    if (_bookmarkPending) return;
    final saver = QueryCardCollectionScope.maybeOf(context);
    final catalog = CollectionCatalogScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    if (saver == null || catalog == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.authUnavailableShort)));
      return;
    }
    setState(() => _bookmarkPending = true);
    try {
      await Future.wait([
        if (catalog.allCollectionStatus != CollectionCatalogStatus.ready)
          catalog.refreshAllCollections(preserveCurrent: true),
        if (catalog.notebookStatus != CollectionCatalogStatus.ready)
          catalog.refreshNotebooks(preserveCurrent: true),
      ]);
      if (!mounted) return;
      if (catalog.allCollectionStatus != CollectionCatalogStatus.ready ||
          catalog.notebookStatus != CollectionCatalogStatus.ready) {
        throw StateError('Collection snapshot unavailable');
      }
      if (saver.isSaved(widget.card.id, widget.card.version)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockQueryAlreadySaved)));
        return;
      }
      final targetLanguage = saver.targetLanguage(widget.card.id, widget.card.version);
      final panel = _QueryBookmarkPanel(
        catalog: catalog,
        saver: saver,
        cardId: widget.card.id,
        cardRevision: widget.card.version,
        targetLanguage: targetLanguage,
        scopeGeneration: catalog.scopeGeneration,
      );
      final compact = MediaQuery.sizeOf(context).width < 760;
      final outcome = compact
          ? await showModalBottomSheet<QueryCardSaveOutcome>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              showDragHandle: true,
              sheetAnimationStyle: HarukaMotion.sheetStyle(
                context,
                reducedMotion: _queryReducedMotion(context),
              ),
              builder: (context) => SafeArea(
                child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), child: panel),
              ),
            )
          : await showHarukaDialog<QueryCardSaveOutcome>(
              context: context,
              animationStyle: HarukaMotion.dialogStyle(
                context,
                reducedMotion: _queryReducedMotion(context),
              ),
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 520,
                  child: Padding(padding: const EdgeInsets.all(28), child: panel),
                ),
              ),
            );
      if (!mounted || outcome == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome == QueryCardSaveOutcome.saved
                ? AppLocalizations.of(context).mockQuerySaved
                : AppLocalizations.of(context).mockQueryAlreadySaved,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    } finally {
      if (mounted) setState(() => _bookmarkPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    final saver = QueryCardCollectionScope.maybeOf(context);
    final saved = saver?.isSaved(widget.card.id, widget.card.version) ?? false;
    final overlay = widget.inOverlay || ModalRoute.of(context) is PopupRoute;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: overlay ? Offset.zero : Offset(0, 18 * (1 - _mainOpacity.value)),
        child: FadeTransition(
          key: const ValueKey('query-result-main-motion'),
          opacity: _mainOpacity,
          child: child,
        ),
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(21),
          side: BorderSide(color: colors.primary, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: colors.primaryContainer.withValues(alpha: .45),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  Icon(_kindIcon(widget.card.kind), color: colors.primary, size: 18),
                  const SizedBox(width: 9),
                  Text(
                    queryCardKind(context, widget.card.kind),
                    style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (widget.targetLanguage == 'ja' || widget.targetLanguage == 'en')
                    Text(
                      widget.targetLanguage == 'en'
                          ? strings.mockShellEnglish
                          : strings.mockShellJapanese,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            FadeTransition(
              key: const ValueKey('query-result-body-motion'),
              opacity: _bodyOpacity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.card.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (widget.card.kind == CollectionKind.word ||
                            widget.card.kind == CollectionKind.sentence) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: strings.mockQueryReadAloud,
                            onPressed: () => _readAloud(context),
                            icon: const Icon(Icons.volume_up_outlined),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    _QueryResultBody(card: widget.card),
                  ],
                ),
              ),
            ),
            FadeTransition(
              key: const ValueKey('query-result-actions-motion'),
              opacity: _actionOpacity,
              child: Container(
                color: colors.primaryContainer.withValues(alpha: .35),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(onPressed: widget.onAgain, child: Text(strings.mockQueryAgain)),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _bookmarkPending || saved || saver == null ? null : _bookmark,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(saved ? strings.mockQueryBookmarked : strings.mockQuerySaveCard),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryBookmarkPanel extends StatefulWidget {
  const _QueryBookmarkPanel({
    required this.catalog,
    required this.saver,
    required this.cardId,
    required this.cardRevision,
    required this.targetLanguage,
    required this.scopeGeneration,
  });

  final CollectionCatalog catalog;
  final QueryCardCollectionRepository saver;
  final String cardId;
  final int cardRevision;
  final String? targetLanguage;
  final int scopeGeneration;

  @override
  State<_QueryBookmarkPanel> createState() => _QueryBookmarkPanelState();
}

class _QueryBookmarkPanelState extends State<_QueryBookmarkPanel> {
  final selected = <String>{};
  String? confirmedLanguage;
  bool busy = false;
  bool failed = false;

  Future<void> _confirm() async {
    if (busy || widget.catalog.scopeGeneration != widget.scopeGeneration) return;
    final language = widget.targetLanguage ?? confirmedLanguage;
    if (language == null) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final outcome = await widget.saver.save(
        QueryCardSaveRequest(
          cardId: widget.cardId,
          cardRevision: widget.cardRevision,
          notebookIds: selected,
          confirmedTargetLanguage: widget.targetLanguage == null ? language : null,
        ),
      );
      if (mounted) Navigator.of(context).pop(outcome);
    } on Object {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.catalog,
    builder: (context, _) {
      final strings = AppLocalizations.of(context);
      final available =
          widget.catalog.scopeGeneration == widget.scopeGeneration &&
          widget.catalog.allCollectionStatus == CollectionCatalogStatus.ready &&
          widget.catalog.notebookStatus == CollectionCatalogStatus.ready;
      final language = widget.targetLanguage ?? confirmedLanguage;
      final notebooks = available && language != null
          ? widget.catalog.notebooks.where((book) => book.targetLanguage == language).toList()
          : <NotebookRecord>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.mockQueryBookmarkTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (!available)
            Text(strings.authUnavailableShort)
          else ...[
            if (widget.targetLanguage == null) ...[
              Text(strings.mockSettingCurrentLearningLanguage),
              DropdownButton<String>(
                value: confirmedLanguage,
                hint: Text(strings.mockSettingCurrentLearningLanguage),
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'ja', child: Text(strings.mockSettingJapanese)),
                  DropdownMenuItem(value: 'en', child: Text(strings.mockSettingEnglish)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        confirmedLanguage = value;
                        selected.clear();
                      }),
              ),
            ],
            for (final notebook in notebooks)
              CheckboxListTile(
                value: selected.contains(notebook.id),
                title: Text(notebook.name),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: busy
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                          selected.add(notebook.id);
                        } else {
                          selected.remove(notebook.id);
                        }
                      }),
              ),
            if (failed) ...[
              const SizedBox(height: 8),
              Text(
                strings.authUnavailableShort,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 15),
            FilledButton(
              onPressed: busy || language == null ? null : _confirm,
              child: Text(strings.mockLearningPracticeBookmarkConfirm),
            ),
          ],
        ],
      );
    },
  );
}

IconData _kindIcon(CollectionKind kind) => switch (kind) {
  CollectionKind.word => Icons.menu_book_outlined,
  CollectionKind.sentence => Icons.translate_outlined,
  CollectionKind.grammar => Icons.account_tree_outlined,
  CollectionKind.exercise => Icons.edit_outlined,
  _ => Icons.bookmark_outline,
};

class _QueryResultBody extends StatelessWidget {
  const _QueryResultBody({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant, height: 1.65);
    switch (card.kind) {
      case CollectionKind.word:
        final word = card.wordDetail;
        if (word == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultHighlight(label: strings.mockQueryMeaningLabel, value: card.explanation),
              if (card.examples.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(strings.mockQueryContextExamples, style: muted),
                const SizedBox(height: 12),
                for (final (index, example) in card.examples.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ResultExample(
                      number: '${index + 1}'.padLeft(2, '0'),
                      original: example,
                    ),
                  ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${word.romanization}  ·  ${word.partOfSpeech}', style: muted),
            const SizedBox(height: 20),
            _ResultHighlight(label: strings.mockQueryMeaningLabel, value: word.meaning),
            const SizedBox(height: 20),
            Text(word.usage, style: muted),
            const SizedBox(height: 22),
            Divider(color: colors.outline.withValues(alpha: .25)),
            const SizedBox(height: 13),
            Text(strings.mockQueryContextExamples, style: muted),
            const SizedBox(height: 14),
            for (final (index, example) in word.examples.indexed) ...[
              if (index > 0) const SizedBox(height: 16),
              _ResultExample(
                number: '${index + 1}'.padLeft(2, '0'),
                original: example.text,
                translation: example.translation,
              ),
            ],
          ],
        );
      case CollectionKind.sentence:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultHighlight(
              label: strings.mockQueryTranslationLabel,
              value: strings.mockQuerySentenceTranslation,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: card.examples.first
                  .split(' / ')
                  .map((part) => Chip(label: Text(part)))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(strings.mockQuerySentenceUsage, style: muted),
            const SizedBox(height: 18),
            _ResultHighlight(
              label: strings.mockQueryGrammarPoint,
              value: strings.mockQuerySentenceGrammar,
            ),
          ],
        );
      case CollectionKind.grammar:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultHighlight(
              label: strings.mockQueryGrammarCoreLabel,
              value: strings.mockQueryGrammarCore,
            ),
            const SizedBox(height: 20),
            Text(strings.mockQueryGrammarUsage, style: muted),
            const SizedBox(height: 20),
            _ResultCompare(
              label: strings.mockQueryGrammarNiLabel,
              original: card.examples[0],
              translation: strings.mockQueryGrammarNiTranslation,
              accentLabel: true,
              minHeight: 118,
            ),
            const SizedBox(height: 12),
            _ResultCompare(
              label: strings.mockQueryGrammarHeLabel,
              original: card.examples[1],
              translation: strings.mockQueryGrammarHeTranslation,
              accentLabel: true,
              minHeight: 118,
            ),
            const SizedBox(height: 20),
          ],
        );
      case CollectionKind.exercise:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultHighlight(
              label: strings.mockQueryCorrectionFocusLabel,
              value: strings.mockQueryCorrectionFocus,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ResultCompare(
                    label: strings.mockQueryCorrectionOriginalLabel,
                    original: strings.mockQueryCorrectionOriginal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResultCompare(
                    label: strings.mockQueryCorrectionSuggestedLabel,
                    original: strings.mockQueryCorrectionSuggested,
                    highlighted: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(strings.mockQueryCorrectionSentence),
            const SizedBox(height: 16),
            Text(strings.mockQueryCorrectionExplanation, style: muted),
          ],
        );
      default:
        return Text(card.explanation, style: muted);
    }
  }
}

class _ResultHighlight extends StatelessWidget {
  const _ResultHighlight({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .75),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ResultExample extends StatelessWidget {
  const _ResultExample({required this.number, required this.original, this.translation});
  final String number;
  final String original;
  final String? translation;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: TextStyle(color: colors.primary, fontSize: 12)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(original),
              if (translation != null) ...[
                const SizedBox(height: 5),
                Text(translation!, style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultCompare extends StatelessWidget {
  const _ResultCompare({
    required this.label,
    required this.original,
    this.translation,
    this.highlighted = false,
    this.accentLabel = false,
    this.minHeight,
  });
  final String label;
  final String original;
  final String? translation;
  final bool highlighted;
  final bool accentLabel;
  final double? minHeight;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: highlighted ? colors.primaryContainer : colors.surfaceContainerLow,
        border: Border.all(color: colors.outline.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accentLabel ? colors.primary : colors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            original,
            style: TextStyle(
              color: highlighted ? colors.primary : colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (translation != null) ...[
            const SizedBox(height: 8),
            Text(translation!, style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';

class NovelPlaybackSnapshot {
  const NovelPlaybackSnapshot({
    required this.sentence,
    required this.position,
    required this.total,
    required this.progress,
    required this.continuous,
    required this.paused,
    required this.finished,
    required this.speed,
  });

  final String sentence;
  final int position;
  final int total;
  final double progress;
  final bool continuous;
  final bool paused;
  final bool finished;
  final double speed;
}

/// UTF-16 offsets into the selectable source, captured before toolbar focus moves.
class NovelNativeSelection {
  const NovelNativeSelection({
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  final int startOffset;
  final int endOffset;
  final String text;
}

typedef NovelKeyboardSelectionCallback = void Function(
  int sentenceIndex,
  NovelNativeSelection? selection,
);

/// Keeps native text selection separate from the explicit sentence toolbar.
class NovelKeyboardSentence extends StatefulWidget {
  const NovelKeyboardSentence({
    required this.onOpenSelection,
    required this.child,
    this.onSelectionChanged,
    super.key,
  });

  final ValueChanged<NovelNativeSelection?> onOpenSelection;
  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<NovelKeyboardSentence> createState() => _NovelKeyboardSentenceState();
}

class _NovelKeyboardSentenceState extends State<NovelKeyboardSentence> {
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _onKeyEvent);
  final SelectionListenerNotifier _selectionNotifier = SelectionListenerNotifier();
  SelectedContent? _selectedContent;
  bool _focused = false;
  bool _focusedByPointer = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _focusedByPointer = false;
    if (mounted) setState(() => _focused = _focusNode.hasFocus && !_focusedByPointer);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        !HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    widget.onOpenSelection(_nativeSelection());
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _selectionNotifier.dispose();
    super.dispose();
  }

  NovelNativeSelection? _nativeSelection() {
    if (!_selectionNotifier.registered) return null;
    final range = _selectionNotifier.selection.range;
    final content = _selectedContent?.plainText;
    if (range == null ||
        content == null ||
        content.isEmpty ||
        range.endOffset <= range.startOffset) {
      return null;
    }
    return NovelNativeSelection(
      startOffset: range.startOffset,
      endOffset: range.endOffset,
      text: content,
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _focusedByPointer = true;
      if (_focused) setState(() => _focused = false);
      _focusNode.requestFocus();
    },
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: _focused
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectionArea(
        focusNode: _focusNode,
        onSelectionChanged: (content) {
          _selectedContent = content;
          widget.onSelectionChanged?.call(content);
        },
        child: SelectionListener(selectionNotifier: _selectionNotifier, child: widget.child),
      ),
    ),
  );
}

class NovelReadingParagraph extends StatefulWidget {
  const NovelReadingParagraph({
    required this.first,
    required this.firstIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.highlightedIndex,
    required this.selectedIndex,
    required this.onLongSentence,
    this.onKeyboardSentence,
    this.second,
    super.key,
  });

  final String first;
  final String? second;
  final int firstIndex;
  final double fontSize;
  final double lineHeight;
  final int? highlightedIndex;
  final int? selectedIndex;
  final ValueChanged<int> onLongSentence;
  final NovelKeyboardSelectionCallback? onKeyboardSentence;

  @override
  State<NovelReadingParagraph> createState() => _NovelReadingParagraphState();
}

class NovelSelectionAnchor extends StatefulWidget {
  const NovelSelectionAnchor({
    required this.selected,
    required this.toolbar,
    required this.child,
    super.key,
  });

  final bool selected;
  final Widget toolbar;
  final Widget child;

  @override
  State<NovelSelectionAnchor> createState() => _NovelSelectionAnchorState();
}

class _NovelSelectionAnchorState extends State<NovelSelectionAnchor> {
  final link = LayerLink();
  OverlayEntry? toolbarEntry;

  @override
  void didUpdateWidget(covariant NovelSelectionAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _syncToolbar();
    if (widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selected) toolbarEntry?.markNeedsBuild();
      });
    }
  }

  void _syncToolbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.selected) {
        toolbarEntry?.remove();
        toolbarEntry?.dispose();
        toolbarEntry = null;
      } else if (toolbarEntry == null) {
        toolbarEntry = OverlayEntry(
          builder: (context) => Positioned(
            left: 0,
            top: 0,
            width: 340,
            child: CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: widget.toolbar,
            ),
          ),
        );
        Overlay.of(context).insert(toolbarEntry!);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.selected) _syncToolbar();
  }

  @override
  void dispose() {
    toolbarEntry?.remove();
    toolbarEntry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(link: link, child: widget.child);
}

class _NovelReadingParagraphState extends State<NovelReadingParagraph> {
  final paragraphKey = GlobalKey();
  int? _keyboardSentenceIndex;

  void _openKeyboardSelection(NovelNativeSelection? selection) {
    final second = widget.second;
    final full = second == null ? widget.first : '${widget.first} $second';
    if (selection == null ||
        selection.startOffset < 0 ||
        selection.endOffset > full.length ||
        selection.endOffset <= selection.startOffset) {
      (widget.onKeyboardSentence ?? (index, _) => widget.onLongSentence(index))(
        _keyboardSentenceIndex ?? widget.firstIndex,
        null,
      );
      return;
    }
    final secondStart = widget.first.length + 1;
    final inSecond = second != null && selection.startOffset >= secondStart;
    final index = inSecond ? widget.firstIndex + 1 : widget.firstIndex;
    final origin = inSecond ? secondStart : 0;
    (widget.onKeyboardSentence ?? (value, _) => widget.onLongSentence(value))(
      index,
      NovelNativeSelection(
        startOffset: selection.startOffset - origin,
        endOffset: selection.endOffset - origin,
        text: full.substring(selection.startOffset, selection.endOffset),
      ),
    );
  }

  int _indexAt(Offset position) {
    final paragraph = paragraphKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return widget.firstIndex;
    final offset = paragraph.getPositionForOffset(position).offset;
    return widget.second != null && offset > widget.first.length
        ? widget.firstIndex + 1
        : widget.firstIndex;
  }

  @override
  Widget build(BuildContext context) {
    final roles = HarukaColors.of(context);
    final green = roles.bookGreen.withValues(alpha: .48);
    final firstStyle = TextStyle(
      backgroundColor: widget.highlightedIndex == widget.firstIndex
          ? green
          : widget.selectedIndex == widget.firstIndex
          ? roles.selected
          : null,
    );
    final secondStyle = TextStyle(
      backgroundColor: widget.highlightedIndex == widget.firstIndex + 1
          ? green
          : widget.selectedIndex == widget.firstIndex + 1
          ? roles.selected
          : null,
    );
    return NovelKeyboardSentence(
      onOpenSelection: _openKeyboardSelection,
      child: Builder(
        builder: (selectionContext) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _keyboardSentenceIndex = _indexAt(details.localPosition),
          onLongPressStart: (details) {
            final index = _indexAt(details.localPosition);
            _keyboardSentenceIndex = index;
            widget.onLongSentence(index);
          },
          child: RichText(
            key: paragraphKey,
            selectionRegistrar: SelectionContainer.maybeOf(selectionContext),
            selectionColor: Theme.of(selectionContext).colorScheme.primary.withValues(alpha: .28),
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: widget.fontSize,
                height: widget.lineHeight,
                fontFamily: 'serif',
              ),
              children: [
                TextSpan(text: widget.first, style: firstStyle),
                if (widget.second != null) ...[
                  const TextSpan(text: ' '),
                  TextSpan(text: widget.second, style: secondStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NovelSelectionToolbar extends StatelessWidget {
  const NovelSelectionToolbar({
    required this.compact,
    required this.tokens,
    required this.selectedTokens,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onToken,
    required this.onStart,
    required this.onEnd,
    required this.onRead,
    required this.onQuery,
    required this.onClose,
    this.nativeSelectionText,
    super.key,
  });

  final bool compact;
  final List<String> tokens;
  final Set<int> selectedTokens;
  final int rangeStart;
  final int rangeEnd;
  final ValueChanged<int> onToken;
  final ValueChanged<int> onStart;
  final ValueChanged<int> onEnd;
  final VoidCallback onRead;
  final VoidCallback onQuery;
  final VoidCallback onClose;
  final String? nativeSelectionText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final selected = selectedTokens.toList()..sort();
    final scope =
        nativeSelectionText ??
        (selected.isEmpty
            ? l10n.mockMaterialNovelSelectionWholeSentence
            : selected.map((index) => tokens[index]).join(' / '));
    return _NovelToolbarFocus(
      child: Material(
        color: scheme.surface,
        elevation: 8,
        shadowColor: roles.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outline),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    l10n.mockMaterialNovelSelectionTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.mockMaterialNovelReadSentence,
                    onPressed: onRead,
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                  IconButton(
                    tooltip: l10n.mockMaterialClose,
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 7,
                children: [
                  for (var index = rangeStart; index <= rangeEnd; index++)
                    if (RegExp(r'^[、。！？,.!?]+$').hasMatch(tokens[index]))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                        child: Text(tokens[index]),
                      )
                    else
                      FilterChip(
                        label: Text(tokens[index]),
                        selected: selectedTokens.contains(index),
                        onSelected: (_) => onToken(index),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.primaryContainer.withValues(alpha: .38),
                        selectedColor: roles.selected,
                        side: BorderSide(color: scheme.primary.withValues(alpha: .08)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scope,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onQuery,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(l10n.mockMaterialQuery),
                    style: TextButton.styleFrom(
                      backgroundColor: scheme.primaryContainer.withValues(alpha: .55),
                      foregroundColor: scheme.primary,
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                key: const PageStorageKey('novel-selection-range'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  l10n.mockMaterialNovelAdjustRange,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          key: ValueKey('novel-range-start-$rangeStart'),
                          initialValue: rangeStart,
                          decoration: InputDecoration(labelText: l10n.mockMaterialNovelRangeStart),
                          items: [
                            for (var index = 0; index <= rangeEnd; index++)
                              DropdownMenuItem(
                                value: index,
                                child: Text(
                                  l10n.mockMaterialNovelBoundaryOption(index + 1, tokens[index]),
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) onStart(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          key: ValueKey('novel-range-end-$rangeEnd'),
                          initialValue: rangeEnd,
                          decoration: InputDecoration(labelText: l10n.mockMaterialNovelRangeEnd),
                          items: [
                            for (var index = rangeStart; index < tokens.length; index++)
                              DropdownMenuItem(
                                value: index,
                                child: Text(
                                  l10n.mockMaterialNovelBoundaryOption(index + 1, tokens[index]),
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) onEnd(value);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NovelToolbarFocus extends StatefulWidget {
  const _NovelToolbarFocus({required this.child});

  final Widget child;

  @override
  State<_NovelToolbarFocus> createState() => _NovelToolbarFocusState();
}

class _NovelToolbarFocusState extends State<_NovelToolbarFocus> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    key: const ValueKey('novel-selection-toolbar-focus'),
    focusNode: _focusNode,
    child: widget.child,
  );
}

class MobileNovelPlaybackPanel extends StatelessWidget {
  const MobileNovelPlaybackPanel({
    required this.sentence,
    required this.position,
    required this.total,
    required this.progress,
    required this.continuous,
    required this.paused,
    required this.finished,
    required this.speed,
    required this.onPauseResume,
    required this.onSpeed,
    required this.onStop,
    super.key,
  });

  final String sentence;
  final int position;
  final int total;
  final double progress;
  final bool continuous;
  final bool paused;
  final bool finished;
  final double speed;
  final VoidCallback onPauseResume;
  final ValueChanged<double> onSpeed;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 9,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  continuous
                      ? l10n.mockMaterialContinuousPlayback
                      : l10n.mockMaterialNovelReadSentence,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  finished
                      ? l10n.mockMaterialTextbookPlaybackFinished
                      : paused
                      ? l10n.mockMaterialTextbookPlaybackPaused
                      : l10n.mockMaterialTextbookPlaybackPlaying,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(sentence, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  continuous
                      ? l10n.mockMaterialSentencePosition(position, total)
                      : l10n.mockMaterialTextbookPlaybackOnce,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: .12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onPauseResume,
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(
                      finished
                          ? l10n.mockMaterialTextbookPlaybackReplay
                          : paused
                          ? l10n.mockMaterialTextbookPlaybackResume
                          : l10n.mockMaterialTextbookPlaybackPause,
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButton<double>(
                    value: speed,
                    isExpanded: true,
                    items: [
                      for (final value in const [0.7, 1.0, 1.2, 1.5])
                        DropdownMenuItem(value: value, child: Text('${value.toStringAsFixed(1)}×')),
                    ],
                    onChanged: (value) {
                      if (value != null) onSpeed(value);
                    },
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.mockMaterialTextbookPlaybackStop),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopNovelPlaybackPanel extends StatelessWidget {
  const DesktopNovelPlaybackPanel({
    required this.sentence,
    required this.position,
    required this.total,
    required this.progress,
    required this.continuous,
    required this.paused,
    required this.finished,
    required this.speed,
    required this.onPauseResume,
    required this.onSpeed,
    required this.onStop,
    super.key,
  });

  final String sentence;
  final int position;
  final int total;
  final double progress;
  final bool continuous;
  final bool paused;
  final bool finished;
  final double speed;
  final VoidCallback onPauseResume;
  final ValueChanged<double> onSpeed;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return HarukaSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                continuous
                    ? l10n.mockMaterialContinuousPlayback
                    : l10n.mockMaterialNovelReadSentence,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                finished
                    ? l10n.mockMaterialTextbookPlaybackFinished
                    : paused
                    ? l10n.mockMaterialTextbookPlaybackPaused
                    : l10n.mockMaterialTextbookPlaybackPlaying,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(sentence, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                continuous
                    ? l10n.mockMaterialSentencePosition(position, total)
                    : l10n.mockMaterialTextbookPlaybackOnce,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  color: scheme.primary,
                  backgroundColor: scheme.primary.withValues(alpha: .12),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: finished
                    ? l10n.mockMaterialTextbookPlaybackReplay
                    : paused
                    ? l10n.mockMaterialTextbookPlaybackResume
                    : l10n.mockMaterialTextbookPlaybackPause,
                onPressed: onPauseResume,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              ),
              DropdownButton<double>(
                value: speed,
                items: [
                  for (final value in const [0.7, 1.0, 1.2, 1.5])
                    DropdownMenuItem(value: value, child: Text('${value.toStringAsFixed(1)}×')),
                ],
                onChanged: (value) {
                  if (value != null) onSpeed(value);
                },
              ),
              IconButton(
                tooltip: l10n.mockMaterialTextbookPlaybackStop,
                onPressed: onStop,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NovelSelectionResultBody extends StatelessWidget {
  const NovelSelectionResultBody({
    required this.selectedText,
    required this.source,
    required this.card,
    required this.onSave,
    super.key,
  });

  final String selectedText;
  final String source;
  final LearningCard? card;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final store = PreviewStoreScope.of(context);
    final saved = card != null && store.collections.any((item) => item.displayText == card!.title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(source, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 10),
        Text(selectedText, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        if (card == null)
          Text(
            l10n.mockMaterialNovelNoQueryResult,
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else if (card!.kind == CollectionKind.word)
          _NovelWordResultCard(
            card: card!,
            reading: card!.title == l10n.mockMaterialNovelWindowWord
                ? l10n.mockMaterialNovelWindowReading
                : null,
            saved: saved,
            onSave: onSave,
          )
        else ...[
          HarukaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card!.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(card!.explanation),
                for (final example in card!.examples) ...[
                  const SizedBox(height: 8),
                  Text(example, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saved ? null : onSave,
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_add_outlined),
            label: Text(
              saved ? l10n.mockMaterialCollectedSentence : l10n.mockMaterialCollectSentence,
            ),
          ),
        ],
      ],
    );
  }
}

class _NovelWordResultCard extends StatelessWidget {
  const _NovelWordResultCard({
    required this.card,
    required this.reading,
    required this.saved,
    required this.onSave,
  });

  final LearningCard card;
  final String? reading;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return HarukaSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.primaryContainer.withValues(alpha: .34),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, color: scheme.primary, size: 18),
                const SizedBox(width: 9),
                Text(
                  l10n.mockQueryCardKindWord,
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  l10n.mockQueryLanguage,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(card.title, style: Theme.of(context).textTheme.headlineSmall),
                if (reading != null) ...[
                  const SizedBox(height: 3),
                  Text(reading!, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .58),
                    border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.mockQueryMeaningLabel,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      Text(card.explanation, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                for (final example in card.examples) ...[
                  const SizedBox(height: 11),
                  Text(example, style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 17),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: saved ? null : onSave,
                    icon: Icon(saved ? Icons.bookmark : Icons.bookmark_add_outlined),
                    label: Text(
                      saved ? l10n.mockMaterialCollectedSentence : l10n.mockMaterialCollectSentence,
                    ),
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

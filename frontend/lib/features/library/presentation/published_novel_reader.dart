import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/api/learning_models.dart' as published;
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/features/collections/reference_feature_scope.dart';
import 'package:haruka/features/collections/reference_selection.dart';
import 'package:haruka/features/novels/presentation/selection_overlay.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';

import 'material_pages.dart';

/// A state/data adapter for the confirmed Flutter reader views. Published
/// metadata stays in its own DTO; unsupported preview actions are not faked.
class PublishedNovelReader extends StatefulWidget {
  const PublishedNovelReader({required this.materialId, required this.reference, super.key});

  final String materialId;
  final ReferenceController reference;

  @override
  State<PublishedNovelReader> createState() => _PublishedNovelReaderState();
}

class _PublishedNovelReaderState extends State<PublishedNovelReader> {
  late String _openingScope;
  String? _requestedChapterKey;
  int? _selectedIndex;
  double _fontSize = 18;
  int _resolveIntent = 0;
  bool _lookupComplete = false;

  void _scheduleLookup() {
    final reference = widget.reference;
    final materialId = widget.materialId;
    final openingScope = _openingScope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.reference != reference || widget.materialId != materialId) return;
      unawaited(() async {
        await reference.ensureMaterial(materialId);
        if (mounted &&
            widget.reference == reference &&
            widget.materialId == materialId &&
            _openingScope == openingScope) {
          setState(() => _lookupComplete = true);
        }
      }());
    });
  }

  @override
  void initState() {
    super.initState();
    _openingScope = referenceScope(widget.reference.auth, 'reference');
    _scheduleLookup();
  }

  @override
  void didUpdateWidget(covariant PublishedNovelReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference || oldWidget.materialId != widget.materialId) {
      _openingScope = referenceScope(widget.reference.auth, 'reference');
      _requestedChapterKey = null;
      _selectedIndex = null;
      _lookupComplete = false;
      _scheduleLookup();
    }
  }

  void _select(published.NovelBlock block, int index, NovelNativeSelection? native) {
    if (referenceScope(widget.reference.auth, 'reference') != _openingScope) return;
    final selection = ReferenceSelection.fromTextSelection(
      block,
      native == null
          ? TextSelection(baseOffset: 0, extentOffset: block.text.length)
          : TextSelection(baseOffset: native.startOffset, extentOffset: native.endOffset),
    );
    if (selection == null) return;
    final previous = widget.reference.selectedSelection;
    if (previous?.block.id == selection.block.id &&
        previous?.locator.span.start == selection.locator.span.start &&
        previous?.locator.span.end == selection.locator.span.end &&
        _selectedIndex == index) {
      return;
    }
    widget.reference.select(selection);
    setState(() => _selectedIndex = index);
  }

  Future<void> _resolve() async {
    final reference = widget.reference;
    final selection = reference.selectedSelection;
    if (reference.busy ||
        selection == null ||
        referenceScope(reference.auth, 'reference') != _openingScope) {
      return;
    }
    final intent = ++_resolveIntent;
    await reference.resolve();
    if (!mounted ||
        intent != _resolveIntent ||
        widget.reference != reference ||
        !identical(reference.selectedSelection, selection) ||
        referenceScope(reference.auth, 'reference') != _openingScope ||
        reference.resolved == null) {
      return;
    }
    await showResolvedWordDetail(context, reference);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.reference.auth,
    builder: (context, _) {
      if (!widget.reference.auth.isAuthenticated ||
          referenceScope(widget.reference.auth, 'reference') != _openingScope) {
        return const SizedBox.shrink();
      }
      return ListenableBuilder(
        listenable: widget.reference,
        builder: (context, _) => _buildCurrent(context),
      );
    },
  );

  Widget _buildCurrent(BuildContext context) {
    final reference = widget.reference;
    final item = reference.materials.where((row) => row.id == widget.materialId).firstOrNull;
    if (item == null) {
      final text = !_lookupComplete
          ? const CircularProgressIndicator()
          : reference.materialError == null
          ? Text(AppLocalizations.of(context).mockMaterialUnavailableMessage)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context).authUnavailableShort),
                TextButton(
                  onPressed: () {
                    setState(() => _lookupComplete = false);
                    _scheduleLookup();
                  },
                  child: Text(AppLocalizations.of(context).referenceRetry),
                ),
              ],
            );
      return PreviewPageFrame(
        location: AppRoutes.materialPath(widget.materialId),
        title: AppLocalizations.of(context).mockMaterialUnavailableTitle,
        detail: true,
        desktopBackLabel: AppLocalizations.of(context).mockShellBack,
        onBack: () => context.go(AppRoutes.materials),
        mobile: Center(child: text),
        desktop: Center(child: text),
      );
    }
    final chapterKey = '${item.id}:${item.revisionId}:${item.firstChapterId}';
    if (_requestedChapterKey != chapterKey) {
      _requestedChapterKey = chapterKey;
      _selectedIndex = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _requestedChapterKey == chapterKey) {
          unawaited(reference.openMaterial(item));
        }
      });
    }
    final chapter =
        reference.material?.id == item.id && reference.material?.revisionId == item.revisionId
        ? reference.chapter
        : null;
    if (chapter == null) {
      final child = Center(
        child: reference.busy
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context).authUnavailableShort),
                  TextButton(
                    onPressed: () => unawaited(reference.openMaterial(item)),
                    child: Text(AppLocalizations.of(context).referenceRetry),
                  ),
                ],
              ),
      );
      return PreviewPageFrame(
        location: AppRoutes.materialPath(item.id),
        title: item.title,
        detail: true,
        desktopBackLabel: AppLocalizations.of(context).mockShellBack,
        onBack: () => context.go(AppRoutes.materials),
        mobile: child,
        desktop: child,
      );
    }
    final blocks = chapter.blocks.toList()
      ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
    final view = PublishedNovelViewData(
      item: item,
      chapter: chapter,
      blocks: blocks,
      reference: reference,
      openingScope: _openingScope,
      selectedIndex: _selectedIndex,
      selectedText: reference.selectedSelection?.locator.quote,
      fontSize: _fontSize,
      onWholeBlock: (index) => _select(blocks[index], index, null),
      onNativeSelection: (index, selection) => _select(blocks[index], index, selection),
      onQuery: () => unawaited(_resolve()),
      onClear: () {
        reference.select(null);
        setState(() => _selectedIndex = null);
      },
      onFont: (value) => setState(() => _fontSize = value),
    );
    return PreviewPageFrame(
      location: AppRoutes.materialPath(item.id),
      title: item.title,
      detail: true,
      detailNotifications: false,
      desktopBackLabel: AppLocalizations.of(context).mockShellBack,
      mobileBackground: Theme.of(context).colorScheme.surface,
      onBack: () => context.go(AppRoutes.materials),
      mobile: MobileNovelView.published(data: view),
      desktop: DesktopNovelView.published(data: view),
    );
  }
}

class PublishedNovelViewData {
  const PublishedNovelViewData({
    required this.item,
    required this.chapter,
    required this.blocks,
    required this.reference,
    required this.openingScope,
    required this.selectedIndex,
    required this.selectedText,
    required this.fontSize,
    required this.onWholeBlock,
    required this.onNativeSelection,
    required this.onQuery,
    required this.onClear,
    required this.onFont,
  });

  final published.MaterialSummary item;
  final published.NovelChapter chapter;
  final List<published.NovelBlock> blocks;
  final ReferenceController reference;
  final String openingScope;
  final int? selectedIndex;
  final String? selectedText;
  final double fontSize;
  final ValueChanged<int> onWholeBlock;
  final NovelKeyboardSelectionCallback onNativeSelection;
  final VoidCallback onQuery;
  final VoidCallback onClear;
  final ValueChanged<double> onFont;
}

void showPublishedContents(BuildContext context, PublishedNovelViewData data) {
  final l10n = AppLocalizations.of(context);
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(context),
      builder: (sheetContext) => ReferenceDialogGuard(
        controller: data.reference,
        openingScope: data.openingScope,
        allowed: () => data.reference.auth.access?.allows('client.material.read') == true,
        child: ListTile(
          title: Text(data.chapter.title),
          subtitle: Text(l10n.mockMaterialContentsTooltip),
          onTap: () => Navigator.pop(sheetContext),
        ),
      ),
    ),
  );
}

void showPublishedFont(BuildContext context, PublishedNovelViewData data) {
  var selected = data.fontSize;
  unawaited(
    showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context),
      builder: (dialogContext) => ReferenceDialogGuard(
        controller: data.reference,
        openingScope: data.openingScope,
        allowed: () => data.reference.auth.access?.allows('client.material.read') == true,
        child: HarukaDialogSurface(
          title: AppLocalizations.of(dialogContext).mockMaterialReadingFontSize,
          size: HarukaDialogSize.compact,
          child: StatefulBuilder(
            builder: (context, update) => ReaderFontControl(
              value: selected,
              preview: data.item.title,
              onChanged: (value) {
                update(() => selected = value);
                data.onFont(value);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

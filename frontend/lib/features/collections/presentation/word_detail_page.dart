import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/app/preview_shell.dart';

import 'collection_catalog_scope.dart';
import 'collection_catalog_access.dart';
import 'collection_overlay_read.dart';
import '../data/collection_catalog.dart';

/// A collection detail uses the same API shaped item as the notebook list.
/// The two layouts share only the item and actions; their presentation differs.
class WordDetailPage extends StatefulWidget {
  const WordDetailPage({required this.itemId, super.key});

  final String itemId;

  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  @override
  Widget build(BuildContext context) => CollectionCatalogAccess(
    allCollections: true,
    builder: (context, catalog) => _buildContent(context, catalog),
  );

  Widget _buildContent(BuildContext context, CollectionCatalog catalog) {
    final item = catalog.findCollection(widget.itemId);
    final l10n = AppLocalizations.of(context);
    if (item == null) {
      return PreviewPageFrame(
        location: AppRoutes.mockNotebooks,
        title: l10n.mockLearningWordTitle,
        detail: true,
        detailNotifications: false,
        mobile: Center(child: Text(l10n.mockSupportCollectionDeleted)),
        desktop: Center(child: Text(l10n.mockSupportCollectionDeleted)),
      );
    }

    return PreviewPageFrame(
      location: AppRoutes.mockCollectionPath(item.id),
      title: l10n.mockLearningWordTitle,
      detail: true,
      detailNotifications: false,
      mobile: MobileWordDetailView(
        item: item,
        onSpeak: () => _WordDetailActions.speak(context),
        onNotebooks: () => _WordDetailActions.editNotebooks(context, item),
        onEdit: () => _WordDetailActions.editWord(context, item),
        onSource: () => _WordDetailActions.openSource(context, item),
      ),
      desktop: DesktopWordDetailView(
        item: item,
        onSpeak: () => _WordDetailActions.speak(context),
        onNotebooks: () => _WordDetailActions.editNotebooks(context, item),
        onEdit: () => _WordDetailActions.editWord(context, item),
        onSource: () => _WordDetailActions.openSource(context, item),
      ),
    );
  }
}

/// Opens word detail in one centered dialog on both screen sizes.
Future<void> showWordDetail(BuildContext context, String itemId) async {
  final router = GoRouter.of(context);
  TransitionRoute<dynamic>? overlayRoute;
  Future<void> openAfterDismissal(String? destination) async {
    if (destination == null) return;
    await overlayRoute?.completed;
    if (context.mounted) router.go(destination);
  }

  final catalog = CollectionCatalogScope.of(context);
  final scopeGeneration = catalog.scopeGeneration;
  final item = await readCollectionForOverlay(catalog, itemId);
  if (!context.mounted) return;
  if (catalog.scopeGeneration != scopeGeneration || item == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
    return;
  }
  final destination = await showHarukaDialog<String>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
    ),
    builder: (dialogContext) {
      overlayRoute = ModalRoute.of(dialogContext) as TransitionRoute<dynamic>?;
      return Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight:
                (MediaQuery.sizeOf(dialogContext).height -
                    MediaQuery.viewInsetsOf(dialogContext).bottom) *
                .85,
          ),
          child: WordDetailDialog(itemId: itemId),
        ),
      );
    },
  );
  await openAfterDismissal(destination);
}

/// Can also be embedded by a caller that owns the modal route itself.
class WordDetailDialog extends StatefulWidget {
  const WordDetailDialog({required this.itemId, super.key});
  final String itemId;

  @override
  State<WordDetailDialog> createState() => _WordDetailDialogState();
}

class _WordDetailDialogState extends State<WordDetailDialog> {
  final _detailScroll = ScrollController();
  double _detailOffset = 0;
  int _mode = 0;

  @override
  void dispose() {
    _detailScroll.dispose();
    super.dispose();
  }

  void _showMode(int mode) {
    if (_mode == 0 && _detailScroll.hasClients) _detailOffset = _detailScroll.offset;
    setState(() => _mode = mode);
    if (mode == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_detailScroll.hasClients) return;
        _detailScroll.jumpTo(_detailOffset.clamp(0, _detailScroll.position.maxScrollExtent));
      });
    }
  }

  Future<bool> _saveNotebooks(CollectionEntry item, Set<String> selected) async {
    try {
      await CollectionCatalogScope.of(context).setCollectionNotebooks(item.id, selected);
      if (mounted) _showMode(0);
      return true;
    } on Object {
      if (mounted) _showUnavailable();
      return false;
    }
  }

  Future<bool> _saveWord(CollectionEntry item, _WordEdit edit) async {
    try {
      await CollectionCatalogScope.of(context).updateCollection(
        item.id,
        displayText: edit.displayText,
        meaning: edit.meaning,
        notes: edit.notes,
      );
      if (mounted) _showMode(0);
      return true;
    } on Object {
      if (mounted) _showUnavailable();
      return false;
    }
  }

  void _showUnavailable() =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));

  @override
  Widget build(BuildContext context) {
    final item = CollectionCatalogScope.of(context).findCollection(widget.itemId);
    if (item == null) {
      return Center(child: Text(AppLocalizations.of(context).mockSupportCollectionDeleted));
    }
    final strings = AppLocalizations.of(context);
    final heading = switch (_mode) {
      1 => strings.mockLearningWordEditTitle,
      2 => strings.mockSupportAssignToNotebook,
      _ => strings.mockLearningWordTitle,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
          child: Row(
            children: [
              if (_mode != 0)
                IconButton(
                  tooltip: strings.mockSupportCancel,
                  onPressed: () => _showMode(0),
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(child: Text(heading, style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: switch (_mode) {
            1 => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: _WordEditFields(
                key: ValueKey(('edit', item.id, item.revision)),
                item: item,
                onSave: (edit) => _saveWord(item, edit),
              ),
            ),
            2 => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: _NotebookSelection(
                key: ValueKey(('notebooks', item.id, item.revision)),
                item: item,
                onSave: (selected) => _saveNotebooks(item, selected),
              ),
            ),
            _ => ListView(
              controller: _detailScroll,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              children: [
                _WordContent(item: item, onSpeak: () => _WordDetailActions.speak(context)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showMode(2),
                    icon: const Icon(Icons.bookmarks_outlined),
                    label: Text(strings.mockSupportAssignToNotebook),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showMode(1),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(strings.mockSupportEditNotes),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      final destination = _WordDetailActions.sourcePath(context, item);
                      Navigator.pop(context, destination);
                    },
                    child: Text(strings.mockLearningWordBackToSource),
                  ),
                ),
              ],
            ),
          },
        ),
      ],
    );
  }
}

abstract final class _WordDetailActions {
  static void speak(BuildContext context) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockSupportAudioUnavailable)));

  static String sourcePath(BuildContext context, CollectionEntry item) {
    final store = PreviewStoreScope.of(context);
    final sourceId = item.sourceMaterialId;
    if (sourceId == null || !store.materials.any((material) => material.id == sourceId)) {
      return AppRoutes.mockLibrary;
    }
    return AppRoutes.mockMaterialPath(sourceId);
  }

  static void openSource(BuildContext context, CollectionEntry item) =>
      context.go(sourcePath(context, item));

  static Future<void> editNotebooks(BuildContext context, CollectionEntry item) async {
    final catalog = CollectionCatalogScope.of(context);
    final selected = await _showLearningPanel<Set<String>>(
      context,
      title: AppLocalizations.of(context).mockSupportAssignToNotebook,
      child: _NotebookSelection(item: item),
    );
    if (selected == null || !context.mounted) return;
    try {
      await catalog.setCollectionNotebooks(item.id, selected);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    }
  }

  static Future<void> editWord(BuildContext context, CollectionEntry item) async {
    final catalog = CollectionCatalogScope.of(context);
    final edit = await _showLearningPanel<_WordEdit>(
      context,
      title: AppLocalizations.of(context).mockLearningWordEditTitle,
      child: _WordEditFields(item: item),
    );
    if (edit == null || !context.mounted) return;
    try {
      await catalog.updateCollection(
        item.id,
        displayText: edit.displayText,
        meaning: edit.meaning,
        notes: edit.notes,
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    }
  }
}

class MobileWordDetailView extends StatelessWidget {
  const MobileWordDetailView({
    required this.item,
    required this.onSpeak,
    required this.onNotebooks,
    required this.onEdit,
    required this.onSource,
    super.key,
  });

  final CollectionEntry item;
  final VoidCallback onSpeak;
  final VoidCallback onNotebooks;
  final VoidCallback onEdit;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
    children: [
      HarukaSurface(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WordContent(item: item, onSpeak: onSpeak),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onNotebooks,
                icon: const Icon(Icons.bookmarks_outlined),
                label: Text(AppLocalizations.of(context).mockSupportAssignToNotebook),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(AppLocalizations.of(context).mockSupportEditNotes),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onSource,
                child: Text(AppLocalizations.of(context).mockLearningWordBackToSource),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class DesktopWordDetailView extends StatelessWidget {
  const DesktopWordDetailView({
    required this.item,
    required this.onSpeak,
    required this.onNotebooks,
    required this.onEdit,
    required this.onSource,
    super.key,
  });

  final CollectionEntry item;
  final VoidCallback onSpeak;
  final VoidCallback onNotebooks;
  final VoidCallback onEdit;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: HarukaSurface(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).mockLearningWordTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 22),
              _WordContent(item: item, onSpeak: onSpeak),
              const SizedBox(height: 22),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  OutlinedButton.icon(
                    onPressed: onNotebooks,
                    icon: const Icon(Icons.bookmarks_outlined),
                    label: Text(AppLocalizations.of(context).mockSupportAssignToNotebook),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(AppLocalizations.of(context).mockSupportEditNotes),
                  ),
                  TextButton(
                    onPressed: onSource,
                    child: Text(AppLocalizations.of(context).mockLearningWordBackToSource),
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

class _WordContent extends StatelessWidget {
  const _WordContent({required this.item, required this.onSpeak});
  final CollectionEntry item;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final catalog = CollectionCatalogScope.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final date = item.createdAt.toLocal();
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mockSupportKindLanguage(
            collectionKindLabel(context, item.kind),
            collectionLanguageLabel(context, item.targetLanguage),
          ),
          style: TextStyle(color: colors.primary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(item.displayText, style: Theme.of(context).textTheme.headlineMedium),
            ),
            IconButton(
              tooltip: l10n.mockSupportSpeakWord(item.displayText),
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_outlined),
            ),
          ],
        ),
        if (item.reading != null)
          Text(item.reading!, style: TextStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: roles.selected, borderRadius: BorderRadius.circular(12)),
          child: Text(item.meaning, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (item.context != null) ...[
          const Divider(height: 39),
          Text(
            l10n.mockSupportCollectionContextExamples,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('01', style: TextStyle(color: colors.primary)),
              const SizedBox(width: 10),
              Expanded(child: Text(item.context!)),
            ],
          ),
        ],
        if (item.sourceTitle != null) ...[
          const SizedBox(height: 22),
          Text(
            l10n.mockLearningWordSourceDate(item.sourceTitle!, dateText),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 15),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            Chip(
              label: Text(l10n.mockLearningWordMastery),
              backgroundColor: roles.selected,
              labelStyle: TextStyle(color: colors.primary),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
            for (final book in catalog.notebooks.where(
              (book) => item.notebookIds.contains(book.id),
            ))
              Chip(
                label: Text(book.name),
                backgroundColor: roles.selected,
                labelStyle: TextStyle(color: colors.primary),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 15),
          Text(l10n.mockSupportPersonalNotes, style: Theme.of(context).textTheme.titleSmall),
          Text(item.notes),
        ],
      ],
    );
  }
}

class _NotebookSelection extends StatefulWidget {
  const _NotebookSelection({required this.item, this.onSave, super.key});
  final CollectionEntry item;
  final Future<bool> Function(Set<String> selected)? onSave;
  @override
  State<_NotebookSelection> createState() => _NotebookSelectionState();
}

class _NotebookSelectionState extends State<_NotebookSelection> {
  late final selected = {...widget.item.notebookIds};
  bool saving = false;

  Future<void> _submit() async {
    if (saving) return;
    if (widget.onSave == null) {
      Navigator.pop(context, selected);
      return;
    }
    setState(() => saving = true);
    await widget.onSave!(selected);
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CollectionCatalogScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final book in catalog.notebooks.where(
          (book) => book.targetLanguage == widget.item.targetLanguage,
        ))
          CheckboxListTile(
            value: selected.contains(book.id),
            title: Text(book.name),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (checked) => setState(() {
              if (checked == true) {
                selected.add(book.id);
              } else {
                selected.remove(book.id);
              }
            }),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: saving ? null : _submit,
            child: Text(AppLocalizations.of(context).mockLearningWordNotebookSave),
          ),
        ),
      ],
    );
  }
}

final class _WordEdit {
  const _WordEdit(this.displayText, this.meaning, this.notes);
  final String displayText;
  final String meaning;
  final String notes;
}

class _WordEditFields extends StatefulWidget {
  const _WordEditFields({required this.item, this.onSave, super.key});
  final CollectionEntry item;
  final Future<bool> Function(_WordEdit edit)? onSave;
  @override
  State<_WordEditFields> createState() => _WordEditFieldsState();
}

class _WordEditFieldsState extends State<_WordEditFields> {
  late final content = TextEditingController(text: widget.item.displayText);
  late final meaning = TextEditingController(text: widget.item.meaning);
  late final notes = TextEditingController(text: widget.item.notes);
  bool saving = false;

  Future<void> _submit() async {
    if (saving || content.text.trim().isEmpty || meaning.text.trim().isEmpty) return;
    final edit = _WordEdit(content.text.trim(), meaning.text.trim(), notes.text.trim());
    if (widget.onSave == null) {
      Navigator.pop(context, edit);
      return;
    }
    setState(() => saving = true);
    await widget.onSave!(edit);
    if (mounted) setState(() => saving = false);
  }

  @override
  void dispose() {
    content.dispose();
    meaning.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        controller: content,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).mockSupportCollectionContentField,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: meaning,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).mockSupportCollectionMeaningField,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: notes,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).mockSupportPersonalNotes,
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: saving ? null : _submit,
          child: Text(AppLocalizations.of(context).mockSupportSave),
        ),
      ),
    ],
  );
}

Future<T?> _showLearningPanel<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  final compact = MediaQuery.sizeOf(context).width < 760;
  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelHeading(title: title),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
  return showHarukaDialog<T>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
    ),
    builder: (dialogContext) => AlertDialog(
      title: _PanelHeading(title: title),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: child)),
    ),
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ],
  );
}

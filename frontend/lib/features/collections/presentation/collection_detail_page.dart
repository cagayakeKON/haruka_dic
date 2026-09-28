import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haruka/app/motion.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';

import 'collection_catalog_scope.dart';
import 'collection_catalog_access.dart';
import 'collection_overlay_read.dart';
import '../data/collection_catalog.dart';

import 'package:haruka/features/collections/presentation/notebook_pages.dart';

class CollectionDetailPage extends StatefulWidget {
  const CollectionDetailPage({required this.itemId, this.overlay = false, super.key});
  final String itemId;
  final bool overlay;
  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  final _detailScroll = ScrollController();
  int _overlayMode = 0;
  double _detailOffset = 0;

  void _showOverlayMode(int mode) {
    if (_overlayMode == 0 && _detailScroll.hasClients) {
      _detailOffset = _detailScroll.offset;
    }
    setState(() => _overlayMode = mode);
    if (mode == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_detailScroll.hasClients) return;
        _detailScroll.jumpTo(
          _detailOffset.clamp(
            _detailScroll.position.minScrollExtent,
            _detailScroll.position.maxScrollExtent,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _detailScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.overlay
      ? _buildContent(context, CollectionCatalogScope.of(context))
      : CollectionCatalogAccess(
          allCollections: true,
          builder: (context, catalog) => _buildContent(context, catalog),
        );

  Widget _buildContent(BuildContext context, CollectionCatalog catalog) {
    final item = catalog.findCollection(widget.itemId);
    if (item == null) {
      return Center(child: Text(AppLocalizations.of(context).mockSupportCollectionDeleted));
    }
    final sourceId = item.sourceMaterialId;
    final hasSource =
        sourceId != null &&
        PreviewStoreScope.of(context).materials.any((material) => material.id == sourceId);
    final content = HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).mockSupportKindLanguage(
              collectionKindLabel(context, item.kind),
              collectionLanguageLabel(context, item.targetLanguage),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(item.displayText, style: Theme.of(context).textTheme.headlineMedium),
              ),
              if (item.kind == CollectionKind.word)
                IconButton(
                  tooltip: AppLocalizations.of(context).mockSupportSpeakWord(item.displayText),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context).mockSupportAudioUnavailable),
                    ),
                  ),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
            ],
          ),
          if (item.reading != null)
            Text(
              item.reading!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: HarukaColors.of(context).selected,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(item.meaning, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (item.context != null) ...[
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).mockSupportCollectionContextExamples),
            const SizedBox(height: 8),
            Text(item.context!),
          ],
          const SizedBox(height: 20),
          if (item.sourceTitle != null)
            Text(
              item.sourceTitle!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: widget.overlay
                ? () => _showOverlayMode(2)
                : () => _chooseNotebooks(context, item),
            icon: const Icon(Icons.bookmarks_outlined),
            label: Text(AppLocalizations.of(context).mockSupportAssignToNotebook),
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: widget.overlay
                ? () => _showOverlayMode(1)
                : () => _editCollection(context, item),
            icon: const Icon(Icons.edit_outlined),
            label: Text(AppLocalizations.of(context).mockSupportEditNotes),
          ),
          const SizedBox(height: 9),
          TextButton(
            onPressed: !hasSource
                ? null
                : () {
                    final path = AppRoutes.mockMaterialPath(sourceId);
                    if (widget.overlay) {
                      Navigator.of(context, rootNavigator: true).pop(path);
                    } else {
                      context.go(path);
                    }
                  },
            child: Text(AppLocalizations.of(context).mockSupportReturnToSource),
          ),
        ],
      ),
    );
    if (widget.overlay) {
      final strings = AppLocalizations.of(context);
      final heading = switch (_overlayMode) {
        1 => strings.mockSupportEditNotes,
        2 => strings.mockSupportAssignToNotebook,
        _ => strings.mockSupportCollectionDetailTitle,
      };
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                if (_overlayMode != 0)
                  IconButton(
                    tooltip: strings.mockSupportCancel,
                    onPressed: () => _showOverlayMode(0),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(child: Text(heading, style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: strings.mockNotebookClose,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: switch (_overlayMode) {
              1 => _CollectionEditDialog(
                key: ValueKey(('edit', item.id, item.revision)),
                item: item,
                catalog: catalog,
                embedded: true,
                onCancel: () => _showOverlayMode(0),
                onSaved: () => _showOverlayMode(0),
              ),
              2 => _CollectionNotebookAssignment(
                key: ValueKey(('notebooks', item.id, item.revision)),
                item: item,
                catalog: catalog,
                onDone: () => _showOverlayMode(0),
              ),
              _ => ListView(
                controller: _detailScroll,
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                children: [content],
              ),
            },
          ),
        ],
      );
    }
    return PreviewPageFrame(
      location: AppRoutes.mockCollectionPath(item.id),
      title: AppLocalizations.of(context).mockSupportCollectionDetailTitle,
      detail: true,
      mobile: ListView(padding: const EdgeInsets.all(20), children: [content]),
      desktop: ListView(
        children: [
          Text(
            AppLocalizations.of(context).mockSupportCollectionDetailTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 740), child: content),
        ],
      ),
    );
  }

  Future<void> _chooseNotebooks(BuildContext context, CollectionEntry item) async {
    final catalog = CollectionCatalogScope.of(context);
    final selected = {...item.notebookIds};
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).mockSupportAssignToNotebook),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final notebook in catalog.notebooks.where(
                (book) => book.targetLanguage == item.targetLanguage,
              ))
                CheckboxListTile(
                  value: selected.contains(notebook.id),
                  title: Text(notebook.name),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selected.add(notebook.id);
                    } else {
                      selected.remove(notebook.id);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).mockSupportCancel),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await catalog.setCollectionNotebooks(item.id, selected);
                  if (context.mounted) Navigator.pop(context);
                } on Object {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)),
                    );
                  }
                }
              },
              child: Text(AppLocalizations.of(context).mockSupportSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCollection(BuildContext context, CollectionEntry item) async {
    final catalog = CollectionCatalogScope.of(context);
    await showHarukaDialog<void>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      builder: (_) => _CollectionEditDialog(item: item, catalog: catalog),
    );
  }
}

class _CollectionEditDialog extends StatefulWidget {
  const _CollectionEditDialog({
    required this.item,
    required this.catalog,
    this.embedded = false,
    this.onCancel,
    this.onSaved,
    super.key,
  });

  final CollectionEntry item;
  final CollectionCatalog catalog;
  final bool embedded;
  final VoidCallback? onCancel;
  final VoidCallback? onSaved;

  @override
  State<_CollectionEditDialog> createState() => _CollectionEditDialogState();
}

class _CollectionEditDialogState extends State<_CollectionEditDialog> {
  late final content = TextEditingController(text: widget.item.displayText);
  late final meaning = TextEditingController(text: widget.item.meaning);
  late final notes = TextEditingController(text: widget.item.notes);
  bool saving = false;

  @override
  void dispose() {
    content.dispose();
    meaning.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.catalog.updateCollection(
        widget.item.id,
        displayText: content.text,
        meaning: meaning.text,
        notes: notes.text,
      );
      if (mounted) {
        if (widget.embedded) {
          widget.onSaved?.call();
        } else {
          Navigator.pop(context);
        }
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: content,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockSupportCollectionContentField,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: meaning,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockSupportCollectionMeaningField,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockSupportPersonalNotes,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: saving ? null : (widget.onCancel ?? () => Navigator.pop(context)),
        child: Text(AppLocalizations.of(context).mockSupportCancel),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(AppLocalizations.of(context).mockSupportSave),
      ),
    ];
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: form,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ),
        ],
      );
    }
    return AlertDialog(
      scrollable: true,
      title: Text(AppLocalizations.of(context).mockSupportEditNotes),
      content: form,
      actions: actions,
    );
  }
}

class _CollectionNotebookAssignment extends StatefulWidget {
  const _CollectionNotebookAssignment({
    required this.item,
    required this.catalog,
    required this.onDone,
    super.key,
  });

  final CollectionEntry item;
  final CollectionCatalog catalog;
  final VoidCallback onDone;

  @override
  State<_CollectionNotebookAssignment> createState() => _CollectionNotebookAssignmentState();
}

class _CollectionNotebookAssignmentState extends State<_CollectionNotebookAssignment> {
  late Set<String> selected = {...widget.item.notebookIds};
  bool saving = false;

  @override
  void didUpdateWidget(covariant _CollectionNotebookAssignment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) selected = {...widget.item.notebookIds};
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.catalog.setCollectionNotebooks(widget.item.id, selected);
      if (mounted) widget.onDone();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        fit: FlexFit.loose,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            for (final notebook in widget.catalog.notebooks.where(
              (book) => book.targetLanguage == widget.item.targetLanguage,
            ))
              CheckboxListTile(
                value: selected.contains(notebook.id),
                title: Text(notebook.name),
                onChanged: saving
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selected.add(notebook.id);
                        } else {
                          selected.remove(notebook.id);
                        }
                      }),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: saving ? null : widget.onDone,
              child: Text(AppLocalizations.of(context).mockSupportCancel),
            ),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(AppLocalizations.of(context).mockSupportSave),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The compact and wide overlays match the collection detail interaction in
/// the prototype while the route remains available for a direct link.
Future<void> showCollectionDetail(BuildContext context, String itemId) async {
  final catalog = CollectionCatalogScope.of(context);
  final router = GoRouter.of(context);
  TransitionRoute<dynamic>? overlayRoute;
  Future<void> openAfterDismissal(String? sourcePath) async {
    if (sourcePath == null) return;
    await overlayRoute?.completed;
    if (context.mounted) router.go(sourcePath);
  }

  final scopeGeneration = catalog.scopeGeneration;
  final item = await readCollectionForOverlay(catalog, itemId);
  if (!context.mounted) return;
  if (catalog.scopeGeneration != scopeGeneration || item == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
    return;
  }
  if (MediaQuery.sizeOf(context).width < 760) {
    final sourcePath = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      sheetAnimationStyle: HarukaMotion.sheetStyle(
        context,
        reducedMotion: PreviewStoreScope.of(context).reducedMotion,
      ),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        overlayRoute = ModalRoute.of(sheetContext) as TransitionRoute<dynamic>?;
        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .79,
          child: CollectionDetailPage(itemId: itemId, overlay: true),
        );
      },
    );
    await openAfterDismissal(sourcePath);
    return;
  }
  final sourcePath = await showHarukaDialog<String>(
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
            maxWidth: 520,
            maxHeight: (MediaQuery.sizeOf(dialogContext).height * .85).clamp(300, 620),
          ),
          child: CollectionDetailPage(itemId: itemId, overlay: true),
        ),
      );
    },
  );
  await openAfterDismissal(sourcePath);
}

class NewCollectionPage extends StatefulWidget {
  const NewCollectionPage({super.key});
  @override
  State<NewCollectionPage> createState() => _NewCollectionPageState();
}

class _NewCollectionPageState extends State<NewCollectionPage> {
  final text = TextEditingController();
  final meaning = TextEditingController();
  CollectionKind kind = CollectionKind.word;
  String? selectedLanguage;
  final selectedNotebookIds = <String>{};
  bool saving = false;
  bool _notebooksRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notebooksRequested) return;
    _notebooksRequested = true;
    final catalog = CollectionCatalogScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && catalog.notebookStatus != CollectionCatalogStatus.ready) {
        unawaited(catalog.refreshNotebooks(preserveCurrent: true));
      }
    });
  }

  Future<void> addCollection() async {
    if (saving || text.text.trim().isEmpty) return;
    setState(() => saving = true);
    final store = PreviewStoreScope.of(context);
    final catalog = CollectionCatalogScope.of(context);
    try {
      await catalog.addCollection(
        CollectionEntry(
          id: store.nextCollectionId(),
          kind: kind,
          displayText: text.text.trim(),
          targetLanguage: selectedLanguage ?? store.activeLanguage,
          meaning: meaning.text.trim(),
          notebookIds: Set.unmodifiable(selectedNotebookIds),
          createdAt: DateTime.now().toUtc(),
        ),
      );
      if (mounted) context.go(AppRoutes.mockNotebooks);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    text.dispose();
    meaning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = PreviewStoreScope.of(context);
    final catalog = CollectionCatalogScope.of(context);
    final language = selectedLanguage ?? store.activeLanguage;
    final form = HarukaSurface(
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final kindField = DropdownButtonFormField<CollectionKind>(
                initialValue: kind,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).mockSupportCollectionKindField,
                ),
                items: [
                  for (final value in CollectionKind.values.where(
                    (value) => value != CollectionKind.exercise,
                  ))
                    DropdownMenuItem(
                      value: value,
                      child: Text(collectionKindLabel(context, value)),
                    ),
                ],
                onChanged: (value) => setState(() => kind = value ?? kind),
              );
              final languageField = DropdownButtonFormField<String>(
                key: ValueKey(language),
                initialValue: language,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).mockNotebookLanguage,
                ),
                items: [
                  for (final value in const ['ja', 'en', 'zh'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(collectionLanguageLabel(context, value)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  selectedLanguage = value ?? language;
                  selectedNotebookIds.clear();
                }),
              );
              if (constraints.maxWidth < 560) {
                return Column(children: [kindField, const SizedBox(height: 12), languageField]);
              }
              return Row(
                children: [
                  Expanded(child: kindField),
                  const SizedBox(width: 12),
                  Expanded(child: languageField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockSupportCollectionContentField,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: meaning,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockSupportCollectionMeaningField,
              border: OutlineInputBorder(),
            ),
          ),
          if (catalog.notebooks.any((book) => book.targetLanguage == language)) ...[
            const SizedBox(height: 12),
            for (final notebook in catalog.notebooks.where(
              (book) => book.targetLanguage == language,
            ))
              CheckboxListTile(
                value: selectedNotebookIds.contains(notebook.id),
                title: Text(notebook.name),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    selectedNotebookIds.add(notebook.id);
                  } else {
                    selectedNotebookIds.remove(notebook.id);
                  }
                }),
              ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: saving ? null : addCollection,
            child: Text(AppLocalizations.of(context).mockSupportAddCollection),
          ),
        ],
      ),
    );
    return PreviewPageFrame(
      location: AppRoutes.mockCollectionNew,
      title: AppLocalizations.of(context).mockSupportAddCollection,
      detail: true,
      mobile: ListView(padding: const EdgeInsets.all(20), children: [form]),
      desktop: ListView(
        children: [
          Text(
            AppLocalizations.of(context).mockSupportAddCollection,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: form),
          ),
        ],
      ),
    );
  }
}

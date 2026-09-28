import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/features/collections/presentation/collection_detail_page.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';

import '../data/collection_catalog.dart';
import 'collection_catalog_access.dart';
import 'collection_catalog_scope.dart';

String collectionKindLabel(BuildContext context, CollectionKind kind) => switch (kind) {
  CollectionKind.word => AppLocalizations.of(context).mockNotebookKindWord,
  CollectionKind.phrase => AppLocalizations.of(context).mockNotebookKindPhrase,
  CollectionKind.grammar => AppLocalizations.of(context).mockNotebookKindGrammar,
  CollectionKind.sentence => AppLocalizations.of(context).mockNotebookKindSentence,
  CollectionKind.excerpt => AppLocalizations.of(context).mockNotebookKindExcerpt,
  CollectionKind.exercise => AppLocalizations.of(context).mockNotebookKindExercise,
};

String collectionLanguageLabel(BuildContext context, String language) => switch (language) {
  'ja' => AppLocalizations.of(context).mockNotebookJapanese,
  'en' => AppLocalizations.of(context).mockNotebookEnglish,
  'zh' => AppLocalizations.of(context).mockNotebookChinese,
  _ => language,
};

class NotebooksPage extends StatefulWidget {
  const NotebooksPage({super.key});
  @override
  State<NotebooksPage> createState() => _NotebooksPageState();
}

class _NotebooksPageState extends State<NotebooksPage> {
  CollectionKind? kind;
  String query = '';
  String? notebookId;
  bool searchOpen = false;
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listQuery = CollectionListQuery(kind: kind, search: query, notebookId: notebookId);
    return CollectionCatalogAccess(
      query: listQuery,
      loadingBuilder: (context, _) => _buildFrame(context, null),
      builder: (context, catalog) => _buildFrame(context, catalog),
    );
  }

  Widget _buildFrame(BuildContext context, CollectionCatalog? catalog) {
    final strings = AppLocalizations.of(context);
    final searchVisible = searchOpen || query.isNotEmpty;
    final loading = catalog == null;
    final items = catalog?.collections ?? const <CollectionEntry>[];
    final selectedName = catalog == null
        ? strings.mockNotebookAllCollections
        : _selectedNotebookName(catalog, strings);
    return PreviewPageFrame(
      location: AppRoutes.mockNotebooks,
      title: strings.mockNotebookTitle,
      mobileActions: [
        IconButton(
          tooltip: strings.mockNotebookSearchHint,
          onPressed: () => setState(() {
            searchOpen = !searchVisible;
            if (!searchOpen) {
              query = '';
              searchController.clear();
            }
          }),
          icon: Icon(searchVisible ? Icons.close : Icons.search),
        ),
        IconButton(
          tooltip: strings.mockNotebookAddCollection,
          onPressed: () => context.push(AppRoutes.mockCollectionNew),
          icon: const Icon(Icons.add),
        ),
      ],
      mobile: MobileNotebooksView(
        items: items,
        kind: kind,
        selectedName: selectedName,
        searchOpen: searchVisible,
        searchController: searchController,
        searchFocusNode: searchFocusNode,
        onType: (value) => setState(() => kind = value),
        onQuery: (value) => setState(() => query = value),
        onNotebook: (value) => setState(() => notebookId = value),
        loading: loading,
      ),
      desktop: DesktopNotebooksView(
        items: items,
        kind: kind,
        selectedName: selectedName,
        searchController: searchController,
        searchFocusNode: searchFocusNode,
        onType: (value) => setState(() => kind = value),
        onQuery: (value) => setState(() => query = value),
        onNotebook: (value) => setState(() => notebookId = value),
        loading: loading,
      ),
    );
  }

  String _selectedNotebookName(CollectionCatalog catalog, AppLocalizations strings) {
    if (notebookId == null) return strings.mockNotebookAllCollections;
    final selected = catalog.notebooks.where((item) => item.id == notebookId).firstOrNull;
    if (selected != null) return selected.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && notebookId != null) setState(() => notebookId = null);
    });
    return strings.mockNotebookAllCollections;
  }
}

Future<void> showNotebookChooser(BuildContext context, ValueChanged<String?> select) async {
  final catalog = CollectionCatalogScope.of(context);
  if (catalog.notebookStatus != CollectionCatalogStatus.ready) {
    try {
      await catalog.refreshNotebooks(preserveCurrent: true);
    } on Object {
      // The catalog publishes the unavailable state for the shared feedback.
    }
  }
  if (!context.mounted) return;
  if (catalog.notebookStatus != CollectionCatalogStatus.ready) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
    return;
  }
  final strings = AppLocalizations.of(context);
  await showHarukaDialog<void>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
    ),
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.mockNotebookChooserTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(strings.mockNotebookAllCollections),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                select(null);
                Navigator.pop(dialogContext);
              },
            ),
            for (final notebook in catalog.notebooks)
              ListTile(
                title: Text(notebook.name),
                subtitle: Text(
                  strings.mockNotebookLanguageAndCount(
                    collectionLanguageLabel(context, notebook.targetLanguage),
                    catalog.notebookCount(notebook.id),
                  ),
                ),
                trailing: IconButton(
                  tooltip: strings.mockNotebookManageNamed(notebook.name),
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    unawaited(showNotebookEditor(context, notebook: notebook));
                  },
                ),
                onTap: () {
                  select(notebook.id);
                  Navigator.pop(dialogContext);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.mockNotebookClose),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            unawaited(showNotebookEditor(context));
          },
          icon: const Icon(Icons.add),
          label: Text(strings.mockNotebookCreate),
        ),
      ],
    ),
  );
}

Future<void> showNotebookEditor(BuildContext context, {NotebookRecord? notebook}) async {
  final catalog = CollectionCatalogScope.of(context);
  await showHarukaDialog<void>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
    ),
    builder: (_) => _NotebookEditorDialog(catalog: catalog, notebook: notebook),
  );
}

class _NotebookEditorDialog extends StatefulWidget {
  const _NotebookEditorDialog({required this.catalog, this.notebook});
  final CollectionCatalog catalog;
  final NotebookRecord? notebook;

  @override
  State<_NotebookEditorDialog> createState() => _NotebookEditorDialogState();
}

class _NotebookEditorDialogState extends State<_NotebookEditorDialog> {
  late final name = TextEditingController(text: widget.notebook?.name ?? '');
  late final description = TextEditingController(text: widget.notebook?.description ?? '');
  late String language = widget.notebook?.targetLanguage ?? 'ja';
  bool saving = false;

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      if (widget.notebook == null) {
        await widget.catalog.createNotebook(name.text, language, description.text);
      } else {
        await widget.catalog.updateNotebook(
          widget.notebook!.id,
          name: name.text,
          description: description.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mockNotebookInvalidName)),
        );
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
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.notebook == null
          ? AppLocalizations.of(context).mockNotebookCreate
          : AppLocalizations.of(context).mockNotebookManage,
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockNotebookName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: language,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockNotebookLanguage,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'ja',
                child: Text(AppLocalizations.of(context).mockNotebookJapanese),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text(AppLocalizations.of(context).mockNotebookEnglish),
              ),
              DropdownMenuItem(
                value: 'zh',
                child: Text(AppLocalizations.of(context).mockNotebookChinese),
              ),
            ],
            onChanged: widget.notebook == null
                ? (value) => setState(() => language = value ?? 'ja')
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: description,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).mockNotebookDescription,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (widget.notebook != null)
        TextButton(
          onPressed: saving
              ? null
              : () async {
                  final deleted = await showHarukaDialog<bool>(
                    context: context,
                    animationStyle: HarukaMotion.dialogStyle(
                      context,
                      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
                    ),
                    builder: (confirmContext) => AlertDialog(
                      title: Text(AppLocalizations.of(context).mockNotebookDeleteConfirmTitle),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).mockNotebookDeleteSummary(
                              widget.notebook!.name,
                              widget.catalog.notebookCount(widget.notebook!.id),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(AppLocalizations.of(context).mockNotebookDeleteConfirmMessage),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: Text(AppLocalizations.of(context).mockNotebookCancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          child: Text(AppLocalizations.of(context).mockNotebookDelete),
                        ),
                      ],
                    ),
                  );
                  if (deleted == true && context.mounted) {
                    setState(() => saving = true);
                    try {
                      await widget.catalog.deleteNotebook(widget.notebook!.id);
                      if (context.mounted) Navigator.pop(context);
                    } on Object {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context).authUnavailableShort),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  }
                },
          child: Text(AppLocalizations.of(context).mockNotebookDeleteNotebook),
        ),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(AppLocalizations.of(context).mockNotebookCancel),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(AppLocalizations.of(context).mockNotebookSave),
      ),
    ],
  );
}

class MobileNotebooksView extends StatelessWidget {
  const MobileNotebooksView({
    required this.items,
    required this.kind,
    required this.selectedName,
    required this.searchOpen,
    required this.searchController,
    required this.searchFocusNode,
    required this.onType,
    required this.onQuery,
    required this.onNotebook,
    this.loading = false,
    super.key,
  });
  final List<CollectionEntry> items;
  final CollectionKind? kind;
  final String selectedName;
  final bool searchOpen;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<CollectionKind?> onType;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onNotebook;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final strings = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => showNotebookChooser(context, onNotebook),
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: Row(
                    children: [
                      Expanded(child: Text(selectedName, overflow: TextOverflow.ellipsis)),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => context.push(AppRoutes.mockDailyWords),
                  icon: const Icon(Icons.schedule),
                  label: Text(strings.mockNotebookDailyWords),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: roles.signal.withValues(alpha: .16),
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (searchOpen) ...[
          TextField(
            controller: searchController,
            focusNode: searchFocusNode,
            autofocus: true,
            onChanged: onQuery,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: strings.mockNotebookSearchHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: Stack(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final value in const <CollectionKind?>[
                      null,
                      CollectionKind.word,
                      CollectionKind.phrase,
                      CollectionKind.sentence,
                      CollectionKind.grammar,
                      CollectionKind.exercise,
                      CollectionKind.excerpt,
                    ]) ...[
                      SizedBox(
                        height: 48,
                        child: HarukaPill(
                          label: value == null
                              ? strings.mockNotebookAll
                              : collectionKindLabel(context, value),
                          selected: kind == value,
                          onTap: () => onType(value),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 30,
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [roles.canvas.withValues(alpha: 0), roles.canvas],
                      ),
                    ),
                    child: Icon(Icons.chevron_right, size: 17, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (!loading)
          Row(
            children: [
              Text(
                strings.mockNotebookCollectionCount(items.length),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push(AppRoutes.mockExerciseBuilder),
                child: Text(strings.mockNotebookGenerateExercise),
              ),
              PopupMenuButton<String>(
                tooltip: strings.mockNotebookCsv,
                position: PopupMenuPosition.under,
                onSelected: (value) {
                  if (value == 'csv') unawaited(context.push<void>(AppRoutes.mockCsv));
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'csv', child: Text(strings.mockNotebookCsv)),
                ],
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (items.isEmpty)
          HarukaEmpty(
            title: strings.mockNotebookEmptyTitle,
            message: strings.mockNotebookEmptyHint,
          ),
        if (!loading && items.isNotEmpty)
          HarukaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  MobileCollectionRow(item: items[index], grouped: true),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class MobileCollectionRow extends StatelessWidget {
  const MobileCollectionRow({required this.item, this.grouped = false, super.key});
  final CollectionEntry item;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: HarukaColors.of(context).selected,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item.kind == CollectionKind.word ? Icons.menu_book_outlined : Icons.chat_bubble_outline,
            size: 17,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.displayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (item.reading != null) ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        item.reading!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                item.meaning,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        if (grouped) const Icon(Icons.chevron_right, size: 18),
        if (item.kind == CollectionKind.word)
          IconButton(
            tooltip: AppLocalizations.of(context).mockNotebookReadNamed(item.displayText),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).mockNotebookAudioUnavailable)),
            ),
            icon: const Icon(Icons.volume_up_outlined, size: 18),
          ),
        if (!grouped) const Icon(Icons.chevron_right, size: 18),
      ],
    );
    final content = InkWell(
      onTap: () => item.kind == CollectionKind.word
          ? showWordDetail(context, item.id)
          : showCollectionDetail(context, item.id),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: grouped ? 9 : 10),
        child: row,
      ),
    );
    return grouped ? content : HarukaSurface(padding: EdgeInsets.zero, child: content);
  }
}

class DesktopNotebooksView extends StatelessWidget {
  const DesktopNotebooksView({
    required this.items,
    required this.kind,
    required this.selectedName,
    required this.searchController,
    required this.searchFocusNode,
    required this.onType,
    required this.onQuery,
    required this.onNotebook,
    this.loading = false,
    super.key,
  });
  final List<CollectionEntry> items;
  final CollectionKind? kind;
  final String selectedName;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<CollectionKind?> onType;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onNotebook;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final strings = AppLocalizations.of(context);
    final scopeControls = Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: loading ? null : () => showNotebookChooser(context, onNotebook),
              icon: const Icon(Icons.bookmarks_outlined),
              label: Row(
                children: [
                  Expanded(child: Text(selectedName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: loading ? null : () => context.push(AppRoutes.mockDailyWords),
              icon: const Icon(Icons.schedule),
              label: Text(strings.mockNotebookDailyWords),
              style: OutlinedButton.styleFrom(
                backgroundColor: roles.signal.withValues(alpha: .16),
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
              ),
            ),
          ),
        ),
      ],
    );
    final search = TextField(
      controller: searchController,
      focusNode: searchFocusNode,
      onChanged: onQuery,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: strings.mockNotebookSearchHint,
        border: OutlineInputBorder(borderSide: BorderSide(color: scheme.outline)),
      ),
    );
    final filters = Wrap(
      spacing: 5,
      children: [
        HarukaPill(
          label: strings.mockNotebookAll,
          selected: kind == null,
          onTap: () => onType(null),
        ),
        for (final value in CollectionKind.values)
          HarukaPill(
            label: collectionKindLabel(context, value),
            selected: kind == value,
            onTap: () => onType(value),
          ),
      ],
    );
    final secondaryActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!loading)
          Text(
            strings.mockNotebookCollectionCount(items.length),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        const SizedBox(width: 9),
        TextButton.icon(
          onPressed: loading ? null : () => context.push(AppRoutes.mockExerciseBuilder),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(strings.mockNotebookGenerateExercise),
        ),
        PopupMenuButton<String>(
          tooltip: strings.mockNotebookCsv,
          position: PopupMenuPosition.under,
          onSelected: (value) {
            if (value == 'csv') unawaited(context.push<void>(AppRoutes.mockCsv));
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'csv', child: Text(strings.mockNotebookCsv)),
          ],
          icon: const Icon(Icons.more_horiz),
        ),
      ],
    );
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.mockNotebookTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : () => context.push(AppRoutes.mockCollectionNew),
              icon: const Icon(Icons.add),
              label: Text(strings.mockNotebookAdd),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 850) {
              return Column(
                children: [
                  SizedBox(width: 460, child: scopeControls),
                  const SizedBox(height: 10),
                  search,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 460, child: scopeControls),
                const SizedBox(width: 14),
                Expanded(child: search),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filters,
                  Align(alignment: Alignment.centerRight, child: secondaryActions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: filters),
                secondaryActions,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (items.isEmpty)
          HarukaEmpty(
            title: strings.mockNotebookEmptyTitle,
            message: strings.mockNotebookEmptyHint,
          ),
        if (!loading)
          HarukaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  DesktopCollectionRow(item: items[i]),
                  if (i < items.length - 1) Divider(height: 1, color: scheme.outline),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class DesktopCollectionRow extends StatelessWidget {
  const DesktopCollectionRow({required this.item, super.key});
  final CollectionEntry item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => item.kind == CollectionKind.word
          ? showWordDetail(context, item.id)
          : showCollectionDetail(context, item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HarukaColors.of(context).selected,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                item.kind == CollectionKind.word
                    ? Icons.menu_book_outlined
                    : Icons.chat_bubble_outline,
                size: 16,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (item.reading != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.reading!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    item.meaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                  ),
                ],
              ),
            ),
            Text(
              collectionKindLabel(context, item.kind),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, size: 17),
            if (item.kind == CollectionKind.word) ...[
              const SizedBox(width: 12),
              IconButton(
                tooltip: AppLocalizations.of(context).mockNotebookReadNamed(item.displayText),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context).mockNotebookAudioUnavailable),
                  ),
                ),
                icon: const Icon(Icons.volume_up_outlined, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

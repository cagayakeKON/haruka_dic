import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/motion.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/api/learning_models.dart' as published;
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/features/collections/reference_feature_scope.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/identified.dart';

import '../data/material_catalog.dart';
import '../data/http_material_catalog.dart';
import '../data/material_import_repository.dart' show sourceFormat;
import '../domain/material_import.dart';
import '../domain/material_metadata.dart';
import '../../../core/api/request_ids.dart';
import '../../../core/api/responses.dart';
import 'material_management_controls.dart';
import 'material_catalog_scope.dart';
import 'material_catalog_access.dart';

HttpMaterialCatalog? liveMaterialCatalog(BuildContext context) =>
    switch (MaterialCatalogScope.maybeOf(context)) {
      final HttpMaterialCatalog catalog => catalog,
      _ => null,
    };
String materialLibraryPath(BuildContext context) =>
    liveMaterialCatalog(context) == null ? AppRoutes.mockLibrary : AppRoutes.materials;
String materialImportPath(BuildContext context) =>
    liveMaterialCatalog(context) == null ? AppRoutes.mockImport : AppRoutes.materialImport;
String materialOpenPath(BuildContext context, String id) => liveMaterialCatalog(context) == null
    ? AppRoutes.mockMaterialPath(id)
    : AppRoutes.materialPath(id);
String materialDetailsPath(BuildContext context, String id) => liveMaterialCatalog(context) == null
    ? AppRoutes.mockMaterialDetailsPath(id)
    : AppRoutes.materialDetailsPath(id);
Widget _identifiedMaterialSearch(BuildContext context, Widget child) =>
    liveMaterialCatalog(context) == null
    ? child
    : Identified(id: UiTestIds.materialSearch, child: child);

bool materialCanOpen(BuildContext context, MaterialSummary item) {
  final catalog = liveMaterialCatalog(context);
  if (catalog == null) return item.status != 'processing';
  final row = catalog.metadata(item.id);
  return catalog.allows('client.material.read') &&
      row?.readable == true &&
      row?.sourceStatus == 'readable' &&
      const {'ja', 'en'}.contains(row?.language) &&
      row?.type == LearningMaterialType.novel &&
      row?.contentRevisionId != null &&
      row?.firstChapterId != null;
}

bool materialCanDelete(BuildContext context, MaterialSummary item) {
  final catalog = liveMaterialCatalog(context);
  if (catalog == null) return true;
  final row = catalog.metadata(item.id);
  return row != null && materialMutationAllowed(catalog, row, 'client.material.delete');
}

String materialTypeLabel(BuildContext context, LearningMaterialType type) => switch (type) {
  LearningMaterialType.novel => AppLocalizations.of(context).mockLibraryNovel,
  LearningMaterialType.textbook => AppLocalizations.of(context).mockLibraryTextbook,
  LearningMaterialType.exam => AppLocalizations.of(context).mockLibraryExam,
};

String materialStatusLabel(BuildContext context, MaterialSummary item) => switch (item.status) {
  'readable' =>
    item.type == LearningMaterialType.novel
        ? AppLocalizations.of(context).mockLibraryReadable
        : AppLocalizations.of(context).mockLibraryLearnable,
  'needs_review' => AppLocalizations.of(context).mockLibraryNeedsReview,
  'processing' => AppLocalizations.of(context).mockLibraryProcessing,
  _ => AppLocalizations.of(context).mockLibraryPending,
};

String _languageLabel(AppLocalizations l10n, String language) => switch (language) {
  'ja' => l10n.mockLibraryJapanese,
  'en' => l10n.mockLibraryEnglish,
  _ => language,
};

String _materialDetailSuffix(AppLocalizations l10n, MaterialSummary item) {
  final count = item.sectionCount;
  if (count == null || item.status == 'processing') return '';
  return switch (item.type) {
    LearningMaterialType.novel => l10n.mockLibraryChapterCount(count),
    LearningMaterialType.textbook => l10n.mockLibraryUnitCount(count),
    LearningMaterialType.exam => l10n.mockLibraryQuestionCount(count),
  };
}

String _mobileMaterialMetadata(BuildContext context, MaterialSummary item) {
  final l10n = AppLocalizations.of(context);
  return l10n
      .mockLibraryMaterialMetadata(
        materialTypeLabel(context, item.type),
        _languageLabel(l10n, item.language),
        _materialDetailSuffix(l10n, item),
      )
      .replaceFirst(RegExp(r'^\s*[·・]\s*'), '');
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LearningMaterialType? type;
  String? language;
  String query = '';
  bool searchOpen = false;
  final searchController = TextEditingController();
  final desktopSearchFocusNode = FocusNode();
  final _mobileViewportAnchor = MaterialViewportAnchor();
  final _desktopViewportAnchor = MaterialViewportAnchor();
  final _publishedMobileScroll = ScrollController();
  final _publishedDesktopScroll = ScrollController();
  ReferenceController? _reference;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (liveMaterialCatalog(context) != null) return;
    final reference = ReferenceFeatureScope.maybeOf(context);
    if (reference != null && !identical(reference, _reference)) {
      _reference = reference;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_reference, reference)) unawaited(reference.ensureMaterials());
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    desktopSearchFocusNode.dispose();
    _publishedMobileScroll.dispose();
    _publishedDesktopScroll.dispose();
    super.dispose();
  }

  void resetFilters() {
    _clearViewportAnchors();
    searchController.clear();
    setState(() {
      type = null;
      query = '';
      language = null;
    });
  }

  void closeSearch() {
    _clearViewportAnchors();
    searchController.clear();
    setState(() {
      searchOpen = false;
      query = '';
    });
  }

  void _setType(LearningMaterialType? value) {
    _clearViewportAnchors();
    setState(() => type = value);
  }

  void _setQuery(String value) {
    _clearViewportAnchors();
    setState(() => query = value);
  }

  void _clearViewportAnchors() {
    _mobileViewportAnchor.clear();
    _desktopViewportAnchor.clear();
  }

  @override
  Widget build(BuildContext context) {
    final reference = ReferenceFeatureScope.maybeOf(context);
    if (reference != null && liveMaterialCatalog(context) == null) {
      return _buildPublishedFrame(context, reference);
    }
    final listQuery = MaterialCatalogQuery(type: type, search: query, language: language);
    return MaterialCatalogAccess(
      query: listQuery,
      loadingBuilder: (context) => _buildFrame(context, null),
      builder: (context, catalog) => _buildFrame(context, catalog.filterMaterials(listQuery)),
    );
  }

  Widget _buildPublishedFrame(BuildContext context, ReferenceController reference) {
    final l10n = AppLocalizations.of(context);
    final term = query.trim().toLowerCase();
    final rows = [
      for (final item in reference.materials)
        if ((type == null || type == LearningMaterialType.novel) &&
            (term.isEmpty ||
                item.title.toLowerCase().contains(term) ||
                item.language.toLowerCase().contains(term)))
          item,
    ];
    Widget results(bool compact) => _PublishedMaterialResults(
      reference: reference,
      items: rows,
      loading: !reference.materialsLoaded && reference.materialError == null,
      hasMore: reference.materialCursor != null,
      error: reference.materialError != null,
      emptyCatalog: reference.materials.isEmpty,
      compact: compact,
      scrollController: compact ? _publishedMobileScroll : _publishedDesktopScroll,
      onMore: () => unawaited(reference.loadMaterials(more: true)),
      onRetry: () => unawaited(reference.loadMaterials()),
      onOpen: (item) => unawaited(context.push(AppRoutes.materialPath(item.id))),
    );
    return Identified(
      id: UiTestIds.referenceMaterialsPage,
      child: PreviewPageFrame(
        location: AppRoutes.materials,
        title: l10n.mockLibraryTitle,
        mobileHeader: searchOpen
            ? Row(
                children: [
                  IconButton(
                    tooltip: l10n.mockLibraryCloseSearch,
                    onPressed: closeSearch,
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  ),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: _setQuery,
                      decoration: InputDecoration(hintText: l10n.mockLibrarySearchMaterials),
                    ),
                  ),
                ],
              )
            : null,
        mobileActions: [
          if (!searchOpen)
            IconButton(
              tooltip: l10n.mockLibrarySearchMaterials,
              onPressed: () => setState(() => searchOpen = true),
              icon: const Icon(Icons.search),
            ),
        ],
        mobile: MobileLibraryView(
          type: type,
          searchOpen: searchOpen,
          onType: _setType,
          allowImport: false,
          availableTypes: const [LearningMaterialType.novel],
          results: results(true),
        ),
        desktop: DesktopLibraryView(
          type: type,
          searchController: searchController,
          searchFocusNode: desktopSearchFocusNode,
          onType: _setType,
          onQuery: _setQuery,
          allowImport: false,
          availableTypes: const [LearningMaterialType.novel],
          results: results(false),
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context, List<MaterialSummary>? items) {
    final l10n = AppLocalizations.of(context);
    final live = liveMaterialCatalog(context);
    final languageFilter = live == null
        ? null
        : SizedBox(
            width: 125,
            child: Identified(
              id: UiTestIds.materialLanguageFilter,
              child: DropdownButtonFormField<String>(
                key: ValueKey('material-language-$language'),
                initialValue: language ?? '',
                decoration: InputDecoration(labelText: l10n.materialLanguage, isDense: true),
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.materialAllLanguages)),
                  DropdownMenuItem(value: 'ja', child: Text(l10n.mockLibraryJapanese)),
                  DropdownMenuItem(value: 'en', child: Text(l10n.mockLibraryEnglish)),
                ],
                onChanged: (value) {
                  _clearViewportAnchors();
                  setState(() => language = value == '' ? null : value);
                },
              ),
            ),
          );
    final continuation = live == null
        ? null
        : Column(
            children: [
              if (live.failure != null)
                TextButton(
                  onPressed: () => live.refresh(
                    query: MaterialCatalogQuery(type: type, search: query, language: language),
                    force: true,
                    preserveCurrent: true,
                  ),
                  child: Text(l10n.authRetry),
                ),
              if (live.hasMore)
                Identified(
                  id: UiTestIds.materialMore,
                  child: TextButton(
                    onPressed: live.loadingMore ? null : live.more,
                    child: Text(l10n.materialMore),
                  ),
                ),
            ],
          );
    return PreviewPageFrame(
      location: materialLibraryPath(context),
      title: l10n.mockLibraryTitle,
      mobileHeader: searchOpen
          ? Row(
              children: [
                IconButton(
                  tooltip: l10n.mockLibraryCloseSearch,
                  onPressed: closeSearch,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _identifiedMaterialSearch(
                    context,
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: _setQuery,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        prefixIcon: const Icon(Icons.search),
                        hintText: l10n.mockLibrarySearchMaterials,
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.mockLibraryResetFilters,
                                onPressed: () {
                                  searchController.clear();
                                  _setQuery('');
                                },
                                icon: const Icon(Icons.close),
                              ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      mobileActions: [
        if (!searchOpen)
          IconButton(
            tooltip: l10n.mockLibrarySearchMaterials,
            onPressed: () => setState(() => searchOpen = true),
            icon: const Icon(Icons.search),
          ),
      ],
      mobile: MobileLibraryView(
        extraFilters: languageFilter,
        allowImport: live == null || live.allows('client.material.import'),
        type: type,
        searchOpen: searchOpen,
        onType: _setType,
        results: items == null
            ? const Center(child: CircularProgressIndicator())
            : MobileLibraryResults(
                items: items,
                viewportAnchor: _mobileViewportAnchor,
                type: type,
                query: query,
                onReset: resetFilters,
                continuation: continuation,
              ),
      ),
      desktop: DesktopLibraryView(
        extraFilters: languageFilter,
        allowImport: live == null || live.allows('client.material.import'),
        type: type,
        searchController: searchController,
        searchFocusNode: desktopSearchFocusNode,
        onType: _setType,
        onQuery: _setQuery,
        results: items == null
            ? const Center(child: CircularProgressIndicator())
            : DesktopLibraryResults(
                items: items,
                viewportAnchor: _desktopViewportAnchor,
                type: type,
                query: query,
                onReset: resetFilters,
                continuation: continuation,
              ),
      ),
    );
  }
}

class _PublishedMaterialResults extends StatelessWidget {
  const _PublishedMaterialResults({
    required this.reference,
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.emptyCatalog,
    required this.compact,
    required this.scrollController,
    required this.onMore,
    required this.onRetry,
    required this.onOpen,
  });

  final ReferenceController reference;

  final List<published.MaterialSummary> items;
  final bool loading;
  final bool hasMore;
  final bool error;
  final bool emptyCatalog;
  final bool compact;
  final ScrollController scrollController;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final ValueChanged<published.MaterialSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return ListView(
      controller: scrollController,
      key: PageStorageKey(compact ? 'published-materials-mobile' : 'published-materials-desktop'),
      padding: EdgeInsets.fromLTRB(compact ? 20 : 0, 0, compact ? 20 : 0, 28),
      children: [
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error)
          HarukaEmpty(
            title: l10n.mockMaterialUnavailableTitle,
            message: l10n.mockMaterialUnavailableMessage,
            action: TextButton(onPressed: onRetry, child: Text(l10n.referenceRetry)),
          ),
        if (!loading && !error && items.isEmpty)
          HarukaEmpty(
            title: emptyCatalog ? l10n.mockLibraryNoMaterials : l10n.mockLibraryNoMatches,
            message: emptyCatalog ? l10n.mockLibraryEmptyHint : l10n.mockLibraryTryAnotherSearch,
          ),
        for (final item in items) ...[
          Identified(
            id: UiTestIds.referenceMaterialRow(item.id),
            merge: true,
            child: Card.outlined(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              color: scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
              ),
              child: InkWell(
                onTap: () => onOpen(item),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: Row(
                    children: [
                      _MaterialCover(
                        label: item.title.isEmpty
                            ? ''
                            : String.fromCharCodes([item.title.runes.first]),
                        color: roles.bookBlue,
                        width: compact ? 58 : 64,
                        height: compact ? 76 : 72,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${item.language == 'ja' ? l10n.mockLibraryJapanese : l10n.mockLibraryEnglish} · ${l10n.mockLibraryNovel}',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            if (reference.auth.access?.allows('client.material.read') == true) ...[
                              const SizedBox(height: 9),
                              Text(
                                l10n.mockLibraryReadable,
                                style: TextStyle(color: roles.positive, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (compact)
                        _MobileMaterialMenu(
                          title: item.title,
                          onOpen: () {},
                          onDetails: () =>
                              _showPublishedMaterialDetails(context, reference, item, onOpen),
                        )
                      else ...[
                        PopupMenuButton<String>(
                          tooltip: l10n.mockLibraryMoreActions(item.title),
                          onSelected: (_) =>
                              _showPublishedMaterialDetails(context, reference, item, onOpen),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'detail',
                              child: Text(l10n.mockLibraryViewDetails),
                            ),
                          ],
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (hasMore)
          Center(
            child: TextButton(
              onPressed: reference.materialsLoading ? null : onMore,
              child: Text(l10n.referenceLoadMore),
            ),
          ),
      ],
    );
  }
}

Future<void> _showPublishedMaterialDetails(
  BuildContext context,
  ReferenceController reference,
  published.MaterialSummary item,
  ValueChanged<published.MaterialSummary> onOpen,
) async {
  final l10n = AppLocalizations.of(context);
  final openingScope = referenceScope(reference.auth, 'reference');
  await showHarukaDialog<void>(
    context: context,
    builder: (dialogContext) => ReferenceDialogGuard(
      controller: reference,
      openingScope: openingScope,
      allowed: () =>
          reference.auth.access?.allows('client.material.list') == true &&
          reference.materials.any((row) => row.id == item.id && row.revisionId == item.revisionId),
      child: HarukaDialogSurface(
        title: l10n.mockMaterialDetailsTitle,
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onOpen(item);
            },
            child: Text(l10n.mockLibraryViewMaterial(item.title)),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(l10n.mockLibraryNovel),
            Text(item.language == 'ja' ? l10n.mockLibraryJapanese : l10n.mockLibraryEnglish),
          ],
        ),
      ),
    ),
  );
}

/// Keeps the opened material at the same viewport position after a gated
/// catalog refresh changes the rows before it.
final class MaterialViewportAnchor {
  final Map<String, GlobalKey> _rowKeys = {};
  String? _materialId;
  String? _queryKey;
  double _top = 0;
  double _scrollOffset = 0;
  double _rowExtent = 0;
  int _index = 0;
  bool _pending = false;

  GlobalKey keyFor(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  void capture(String id, String queryKey, List<MaterialSummary> items, {bool pending = true}) {
    final rowContext = keyFor(id).currentContext;
    final row = rowContext?.findRenderObject();
    final scrollable = rowContext == null ? null : Scrollable.maybeOf(rowContext);
    final viewport = row == null ? null : RenderAbstractViewport.of(row);
    if (row is! RenderBox || viewport is! RenderBox || scrollable == null) {
      _pending = false;
      return;
    }
    _materialId = id;
    _queryKey = queryKey;
    _top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
    _scrollOffset = scrollable.position.pixels;
    _rowExtent = row.size.height;
    _index = items.indexWhere((item) => item.id == id);
    _pending = pending;
  }

  void activate(String id) {
    if (_materialId == id) _pending = true;
  }

  void clear() {
    _pending = false;
    _materialId = null;
    _queryKey = null;
    _rowKeys.clear();
  }

  void pruneTo(List<MaterialSummary> items) {
    final ids = items.map((item) => item.id).toSet();
    _rowKeys.removeWhere((id, _) => !ids.contains(id));
  }
}

class _RestoringMaterialList extends StatefulWidget {
  const _RestoringMaterialList({
    required this.items,
    required this.anchor,
    required this.queryKey,
    required this.builder,
    super.key,
  });

  final List<MaterialSummary> items;
  final MaterialViewportAnchor anchor;
  final String queryKey;
  final Widget Function(ScrollController) builder;

  @override
  State<_RestoringMaterialList> createState() => _RestoringMaterialListState();
}

class _RestoringMaterialListState extends State<_RestoringMaterialList> {
  final _controller = ScrollController();
  bool _restoreScheduled = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _scheduleRestore();
  }

  @override
  void didUpdateWidget(covariant _RestoringMaterialList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRestore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) ?? true) _scheduleRestore();
  }

  void _scheduleRestore() {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted) return;
      widget.anchor.pruneTo(widget.items);
      _restore();
    });
  }

  void _restore() {
    final anchor = widget.anchor;
    final id = anchor._materialId;
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return;
    if (!anchor._pending || id == null || anchor._queryKey != widget.queryKey) return;
    if (!_controller.hasClients) return;
    final index = widget.items.indexWhere((item) => item.id == id);
    if (index < 0) {
      anchor._pending = false;
      _attempts = 0;
      return;
    }
    final row = anchor.keyFor(id).currentContext?.findRenderObject();
    if (row is RenderBox) {
      final viewport = RenderAbstractViewport.of(row);
      final target = viewport.getOffsetToReveal(row, 0).offset - anchor._top;
      final position = _controller.position;
      _controller.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
      anchor._pending = false;
      _attempts = 0;
      return;
    }

    // PageStorage restores the old pixel offset first. Move near the ID if
    // changed leading rows left it outside the lazily built viewport, then
    // align the measured row on the next frame.
    final position = _controller.position;
    if (_attempts == 0) {
      final estimated = anchor._scrollOffset + (index - anchor._index) * anchor._rowExtent;
      _controller.jumpTo(estimated.clamp(position.minScrollExtent, position.maxScrollExtent));
    } else {
      final builtIndices = <int>[
        for (var i = 0; i < widget.items.length; i++)
          if (anchor.keyFor(widget.items[i].id).currentContext != null) i,
      ];
      if (builtIndices.isEmpty) {
        anchor._pending = false;
        return;
      }
      final nearest = index < builtIndices.first ? builtIndices.first : builtIndices.last;
      final estimated = position.pixels + (index - nearest) * anchor._rowExtent;
      _controller.jumpTo(estimated.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    if (++_attempts < 8) {
      _scheduleRestore();
    } else {
      anchor._pending = false;
      _attempts = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

class MobileLibraryView extends StatelessWidget {
  const MobileLibraryView({
    required this.type,
    required this.searchOpen,
    required this.onType,
    required this.results,
    this.allowImport = true,
    this.availableTypes,
    this.extraFilters,
    super.key,
  });

  final LearningMaterialType? type;
  final bool searchOpen;
  final ValueChanged<LearningMaterialType?> onType;
  final Widget results;
  final bool allowImport;
  final List<LearningMaterialType>? availableTypes;
  final Widget? extraFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = HarukaMotion.reduced(
      context,
      reducedMotion: _libraryReducedMotion(context),
    );
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 7),
              child: HarukaSurface(
                key: const ValueKey('mobile-material-types'),
                radius: 16,
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _MobileMaterialTypeTab(
                      label: l10n.mockLibraryAll,
                      icon: Icons.grid_view_rounded,
                      selected: type == null,
                      reduceMotion: reduceMotion,
                      onTap: () => onType(null),
                    ),
                    for (final value in availableTypes ?? LearningMaterialType.values)
                      _MobileMaterialTypeTab(
                        label: materialTypeLabel(context, value),
                        icon: switch (value) {
                          LearningMaterialType.novel => Icons.auto_stories_outlined,
                          LearningMaterialType.textbook => Icons.menu_book_outlined,
                          LearningMaterialType.exam => Icons.description_outlined,
                        },
                        selected: type == value,
                        reduceMotion: reduceMotion,
                        onTap: () => onType(value),
                      ),
                  ],
                ),
              ),
            ),
            if (extraFilters != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(alignment: Alignment.centerRight, child: extraFilters),
              ),
            Expanded(child: results),
          ],
        ),
        if (!searchOpen && allowImport)
          Positioned(
            right: 22,
            bottom: 22,
            child: FloatingActionButton.extended(
              onPressed: () => context.push(materialImportPath(context)),
              icon: const Icon(Icons.add),
              label: Text(l10n.mockLibraryImport),
            ),
          ),
      ],
    );
  }
}

class MobileLibraryResults extends StatelessWidget {
  const MobileLibraryResults({
    required this.items,
    required this.viewportAnchor,
    required this.type,
    required this.query,
    required this.onReset,
    this.continuation,
    super.key,
  });

  final List<MaterialSummary> items;
  final MaterialViewportAnchor viewportAnchor;
  final LearningMaterialType? type;
  final String query;
  final VoidCallback onReset;
  final Widget? continuation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = HarukaMotion.reduced(
      context,
      reducedMotion: _libraryReducedMotion(context),
    );
    final queryKey = '${type?.name ?? 'all'}-$query';
    return _RestoringMaterialList(
      key: ValueKey('library-mobile-$queryKey'),
      items: items,
      anchor: viewportAnchor,
      queryKey: queryKey,
      builder: (controller) => ListView(
        controller: controller,
        key: PageStorageKey('library-mobile-$queryKey'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 150),
        children: [
          if (items.isEmpty)
            HarukaEmpty(
              title: query.isEmpty ? l10n.mockLibraryNoMaterials : l10n.mockLibraryNoMatches,
              message: query.isEmpty ? l10n.mockLibraryAddPrompt : l10n.mockLibraryTryAnotherSearch,
              action: TextButton(onPressed: onReset, child: Text(l10n.mockLibraryResetFilters)),
            ),
          for (final item in items) ...[
            TweenAnimationBuilder<double>(
              key: ValueKey('mobile-material-${item.id}-$queryKey'),
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion || viewportAnchor._pending
                  ? Duration.zero
                  : HarukaMotion.pageEnter,
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(offset: Offset(0, (1 - value) * 8), child: child),
              ),
              child: MobileMaterialCard(
                item: item,
                viewportAnchor: viewportAnchor,
                queryKey: queryKey,
                catalogQuery: MaterialCatalogQuery(type: type, search: query),
                items: items,
              ),
            ),
            const SizedBox(height: 10),
          ],
          ?continuation,
        ],
      ),
    );
  }
}

class _MobileMaterialTypeTab extends StatelessWidget {
  const _MobileMaterialTypeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : HarukaMotion.pageEnter,
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: selected ? roles.selected : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileMaterialCard extends StatelessWidget {
  const MobileMaterialCard({
    required this.item,
    required this.viewportAnchor,
    required this.queryKey,
    required this.catalogQuery,
    required this.items,
    super.key,
  });
  final MaterialSummary item;
  final MaterialViewportAnchor viewportAnchor;
  final String queryKey;
  final MaterialCatalogQuery catalogQuery;
  final List<MaterialSummary> items;

  @override
  Widget build(BuildContext context) {
    final roles = HarukaColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final coverColor = switch (item.type) {
      LearningMaterialType.novel => roles.bookBlue,
      LearningMaterialType.textbook => Color.lerp(roles.bookGreen, scheme.surface, .48)!,
      LearningMaterialType.exam => roles.bookPeach,
    };
    return _identifiedMaterialRow(
      context,
      item.id,
      Card.outlined(
        key: viewportAnchor.keyFor(item.id),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
        ),
        child: InkWell(
          onTap: !materialCanOpen(context, item)
              ? null
              : () {
                  viewportAnchor.capture(item.id, queryKey, items);
                  unawaited(context.push(materialOpenPath(context, item.id)));
                },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MaterialCover(label: item.cover, color: coverColor, width: 58, height: 76),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _mobileMaterialMetadata(context, item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 11),
                      _MaterialStatus(item: item, compact: true, showProgress: false),
                    ],
                  ),
                ),
                _MobileMaterialMenu(
                  title: item.title,
                  onOpen: () => viewportAnchor.capture(item.id, queryKey, items, pending: false),
                  onDetails: () => unawaited(
                    _showMobileMaterialDetails(
                      context,
                      item,
                      query: catalogQuery,
                      onOpenMaterial: () => viewportAnchor.activate(item.id),
                    ),
                  ),
                  onDelete: !materialCanDelete(context, item)
                      ? null
                      : () => unawaited(_confirmDelete(context, item)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMaterialMenu extends StatefulWidget {
  const _MobileMaterialMenu({
    required this.title,
    required this.onOpen,
    required this.onDetails,
    this.onDelete,
  });

  final String title;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  final VoidCallback? onDelete;

  @override
  State<_MobileMaterialMenu> createState() => _MobileMaterialMenuState();
}

class _MobileMaterialMenuState extends State<_MobileMaterialMenu> {
  final _controller = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _open) _controller.close();
      },
      child: MenuAnchor(
        controller: _controller,
        alignmentOffset: const Offset(0, 4),
        consumeOutsideTap: true,
        animated: !HarukaMotion.reduced(context, reducedMotion: _libraryReducedMotion(context)),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomEnd,
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        onOpen: () {
          setState(() => _open = true);
          widget.onOpen();
        },
        onClose: () {
          if (mounted) setState(() => _open = false);
        },
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.menu_book_outlined, size: 20),
            onPressed: widget.onDetails,
            child: SizedBox(width: 138, child: Text(l10n.mockLibraryViewDetails)),
          ),
          if (widget.onDelete != null)
            MenuItemButton(
              leadingIcon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
              onPressed: widget.onDelete,
              child: SizedBox(
                width: 138,
                child: Text(l10n.mockLibraryDeleteMaterial, style: TextStyle(color: scheme.error)),
              ),
            ),
        ],
        builder: (context, controller, child) => IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          iconSize: 20,
          color: scheme.onSurfaceVariant,
          tooltip: l10n.mockLibraryMoreActions(widget.title),
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.more_horiz),
        ),
      ),
    );
  }
}

Future<void> _showMobileMaterialDetails(
  BuildContext context,
  MaterialSummary selected, {
  required MaterialCatalogQuery query,
  required VoidCallback onOpenMaterial,
}) async {
  final live = liveMaterialCatalog(context);
  if (live != null) {
    await showLiveMaterialDialog(
      context,
      live,
      selected.id,
      onOpenMaterial: () {
        onOpenMaterial();
        unawaited(context.push(materialOpenPath(context, selected.id)));
      },
    );
    return;
  }
  final pageContext = Navigator.of(context).context;
  final messenger = ScaffoldMessenger.of(context);
  final catalog = MaterialCatalogScope.of(context);
  if (!context.mounted || !pageContext.mounted) return;
  final item = catalog.findById(selected.id);
  if (catalog.status != MaterialCatalogStatus.ready ||
      item == null ||
      item.type != selected.type ||
      item.revision != selected.revision ||
      !catalog.filterMaterials(query).any((row) => row.id == selected.id)) {
    messenger.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(pageContext).mockMaterialUnavailableMessage)),
    );
    return;
  }
  final l10n = AppLocalizations.of(pageContext);
  final scheme = Theme.of(pageContext).colorScheme;
  await showHarukaDialog<void>(
    context: pageContext,
    animationStyle: HarukaMotion.dialogStyle(
      pageContext,
      reducedMotion: PreviewStoreScope.of(pageContext).reducedMotion,
    ),
    builder: (dialogContext) => HarukaDialogSurface(
      title: l10n.mockMaterialDetailsTitle,
      actions: [
        FilledButton(
          onPressed: item.status == 'processing'
              ? null
              : () {
                  Navigator.pop(dialogContext);
                  onOpenMaterial();
                  unawaited(pageContext.push(AppRoutes.mockMaterialPath(item.id)));
                },
          child: Text(l10n.mockLibraryOpenMaterial),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(materialTypeLabel(pageContext, item.type), style: TextStyle(color: scheme.primary)),
          const SizedBox(height: 8),
          Text(item.title, style: Theme.of(pageContext).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            _mobileMaterialMetadata(pageContext, item),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text(item.description),
          const SizedBox(height: 16),
          Text(materialStatusLabel(pageContext, item), style: TextStyle(color: scheme.primary)),
          const SizedBox(height: 8),
          Text(l10n.mockMaterialCurrentRevision(item.revision)),
        ],
      ),
    ),
  );
}

class DesktopLibraryView extends StatelessWidget {
  const DesktopLibraryView({
    required this.type,
    required this.searchController,
    required this.searchFocusNode,
    required this.onType,
    required this.onQuery,
    required this.results,
    this.allowImport = true,
    this.availableTypes,
    this.extraFilters,
    super.key,
  });
  final LearningMaterialType? type;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<LearningMaterialType?> onType;
  final ValueChanged<String> onQuery;
  final Widget results;
  final bool allowImport;
  final List<LearningMaterialType>? availableTypes;
  final Widget? extraFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.mockLibraryTitle, style: Theme.of(context).textTheme.headlineMedium),
            ),
            if (allowImport)
              FilledButton.icon(
                onPressed: () => context.push(materialImportPath(context)),
                icon: const Icon(Icons.add),
                label: Text(l10n.mockLibraryImport),
              ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final filters = <Widget>[
              HarukaPill(
                label: l10n.mockLibraryAll,
                selected: type == null,
                onTap: () => onType(null),
              ),
              for (final value in availableTypes ?? LearningMaterialType.values)
                HarukaPill(
                  label: materialTypeLabel(context, value),
                  selected: type == value,
                  onTap: () => onType(value),
                ),
            ];
            if (extraFilters != null) {
              filters.add(Padding(padding: const EdgeInsets.only(left: 12), child: extraFilters));
            }
            final search = _identifiedMaterialSearch(
              context,
              TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onQuery,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surface,
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.mockLibrarySearchHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide(color: scheme.outline.withValues(alpha: .7)),
                  ),
                ),
              ),
            );
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: filters),
                  const SizedBox(height: 12),
                  search,
                ],
              );
            }
            return Row(
              children: [
                ...filters,
                const Spacer(),
                SizedBox(width: 300, child: search),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Expanded(child: results),
      ],
    );
  }
}

class DesktopLibraryResults extends StatelessWidget {
  const DesktopLibraryResults({
    required this.items,
    required this.viewportAnchor,
    required this.type,
    required this.query,
    required this.onReset,
    this.continuation,
    super.key,
  });

  final List<MaterialSummary> items;
  final MaterialViewportAnchor viewportAnchor;
  final LearningMaterialType? type;
  final String query;
  final VoidCallback onReset;
  final Widget? continuation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final queryKey = '${type?.name ?? 'all'}-$query';
    return _RestoringMaterialList(
      key: ValueKey('library-desktop-$queryKey'),
      items: items,
      anchor: viewportAnchor,
      queryKey: queryKey,
      builder: (controller) => ListView(
        controller: controller,
        key: PageStorageKey('library-desktop-$queryKey'),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.mockLibraryRecentlyUpdated,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          if (items.isEmpty)
            HarukaEmpty(
              title: l10n.mockLibraryNoMatches,
              message: l10n.mockLibraryTryAnotherSearch,
              action: TextButton(onPressed: onReset, child: Text(l10n.mockLibraryResetFilters)),
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DesktopMaterialRow(
                item: item,
                viewportAnchor: viewportAnchor,
                queryKey: queryKey,
                items: items,
              ),
            ),
          ?continuation,
        ],
      ),
    );
  }
}

class DesktopMaterialRow extends StatelessWidget {
  const DesktopMaterialRow({
    required this.item,
    required this.viewportAnchor,
    required this.queryKey,
    required this.items,
    super.key,
  });
  final MaterialSummary item;
  final MaterialViewportAnchor viewportAnchor;
  final String queryKey;
  final List<MaterialSummary> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _identifiedMaterialRow(
      context,
      item.id,
      Card.outlined(
        key: viewportAnchor.keyFor(item.id),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
        ),
        child: InkWell(
          onTap: !materialCanOpen(context, item)
              ? null
              : () {
                  viewportAnchor.capture(item.id, queryKey, items);
                  unawaited(context.push(materialOpenPath(context, item.id)));
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final statusOnRight = constraints.maxWidth >= 700;
                return Row(
                  children: [
                    _MaterialCover(
                      label: item.cover,
                      color: switch (item.type) {
                        LearningMaterialType.novel => roles.bookBlue,
                        LearningMaterialType.textbook => roles.bookGreen,
                        LearningMaterialType.exam => roles.bookPeach,
                      },
                      width: 64,
                      height: 76,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _mobileMaterialMetadata(context, item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                          ),
                          if (!statusOnRight) ...[
                            const SizedBox(height: 8),
                            _MaterialStatus(
                              item: item,
                              showProgress: liveMaterialCatalog(context) == null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (statusOnRight) ...[
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 190,
                        child: _MaterialStatus(
                          item: item,
                          showProgress: liveMaterialCatalog(context) == null,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    PopupMenuButton<String>(
                      useRootNavigator: true,
                      tooltip: l10n.mockLibraryMoreActions(item.title),
                      onSelected: (value) {
                        if (value == 'detail') {
                          viewportAnchor.capture(item.id, queryKey, items);
                          unawaited(context.push(materialDetailsPath(context, item.id)));
                        } else {
                          unawaited(_confirmDelete(context, item));
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'detail', child: Text(l10n.mockLibraryViewDetails)),
                        if (materialCanDelete(context, item))
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.mockLibraryDeleteMaterial),
                          ),
                      ],
                    ),
                    IconButton(
                      tooltip: l10n.mockLibraryViewMaterial(item.title),
                      onPressed: !materialCanOpen(context, item)
                          ? null
                          : () {
                              viewportAnchor.capture(item.id, queryKey, items);
                              unawaited(context.push(materialOpenPath(context, item.id)));
                            },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MaterialCover extends StatelessWidget {
  const _MaterialCover({
    required this.label,
    required this.color,
    required this.width,
    required this.height,
  });

  final String label;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
          ),
          Center(child: Text(label, style: Theme.of(context).textTheme.titleLarge)),
        ],
      ),
    ),
  );
}

class _MaterialStatus extends StatelessWidget {
  const _MaterialStatus({required this.item, this.compact = false, this.showProgress = true});

  final MaterialSummary item;
  final bool compact;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final processing = item.status == 'processing';
    final statusColor = switch (item.status) {
      'readable' => roles.positive,
      'needs_review' => roles.warning,
      'processing' => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    final progress = (item.activeJobProgressPercent ?? 0).clamp(0, 100) / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              processing && showProgress
                  ? AppLocalizations.of(context)
                        .mockLibraryParsingProgress(item.activeJobProgressPercent ?? 0)
                  : materialStatusLabel(context, item),
              style: TextStyle(
                color: statusColor,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (processing && showProgress) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: compact ? double.infinity : 190,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _confirmDelete(BuildContext context, MaterialSummary item) async {
  final live = liveMaterialCatalog(context);
  if (live != null) {
    final row = live.metadata(item.id);
    if (row != null) await deleteLiveMaterial(context, live, row);
    return;
  }
  final l10n = AppLocalizations.of(context);
  final store = MaterialCatalogScope.of(context);
  final confirmed = await showHarukaDialog<bool>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: _libraryReducedMotion(context),
    ),
    builder: (dialogContext) => HarukaDialogSurface(
      title: l10n.mockLibraryDeleteConfirmTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.mockLibraryCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.mockLibraryDelete),
        ),
      ],
      child: Text(l10n.mockLibraryDeleteConfirmMessage(item.title)),
    ),
  );
  if (confirmed == true) await store.deleteMaterial(item.id);
}

class ImportPage extends StatefulWidget {
  const ImportPage({this.pickFileName, this.pickFile, this.sourceMaterialId, super.key});

  /// Selects a local file name; no file bytes enter the mock store.
  final Future<String?> Function()? pickFileName;
  final Future<XFile?> Function()? pickFile;
  final String? sourceMaterialId;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  int step = 0;
  LearningMaterialType type = LearningMaterialType.novel;
  String? fileName;
  bool aiStructure = false;
  XFile? _file;
  final _title = TextEditingController();
  String _language = 'ja';
  String _key = newRequestId();
  HttpMaterialCatalog? _live;
  Object? _scope;
  MaterialImportCapabilities? _capabilities;
  MaterialMetadata? _source;
  MaterialImport? _intent;
  MaterialImportDraft? _draft;
  bool _busy = false;
  bool _unknown = false;
  Object? _error;
  bool get _current => mounted && _live?.isCurrent(_scope!) == true;
  bool get _canSubmit =>
      _live != null &&
      _title.text.trim().runes.length <= 200 &&
      materialImportTypeAllowed(_live!, type) &&
      (widget.sourceMaterialId == null ||
          (_source != null && materialReuseAllowed(_live!, _source!)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final live = liveMaterialCatalog(context);
    if (live == null) return;
    if (_scope == live.scopeIdentity) {
      _restoreDraft(live.importDraft);
      return;
    }
    _live = live;
    _scope = live.scopeIdentity;
    _file = null;
    fileName = null;
    _intent = null;
    _capabilities = null;
    _source = null;
    _title.clear();
    _key = newRequestId();
    _busy = false;
    _unknown = false;
    _error = null;
    step = 0;
    _draft = null;
    _restoreDraft(live.importDraft);
    final scope = _scope;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadCapabilities(scope)));
  }

  void _restoreDraft(MaterialImportDraft? draft) {
    if (draft == null) return;
    if (!identical(_draft, draft) && !draft.busy && draft.intent != null) draft.unknown = true;
    _draft = draft;
    _file = draft.file;
    fileName = draft.file?.name ?? draft.source?.title ?? draft.title;
    _source = draft.source;
    type = draft.type;
    _language = draft.language;
    _title.text = draft.title;
    _key = draft.key;
    _intent = draft.intent;
    _busy = draft.busy;
    _unknown = draft.unknown;
    _error = draft.error;
    step = 2;
  }

  Future<void> _loadCapabilities(Object? scope) async {
    try {
      final caps = await _live!.imports.capabilities();
      if (!mounted || _scope != scope || !_current) return;
      final source = widget.sourceMaterialId == null
          ? null
          : await _live!.detail(widget.sourceMaterialId!);
      if (!mounted || _scope != scope || !_current) return;
      setState(() {
        _capabilities = caps;
        if (_draft == null) _source = source;
        if (source != null && _draft == null) {
          fileName = source.title;
          _title.text = source.title;
          _language = source.language ?? 'ja';
        }
      });
    } on Object catch (error) {
      if (mounted && _scope == scope) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> selectFile() async {
    if (_live != null) {
      if (_busy || _draft != null || widget.sourceMaterialId != null) return;
      final scope = _scope;
      final selected = await (widget.pickFile?.call() ?? openFile());
      if (!mounted || !_current || _scope != scope || selected == null) return;
      setState(() {
        _file = selected;
        fileName = selected.name;
        _key = newRequestId();
        _title.text = selected.name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
        _error = null;
      });
      return;
    }
    final selected = await (widget.pickFileName?.call() ?? _chooseFileName());
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    setState(() => fileName = selected.trim());
  }

  Future<String?> _chooseFileName() async => (await openFile())?.name;

  Future<void> next() async {
    if (_live != null) {
      await _nextLive();
      return;
    }
    if (step == 1 && fileName == null) return;
    if (step < 2) {
      setState(() => step++);
      return;
    }
    final name = fileName!;
    final title = name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
    await MaterialCatalogScope.of(context).importMaterial(type, title.isEmpty ? name : title, 'ja');
    if (!mounted) return;
    context.go(AppRoutes.mockLibrary);
  }

  Future<void> _nextLive() async {
    final live = _live!;
    if (!_current || !_canSubmit || _busy || _capabilities == null) return;
    if (step < 2) {
      if (step == 1 && fileName == null) return;
      setState(() => step++);
      return;
    }
    final scope = _scope!;
    final draft =
        _draft ??
        MaterialImportDraft(
          scope: scope,
          key: _key,
          type: type,
          language: _language,
          title: _title.text,
          file: _file,
          source: _source,
        );
    _draft = draft;
    draft.busy = true;
    draft.error = null;
    live.retainImport(draft);
    try {
      var intent = draft.intent;
      if (intent == null) {
        intent = draft.source == null
            ? await live.imports.create(
                file: draft.file!,
                type: draft.type,
                language: draft.language,
                title: draft.title,
                idempotencyKey: draft.key,
              )
            : await live.imports.reimportExisting(
                sourceId: draft.source!.id,
                targetType: draft.type,
                language: draft.language,
                title: draft.title,
                idempotencyKey: draft.key,
              );
        if (!live.isCurrent(scope)) return;
        draft.intent = intent;
        live.retainImport(draft);
      }
      if (draft.unknown ||
          intent.status == 'verifying' ||
          (intent.status == 'awaiting_upload' && draft.file == null)) {
        intent = await live.imports.find(intent.id);
        if (!live.isCurrent(scope)) return;
        draft.intent = intent;
        draft.unknown = false;
        live.retainImport(draft);
      } else if (intent.status == 'awaiting_upload') {
        draft.unknown = true;
        live.retainImport(draft);
        intent = await live.imports.uploadAndComplete(intent, draft.file!);
        if (!live.isCurrent(scope)) return;
        draft.intent = intent;
        draft.unknown = false;
        live.retainImport(draft);
      }
      if (intent.accepted) {
        live.record('material.import.submitted', draft.type, 'success');
        live.clearImport(draft);
        await live.acceptedImport();
        if (mounted && _scope == scope && _current) context.go(AppRoutes.materials);
      }
    } on Object catch (error) {
      if (live.isCurrent(scope)) {
        draft.error = error;
        if (draft.intent == null && error is ApiFailure && error.code == 'INPUT_INVALID') {
          live.clearImport(draft);
          if (mounted && _scope == scope) {
            _draft = null;
            setState(() {
              _busy = false;
              _error = error;
            });
          }
        }
        if (!draft.unknown) {
          live.record(
            'material.import.submitted',
            draft.type,
            error is ApiFailure && error.code == 'PERMISSION_DENIED' ? 'denied' : 'failure',
          );
        }
      }
    } finally {
      draft.busy = false;
      if (live.isCurrent(scope) &&
          identical(live.importDraft, draft) &&
          draft.intent?.accepted != true) {
        live.retainImport(draft);
      }
      if (mounted && _scope == scope) {
        setState(() {
          _busy = false;
          _restoreDraft(live.importDraft);
        });
      }
    }
  }

  Future<void> _cancelIntent() async {
    final intent = _intent;
    if (intent == null || _busy || !_current) return;
    final scope = _scope;
    setState(() => _busy = true);
    if (_draft case final draft?) {
      draft.busy = true;
      _live!.retainImport(draft);
    }
    try {
      await _live!.imports.cancel(intent);
      if (!mounted || _scope != scope || !_current) return;
      _live!.record('material.import.submitted', type, 'cancelled');
      if (_draft case final draft?) _live!.clearImport(draft);
      setState(() {
        _intent = null;
        _draft = null;
        _file = null;
        fileName = null;
        _unknown = false;
        _key = newRequestId();
        step = 1;
      });
    } on Object catch (error) {
      if (mounted && _scope == scope) setState(() => _error = error);
    } finally {
      if (_draft case final draft?) {
        draft.busy = false;
        if (_live!.isCurrent(scope!) && identical(_live!.importDraft, draft)) {
          _live!.retainImport(draft);
        }
      }
      if (mounted && _scope == scope) setState(() => _busy = false);
    }
  }

  void _restartTerminal() {
    if (_busy ||
        !_current ||
        !const {'expired', 'cancelled', 'rejected'}.contains(_intent?.status)) {
      return;
    }
    if (_draft case final draft?) _live!.clearImport(draft);
    setState(() {
      _draft = null;
      _intent = null;
      _file = null;
      fileName = _source?.title;
      _unknown = false;
      _error = null;
      _key = newRequestId();
      step = 1;
    });
  }

  void back() {
    if (_busy || _intent != null) return;
    if (step > 0) {
      setState(() => step--);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(materialLibraryPath(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formal = _live != null;
    final capability = _capabilities?.forType(type);
    final extra = !formal
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_capabilities == null && _error == null) const LinearProgressIndicator(),
              if (step == 1) ...[
                const SizedBox(height: 16),
                Identified(
                  id: UiTestIds.materialImportTitle,
                  child: TextField(
                    controller: _title,
                    enabled: !_busy && _draft == null,
                    maxLength: 200,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: l10n.materialTitle),
                  ),
                ),
                Identified(
                  id: UiTestIds.materialImportLanguage,
                  child: DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: InputDecoration(labelText: l10n.materialLanguage),
                    items: [
                      for (final lang in capability?.languages ?? const ['ja', 'en'])
                        DropdownMenuItem(
                          value: lang,
                          child: Text(
                            lang == 'ja' ? l10n.mockLibraryJapanese : l10n.mockLibraryEnglish,
                          ),
                        ),
                    ],
                    onChanged: _busy || _draft != null
                        ? null
                        : (value) => setState(() {
                            _language = value!;
                            _key = newRequestId();
                          }),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${l10n.materialFormats}：${capability?.formats.map((f) => '${f.toUpperCase()} ≤ ${((capability.limitFor(f)) / 1000000).toStringAsFixed(1)} MB').join(' · ') ?? '—'}',
                ),
                Text(
                  '${l10n.materialCapacity}：${((_capabilities?.availableBytes ?? 0) / 1000000).toStringAsFixed(1)} MB',
                ),
              ],
              if (step == 2) ...[
                const SizedBox(height: 16),
                Text(_title.text),
                Text(_language == 'ja' ? l10n.mockLibraryJapanese : l10n.mockLibraryEnglish),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                Text(l10n.materialUploadBusy),
              ],
              if (_intent != null && !_intent!.accepted)
                Identified(
                  id: UiTestIds.materialImportState,
                  child: Text(
                    _unknown
                        ? l10n.materialImportUnknown
                        : switch (_intent!.status) {
                            'verifying' => l10n.materialImportVerifying,
                            'expired' => l10n.materialImportExpired,
                            'cancelled' => l10n.materialImportCancelled,
                            'rejected' => l10n.materialImportRejected,
                            _ => l10n.mockLibraryConfirmImport,
                          },
                  ),
                ),
              if (_error != null)
                Text(
                  l10n.apiUnknownError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_intent != null &&
                  !_intent!.accepted &&
                  !const {'cancelled', 'expired', 'rejected'}.contains(_intent!.status))
                TextButton(
                  onPressed: _busy ? null : _cancelIntent,
                  child: Text(l10n.materialImportCancel),
                ),
              if (const {'cancelled', 'expired', 'rejected'}.contains(_intent?.status))
                TextButton(onPressed: _busy ? null : _restartTerminal, child: Text(l10n.authRetry)),
              if (_capabilities == null && _error != null)
                TextButton(
                  onPressed: () => unawaited(_loadCapabilities(_scope)),
                  child: Text(l10n.authRetry),
                ),
            ],
          );
    final canNext =
        !formal ||
        (_current &&
            _canSubmit &&
            !_busy &&
            capability != null &&
            !const {'cancelled', 'expired', 'rejected'}.contains(_intent?.status) &&
            (_source == null || type != _source!.type));
    final nextLabel = formal && (_unknown || _intent?.status == 'verifying')
        ? l10n.materialImportObserve
        : formal && _intent?.status == 'awaiting_upload'
        ? l10n.materialImportRetryUpload
        : null;
    return Identified(
      id: UiTestIds.materialImportPage,
      child: PreviewPageFrame(
        location: materialImportPath(context),
        title: l10n.mockLibraryImport,
        detail: true,
        detailNotifications: false,
        mobileHeader: Row(
          children: [
            IconButton(
              tooltip: l10n.mockShellBack,
              onPressed: back,
              icon: const Icon(Icons.arrow_back_ios_new, size: 19),
            ),
            Text(l10n.mockLibraryImport, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        mobile: MobileImportView(
          extra: extra,
          formal: formal,
          allowedTypes: formal
              ? LearningMaterialType.values
                    .where((value) => materialImportTypeAllowed(_live!, value))
                    .toList()
              : null,
          fileFormat: _source?.sourceFormat ?? (_file == null ? null : sourceFormat(_file!.name)),
          allowNext: canNext,
          nextLabel: nextLabel,
          step: step,
          type: type,
          fileName: fileName,
          aiStructure: aiStructure,
          onType: (value) {
            if (!_busy && _draft == null) {
              setState(() {
                type = value;
                _key = newRequestId();
              });
            }
          },
          onAiStructure: (value) => setState(() => aiStructure = value),
          onFile: selectFile,
          onNext: next,
        ),
        desktop: DesktopImportView(
          extra: extra,
          formal: formal,
          allowedTypes: formal
              ? LearningMaterialType.values
                    .where((value) => materialImportTypeAllowed(_live!, value))
                    .toList()
              : null,
          fileFormat: _source?.sourceFormat ?? (_file == null ? null : sourceFormat(_file!.name)),
          allowNext: canNext,
          nextLabel: nextLabel,
          step: step,
          type: type,
          fileName: fileName,
          aiStructure: aiStructure,
          onType: (value) {
            if (!_busy && _draft == null) {
              setState(() {
                type = value;
                _key = newRequestId();
              });
            }
          },
          onAiStructure: (value) => setState(() => aiStructure = value),
          onFile: selectFile,
          onNext: next,
          onBack: back,
        ),
      ),
    );
  }
}

IconData _importTypeIcon(LearningMaterialType type) => switch (type) {
  LearningMaterialType.novel => Icons.menu_book_outlined,
  LearningMaterialType.textbook => Icons.library_books_outlined,
  LearningMaterialType.exam => Icons.edit_outlined,
};

String _importTypeDescription(AppLocalizations l10n, LearningMaterialType type) => switch (type) {
  LearningMaterialType.novel => l10n.mockLibraryNovelDescription,
  LearningMaterialType.textbook => l10n.mockLibraryTextbookDescription,
  LearningMaterialType.exam => l10n.mockLibraryExamDescription,
};

class MobileImportView extends StatelessWidget {
  const MobileImportView({
    required this.step,
    required this.type,
    required this.fileName,
    required this.aiStructure,
    required this.onType,
    required this.onAiStructure,
    required this.onFile,
    required this.onNext,
    this.extra,
    this.formal = false,
    this.fileFormat,
    this.allowedTypes,
    this.allowNext = true,
    this.nextLabel,
    super.key,
  });

  final Widget? extra;
  final bool formal, allowNext;
  final String? fileFormat;
  final List<LearningMaterialType>? allowedTypes;
  final String? nextLabel;
  final int step;
  final LearningMaterialType type;
  final String? fileName;
  final bool aiStructure;
  final ValueChanged<LearningMaterialType> onType;
  final ValueChanged<bool> onAiStructure;
  final VoidCallback onFile;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 31, 20, 24),
            children: [
              Text(
                l10n.mockLibraryImportStepType(step + 1, 3, materialTypeLabel(context, type)),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(switch (step) {
                0 => l10n.mockLibraryChooseType,
                1 => l10n.mockLibraryChooseFile,
                _ => l10n.mockLibraryConfirmImport,
              }, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 17),
              Row(
                children: [
                  for (var index = 0; index < 3; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: AnimatedContainer(
                        duration:
                            HarukaMotion.reduced(
                              context,
                              reducedMotion: _libraryReducedMotion(context),
                            )
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        height: 3,
                        decoration: BoxDecoration(
                          color: index <= step
                              ? scheme.primary
                              : scheme.outline.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              if (step == 0)
                for (final candidate in allowedTypes ?? LearningMaterialType.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card.outlined(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      color: type == candidate ? roles.selected : scheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: type == candidate
                              ? scheme.primary
                              : scheme.outline.withValues(alpha: .12),
                        ),
                      ),
                      child: Identified(
                        id: _importTypeId(candidate),
                        child: InkWell(
                          onTap: () => onType(candidate),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: roles.selected,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _importTypeIcon(candidate),
                                    color: scheme.primary,
                                    size: 23,
                                  ),
                                ),
                                const SizedBox(width: 17),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        materialTypeLabel(context, candidate),
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _importTypeDescription(l10n, candidate),
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  type == candidate
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: type == candidate
                                      ? scheme.primary
                                      : scheme.outline.withValues(alpha: .3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
              else if (step == 1)
                HarukaSurface(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: Column(
                    children: [
                      Icon(Icons.upload_outlined, size: 36, color: scheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        l10n.mockLibraryChooseFile,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Identified(
                        id: UiTestIds.materialImportFile,
                        child: OutlinedButton.icon(
                          onPressed: onFile,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(l10n.mockLibraryChooseMaterialFile),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        fileName == null
                            ? l10n.mockLibraryNoFileSelected
                            : l10n.mockLibrarySelectedFile(fileName!),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 55),
                      if (!formal)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: aiStructure,
                          onChanged: (value) => onAiStructure(value ?? false),
                          title: Text(
                            formal
                                ? l10n.materialSourceFormat
                                : l10n.mockLibraryAiStructureSuggestion,
                          ),
                          subtitle: Text(l10n.mockLibraryAiStructureDescription),
                        ),
                    ],
                  ),
                )
              else
                HarukaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.mockLibraryMaterialTypeStep,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        materialTypeLabel(context, type),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.mockLibraryChooseFile,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      Text(fileName ?? '', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 18),
                      Text(
                        formal ? l10n.materialSourceFormat : l10n.mockLibraryAiStructureSuggestion,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        formal
                            ? fileFormat?.toUpperCase() ?? '—'
                            : aiStructure
                            ? l10n.mockLibraryAiStructureEnabled
                            : l10n.mockLibraryAiStructureDisabled,
                      ),
                      if (formal) ...[
                        const SizedBox(height: 12),
                        Text(l10n.materialImportSourceBoundary),
                      ],
                    ],
                  ),
                ),
              ?extra,
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: .2))),
          ),
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 15),
          child: Identified(
            id: UiTestIds.materialImportNext,
            child: FilledButton(
              style: FilledButton.styleFrom(
                disabledBackgroundColor: scheme.primary.withValues(alpha: .5),
                disabledForegroundColor: scheme.onPrimary,
              ),
              onPressed: !allowNext || (step == 1 && fileName == null) ? null : onNext,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    nextLabel ?? (step == 2 ? l10n.mockLibraryConfirmImport : l10n.mockLibraryNext),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DesktopImportView extends StatelessWidget {
  const DesktopImportView({
    required this.step,
    required this.type,
    required this.fileName,
    required this.aiStructure,
    required this.onType,
    required this.onAiStructure,
    required this.onFile,
    required this.onNext,
    required this.onBack,
    this.extra,
    this.formal = false,
    this.fileFormat,
    this.allowedTypes,
    this.allowNext = true,
    this.nextLabel,
    super.key,
  });

  final Widget? extra;
  final bool formal, allowNext;
  final String? fileFormat;
  final List<LearningMaterialType>? allowedTypes;
  final String? nextLabel;
  final int step;
  final LearningMaterialType type;
  final String? fileName;
  final bool aiStructure;
  final ValueChanged<LearningMaterialType> onType;
  final ValueChanged<bool> onAiStructure;
  final VoidCallback onFile;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final stepLabels = [
      l10n.mockLibraryMaterialTypeStep,
      l10n.mockLibraryChooseFile,
      l10n.mockLibraryConfirmImport,
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Text(l10n.mockLibraryImport, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 32),
            Row(
              children: [
                for (var index = 0; index < 3; index++) ...[
                  if (index > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: index <= step
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: .22),
                            width: index <= step ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: index <= step ? scheme.primary : scheme.surface,
                            foregroundColor: index <= step
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            stepLabels[index],
                            style: TextStyle(
                              color: index <= step ? scheme.primary : scheme.onSurfaceVariant,
                              fontWeight: index == step ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 38),
            Text(stepLabels[step], style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 17),
            if (step == 0)
              Row(
                children: [
                  for (final candidate in allowedTypes ?? LearningMaterialType.values) ...[
                    if (candidate != LearningMaterialType.novel) const SizedBox(width: 12),
                    Expanded(
                      child: Card.outlined(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        color: candidate == type ? roles.selected : scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                          side: BorderSide(
                            color: candidate == type
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: .15),
                          ),
                        ),
                        child: Identified(
                          id: _importTypeId(candidate),
                          child: InkWell(
                            onTap: () => onType(candidate),
                            child: SizedBox(
                              height: 160,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _importTypeIcon(candidate),
                                          color: candidate == type
                                              ? scheme.primary
                                              : scheme.onSurface,
                                        ),
                                        const Spacer(),
                                        if (candidate == type)
                                          Icon(Icons.check, size: 18, color: scheme.primary),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      materialTypeLabel(context, candidate),
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else if (step == 1)
              HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.upload_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          l10n.mockLibraryChooseFile,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Identified(
                      id: UiTestIds.materialImportFile,
                      child: OutlinedButton.icon(
                        onPressed: onFile,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(l10n.mockLibraryChooseMaterialFile),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      fileName == null
                          ? l10n.mockLibraryNoFileSelected
                          : l10n.mockLibrarySelectedFile(fileName!),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 25),
                    if (!formal)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: aiStructure,
                        onChanged: (value) => onAiStructure(value ?? false),
                        title: Text(
                          formal
                              ? l10n.materialSourceFormat
                              : l10n.mockLibraryAiStructureSuggestion,
                        ),
                        subtitle: Text(l10n.mockLibraryAiStructureDescription),
                      ),
                  ],
                ),
              )
            else
              HarukaSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.mockLibraryMaterialTypeStep),
                    Text(
                      materialTypeLabel(context, type),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.mockLibraryChooseFile),
                    Text(fileName ?? '', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Text(
                      formal ? l10n.materialSourceFormat : l10n.mockLibraryAiStructureSuggestion,
                    ),
                    Text(
                      formal
                          ? fileFormat?.toUpperCase() ?? '—'
                          : aiStructure
                          ? l10n.mockLibraryAiStructureEnabled
                          : l10n.mockLibraryAiStructureDisabled,
                    ),
                    if (formal) ...[
                      const SizedBox(height: 12),
                      Text(l10n.materialImportSourceBoundary),
                    ],
                  ],
                ),
              ),
            ?extra,
            const SizedBox(height: 34),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (step > 0) ...[
                  OutlinedButton(onPressed: onBack, child: Text(l10n.mockLibraryBackToEdit)),
                  const SizedBox(width: 12),
                ],
                SizedBox(
                  width: 180,
                  child: Identified(
                    id: UiTestIds.materialImportNext,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        disabledBackgroundColor: scheme.primary.withValues(alpha: .5),
                        disabledForegroundColor: scheme.onPrimary,
                      ),
                      onPressed: !allowNext || (step == 1 && fileName == null) ? null : onNext,
                      child: Text(
                        nextLabel ??
                            (step == 2 ? l10n.mockLibraryConfirmImport : l10n.mockLibraryNext),
                      ),
                    ),
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

bool _libraryReducedMotion(BuildContext context) =>
    ShellPresentationScope.maybeOf(context)?.reducedMotion ??
    PreviewStoreScope.maybeOf(context)?.reducedMotion ??
    false;

String _importTypeId(LearningMaterialType type) => switch (type) {
  LearningMaterialType.novel => UiTestIds.materialImportNovel,
  LearningMaterialType.textbook => UiTestIds.materialImportTextbook,
  LearningMaterialType.exam => UiTestIds.materialImportExam,
};
Widget _identifiedMaterialRow(BuildContext context, String id, Widget child) =>
    liveMaterialCatalog(context) == null
    ? child
    : Identified(id: UiTestIds.referenceMaterialRow(id), child: child);

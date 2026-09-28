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
import 'material_catalog_scope.dart';
import 'material_catalog_access.dart';

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
    if (reference != null) return _buildPublishedFrame(context, reference);
    final listQuery = MaterialCatalogQuery(type: type, search: query);
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
    return PreviewPageFrame(
      location: AppRoutes.mockLibrary,
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
                  child: TextField(
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
        results: items == null
            ? const Center(child: CircularProgressIndicator())
            : MobileLibraryResults(
                items: items,
                viewportAnchor: _mobileViewportAnchor,
                type: type,
                query: query,
                onReset: resetFilters,
              ),
      ),
      desktop: DesktopLibraryView(
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
    super.key,
  });

  final LearningMaterialType? type;
  final bool searchOpen;
  final ValueChanged<LearningMaterialType?> onType;
  final Widget results;
  final bool allowImport;
  final List<LearningMaterialType>? availableTypes;

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
            Expanded(child: results),
          ],
        ),
        if (!searchOpen && allowImport)
          Positioned(
            right: 22,
            bottom: 22,
            child: FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.mockImport),
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
    super.key,
  });

  final List<MaterialSummary> items;
  final MaterialViewportAnchor viewportAnchor;
  final LearningMaterialType? type;
  final String query;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = HarukaMotion.reduced(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
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
    return Card.outlined(
      key: viewportAnchor.keyFor(item.id),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
      ),
      child: InkWell(
        onTap: item.status == 'processing'
            ? null
            : () {
                viewportAnchor.capture(item.id, queryKey, items);
                unawaited(context.push(AppRoutes.mockMaterialPath(item.id)));
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
                onDelete: () => unawaited(_confirmDelete(context, item)),
              ),
            ],
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
                onPressed: () => context.push(AppRoutes.mockImport),
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
            final search = TextField(
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
    super.key,
  });

  final List<MaterialSummary> items;
  final MaterialViewportAnchor viewportAnchor;
  final LearningMaterialType? type;
  final String query;
  final VoidCallback onReset;

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
    return Card.outlined(
      key: viewportAnchor.keyFor(item.id),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
      ),
      child: InkWell(
        onTap: item.status == 'processing'
            ? null
            : () {
                viewportAnchor.capture(item.id, queryKey, items);
                unawaited(context.push(AppRoutes.mockMaterialPath(item.id)));
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
                          _MaterialStatus(item: item),
                        ],
                      ],
                    ),
                  ),
                  if (statusOnRight) ...[
                    const SizedBox(width: 24),
                    SizedBox(width: 190, child: _MaterialStatus(item: item)),
                  ],
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    useRootNavigator: true,
                    tooltip: l10n.mockLibraryMoreActions(item.title),
                    onSelected: (value) {
                      if (value == 'detail') {
                        viewportAnchor.capture(item.id, queryKey, items);
                        unawaited(context.push(AppRoutes.mockMaterialDetailsPath(item.id)));
                      } else {
                        unawaited(_confirmDelete(context, item));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'detail', child: Text(l10n.mockLibraryViewDetails)),
                      PopupMenuItem(value: 'delete', child: Text(l10n.mockLibraryDeleteMaterial)),
                    ],
                  ),
                  IconButton(
                    tooltip: l10n.mockLibraryViewMaterial(item.title),
                    onPressed: item.status == 'processing'
                        ? null
                        : () {
                            viewportAnchor.capture(item.id, queryKey, items);
                            unawaited(context.push(AppRoutes.mockMaterialPath(item.id)));
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              );
            },
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
  final l10n = AppLocalizations.of(context);
  final store = MaterialCatalogScope.of(context);
  final confirmed = await showHarukaDialog<bool>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
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
  const ImportPage({this.pickFileName, super.key});

  /// Selects a local file name; no file bytes enter the mock store.
  final Future<String?> Function()? pickFileName;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  int step = 0;
  LearningMaterialType type = LearningMaterialType.novel;
  String? fileName;
  bool aiStructure = false;

  Future<void> selectFile() async {
    final selected = await (widget.pickFileName?.call() ?? _chooseFileName());
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    setState(() => fileName = selected.trim());
  }

  Future<String?> _chooseFileName() async => (await openFile())?.name;

  Future<void> next() async {
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

  void back() {
    if (step > 0) {
      setState(() => step--);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.mockLibrary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PreviewPageFrame(
      location: AppRoutes.mockImport,
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
        step: step,
        type: type,
        fileName: fileName,
        aiStructure: aiStructure,
        onType: (value) => setState(() => type = value),
        onAiStructure: (value) => setState(() => aiStructure = value),
        onFile: selectFile,
        onNext: next,
      ),
      desktop: DesktopImportView(
        step: step,
        type: type,
        fileName: fileName,
        aiStructure: aiStructure,
        onType: (value) => setState(() => type = value),
        onAiStructure: (value) => setState(() => aiStructure = value),
        onFile: selectFile,
        onNext: next,
        onBack: back,
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
    super.key,
  });

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
                              reducedMotion: PreviewStoreScope.of(context).reducedMotion,
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
                for (final candidate in LearningMaterialType.values)
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
                      OutlinedButton.icon(
                        onPressed: onFile,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(l10n.mockLibraryChooseMaterialFile),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        fileName == null
                            ? l10n.mockLibraryNoFileSelected
                            : l10n.mockLibrarySelectedFile(fileName!),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                      const SizedBox(height: 55),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: aiStructure,
                        onChanged: (value) => onAiStructure(value ?? false),
                        title: Text(l10n.mockLibraryAiStructureSuggestion),
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
                        l10n.mockLibraryAiStructureSuggestion,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        aiStructure
                            ? l10n.mockLibraryAiStructureEnabled
                            : l10n.mockLibraryAiStructureDisabled,
                      ),
                    ],
                  ),
                ),
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
          child: FilledButton(
            style: FilledButton.styleFrom(
              disabledBackgroundColor: scheme.primary.withValues(alpha: .5),
              disabledForegroundColor: scheme.onPrimary,
            ),
            onPressed: step == 1 && fileName == null ? null : onNext,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(step == 2 ? l10n.mockLibraryConfirmImport : l10n.mockLibraryNext),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 18),
              ],
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
    super.key,
  });

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
                  for (final candidate in LearningMaterialType.values) ...[
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
                    OutlinedButton.icon(
                      onPressed: onFile,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(l10n.mockLibraryChooseMaterialFile),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      fileName == null
                          ? l10n.mockLibraryNoFileSelected
                          : l10n.mockLibrarySelectedFile(fileName!),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 25),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: aiStructure,
                      onChanged: (value) => onAiStructure(value ?? false),
                      title: Text(l10n.mockLibraryAiStructureSuggestion),
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
                    Text(l10n.mockLibraryAiStructureSuggestion),
                    Text(
                      aiStructure
                          ? l10n.mockLibraryAiStructureEnabled
                          : l10n.mockLibraryAiStructureDisabled,
                    ),
                  ],
                ),
              ),
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
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: scheme.primary.withValues(alpha: .5),
                      disabledForegroundColor: scheme.onPrimary,
                    ),
                    onPressed: step == 1 && fileName == null ? null : onNext,
                    child: Text(step == 2 ? l10n.mockLibraryConfirmImport : l10n.mockLibraryNext),
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

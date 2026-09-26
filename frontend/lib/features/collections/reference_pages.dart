import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/learning_models.dart';
import '../../core/auth/auth_controller.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import 'reference_controller.dart';
import 'reference_selection.dart';

const _ink = Color(0xff152b42);
const _muted = Color(0xff58697b);
const _blue = Color(0xff2457ed);
const _softBlue = Color(0xffe8efff);
const _line = Color(0xffdde5ee);
bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 900;

class ReferenceMaterialsPage extends ConsumerStatefulWidget {
  const ReferenceMaterialsPage({required this.scope, super.key});
  final String scope;
  @override
  ConsumerState<ReferenceMaterialsPage> createState() => _ReferenceMaterialsPageState();
}

class _ReferenceMaterialsPageState extends ConsumerState<ReferenceMaterialsPage> {
  bool _reading = false;
  int _openIntent = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(referenceControllerProvider(widget.scope)).loadMaterials());
    });
  }

  Future<void> _open(ReferenceController state, MaterialSummary material) async {
    if (state.busy) return;
    final intent = ++_openIntent;
    await state.openMaterial(material);
    if (!mounted ||
        intent != _openIntent ||
        state.error != null ||
        state.chapter == null ||
        state.material?.id != material.id) {
      return;
    }
    setState(() => _reading = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceControllerProvider(widget.scope));
    final strings = AppLocalizations.of(context);
    return Identified(
      id: UiTestIds.referenceMaterialsPage,
      child: _ReferenceScaffold(
        title: _reading && state.material != null
            ? state.material!.title
            : strings.referenceMaterialsTitle,
        backTooltip: _reading ? strings.referenceMaterialsTitle : strings.authBackToAccount,
        plainCompactReader: _reading,
        onBack: () {
          ++_openIntent;
          if (_reading) {
            setState(() => _reading = false);
          } else {
            context.go('/account');
          }
        },
        maxWidth: _reading ? 1840 : 1000,
        child: _reading
            ? _ReaderView(state: state, strings: strings)
            : _MaterialList(
                state: state,
                strings: strings,
                onOpen: (m) => unawaited(_open(state, m)),
              ),
      ),
    );
  }
}

class _MaterialList extends StatelessWidget {
  const _MaterialList({required this.state, required this.strings, required this.onOpen});
  final ReferenceController state;
  final AppLocalizations strings;
  final ValueChanged<MaterialSummary> onOpen;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_compact(context)) ...[
        Text(strings.referenceMaterialsTitle, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
      ],
      Row(
        children: [
          Expanded(
            child: Text(
              '小说 · ${state.materials.length} 份已发布材料',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          if (state.canListCollections) _CollectionsLink(strings: strings),
        ],
      ),
      const SizedBox(height: 16),
      if (state.error != null)
        _ErrorPanel(state: state, strings: strings, retry: state.loadMaterials),
      if (state.busy) const LinearProgressIndicator(),
      if (state.loading && state.materials.isEmpty) const LinearProgressIndicator(),
      if (!state.loading && state.materials.isEmpty && state.error == null)
        _EmptyPanel(message: strings.referenceNoMaterials),
      for (final material in state.materials)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Identified(
            id: UiTestIds.referenceMaterialRow(material.id),
            merge: true,
            child: _MaterialRow(
              material: material,
              language: material.language == 'ja'
                  ? strings.referenceJapanese
                  : strings.referenceEnglish,
              onTap: state.busy ? null : () => onOpen(material),
            ),
          ),
        ),
      if (state.materialCursor != null)
        Center(
          child: TextButton(
            onPressed: state.loading ? null : () => state.loadMaterials(more: true),
            child: Text(strings.referenceLoadMore),
          ),
        ),
      if (state.loading && state.materials.isNotEmpty) const LinearProgressIndicator(),
    ],
  );
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.material, required this.language, required this.onTap});
  final MaterialSummary material;
  final String language;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final initial = material.title.isEmpty ? '文' : String.fromCharCode(material.title.runes.first);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _softBlue, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  initial,
                  style: const TextStyle(color: _blue, fontFamily: 'serif', fontSize: 27),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text('小说 · $language', style: const TextStyle(color: _muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    const Text('可阅读', style: TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderView extends StatelessWidget {
  const _ReaderView({required this.state, required this.strings});
  final ReferenceController state;
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) {
    final material = state.material;
    if (material == null) return const SizedBox.shrink();
    final compact = _compact(context);
    final chapter = state.chapter;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final rightPanel = !compact && viewportWidth >= 1280 && state.resolved != null;
    final chapterWidth = viewportWidth >= 1800 ? 220.0 : 180.0;
    final panelWidth = viewportWidth >= 1800 ? 520.0 : 360.0;
    final result = state.resolved == null
        ? null
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: state.resolved!.found
                ? _WordCardPanel(
                    key: ValueKey(state.resolved!.card!.id),
                    state: state,
                    strings: strings,
                  )
                : _EmptyPanel(
                    key: const ValueKey('missing'),
                    message: strings.referenceNoPreparedCard,
                  ),
          );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const _Pill(label: '阅读', icon: Icons.menu_book_outlined),
                const Spacer(),
                if (state.canListCollections) _CollectionsLink(strings: strings),
              ],
            ),
          ),
        if (state.error != null)
          _ErrorPanel(
            state: state,
            strings: strings,
            retry: chapter == null ? () => state.openMaterial(material) : null,
          ),
        if (state.busy && chapter == null) const LinearProgressIndicator(),
        if (chapter != null) ...[
          if (compact)
            _ReadingPaper(chapter: chapter, state: state, strings: strings)
          else
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: _ReadingPaper(chapter: chapter, state: state, strings: strings),
              ),
            ),
          if (!rightPanel && result != null) ...[const SizedBox(height: 20), result],
        ],
      ],
    );
    if (compact) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: chapterWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 18, right: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Pill(label: '小说', icon: Icons.menu_book_outlined),
                const SizedBox(height: 20),
                Text(
                  material.title,
                  style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  material.language == 'ja' ? strings.referenceJapanese : strings.referenceEnglish,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 28),
                const Text('已发布章节', style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 10),
                if (chapter != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _softBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      chapter.title,
                      style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 20),
                if (state.canListCollections) _CollectionsLink(strings: strings),
              ],
            ),
          ),
        ),
        Expanded(child: body),
        if (rightPanel && result != null) ...[
          const SizedBox(width: 24),
          SizedBox(width: panelWidth, child: result),
        ],
      ],
    );
  }
}

class _ReadingPaper extends StatelessWidget {
  const _ReadingPaper({required this.chapter, required this.state, required this.strings});
  final NovelChapter chapter;
  final ReferenceController state;
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) {
    final compact = _compact(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 56, vertical: compact ? 16 : 48),
      decoration: compact
          ? null
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _line),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('已发布章节', style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            chapter.title,
            style: TextStyle(
              color: _ink,
              fontFamily: 'serif',
              fontSize: compact ? 25 : 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(strings.referenceSelectHint, style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 22),
          for (final block in chapter.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Identified(
                id: UiTestIds.referenceBlock(block.id),
                child: SelectableText(
                  block.text,
                  key: ValueKey(block.id),
                  style: TextStyle(
                    color: _ink,
                    fontFamily: 'serif',
                    fontSize: compact ? 19 : 20,
                    height: 1.95,
                  ),
                  onSelectionChanged: (selection, cause) {
                    final selected = ReferenceSelection.fromTextSelection(block, selection);
                    if (selected != null) {
                      state.select(selected);
                    } else if (!selection.isCollapsed || cause == SelectionChangedCause.tap) {
                      // Toolbar transitions may collapse a still-visible selection.
                      state.select(null);
                    }
                  },
                ),
              ),
            ),
          const Divider(color: _line),
          const SizedBox(height: 12),
          if (state.selectedSelection != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: _softBlue, borderRadius: BorderRadius.circular(10)),
              child: Text(
                state.selectedSelection!.locator.quote,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.selectedSelection == null ? strings.referenceSelectHint : '已选原文',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Identified(
                id: UiTestIds.referenceQuery,
                merge: true,
                child: FilledButton.icon(
                  onPressed: state.selectedBlock == null || state.busy || !state.canResolve
                      ? null
                      : state.resolve,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(strings.referenceQuery),
                ),
              ),
            ],
          ),
          if (state.busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
        ],
      ),
    );
  }
}

class _WordCardPanel extends StatelessWidget {
  const _WordCardPanel({required this.state, required this.strings, super.key});
  final ReferenceController state;
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) {
    final card = state.resolved!.card!;
    return _LearningCard(
      payload: card.payload,
      sources: card.sourceRefs,
      language: card.targetLanguage,
      strings: strings,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.saved != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Identified(
                id: UiTestIds.referenceSavedState,
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: _blue),
                    const SizedBox(width: 8),
                    Expanded(child: Text(strings.referenceSaved)),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Identified(
              id: UiTestIds.referenceSave,
              merge: true,
              child: FilledButton.icon(
                onPressed: state.busy || state.saved != null || !state.canSave ? null : state.save,
                icon: Icon(state.saved == null ? Icons.bookmark_add_outlined : Icons.check),
                label: Text(state.saved == null ? strings.referenceSave : strings.referenceSaved),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CollectionsPage extends ConsumerStatefulWidget {
  const CollectionsPage({required this.scope, super.key});
  final String scope;
  @override
  ConsumerState<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends ConsumerState<CollectionsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(referenceControllerProvider(widget.scope)).loadCollections());
    });
  }

  void _showDetail(CollectionRead collection, AppLocalizations strings) {
    Widget content(BuildContext dialogContext) => Consumer(
      builder: (dialogContext, ref, _) {
        final auth = ref.watch(authControllerProvider);
        if (!auth.isAuthenticated || referenceScope(auth, 'collections') != widget.scope) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (dialogContext.mounted && ModalRoute.of(dialogContext)?.isCurrent == true) {
              Navigator.of(dialogContext).pop();
            }
          });
          return const SizedBox.shrink();
        }
        return _CollectionDetail(collection: collection, strings: strings);
      },
    );
    if (_compact(context)) {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: Colors.white,
          constraints: const BoxConstraints(maxWidth: 560),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (dialogContext) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: content(dialogContext),
            ),
          ),
        ),
      );
    } else {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            contentPadding: const EdgeInsets.all(28),
            content: SizedBox(
              width: 510,
              child: SingleChildScrollView(child: content(dialogContext)),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceControllerProvider(widget.scope));
    final strings = AppLocalizations.of(context);
    return Identified(
      id: UiTestIds.referenceCollectionsPage,
      child: _ReferenceScaffold(
        title: strings.referenceCollectionsTitle,
        backTooltip: strings.authBackToAccount,
        onBack: () => context.go('/account'),
        maxWidth: 1020,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_compact(context)) ...[
              Text(
                strings.referenceCollectionsTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                const _Pill(label: '全部收藏', icon: Icons.bookmarks_outlined),
                const Spacer(),
                if (state.collectionsLoaded)
                  Text(
                    '${state.collections.length} 条收藏',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (state.error != null)
              _ErrorPanel(state: state, strings: strings, retry: state.loadCollections),
            if (state.loading && !state.collectionsLoaded) const LinearProgressIndicator(),
            if (state.collectionsLoaded)
              Identified(
                id: UiTestIds.referenceCollectionsLoaded,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var index = 0; index < state.collections.length; index++) ...[
                        if (index > 0) const Divider(height: 1, color: _line),
                        Identified(
                          id: UiTestIds.referenceCollectionRow(state.collections[index].id),
                          merge: true,
                          child: _CollectionRow(
                            collection: state.collections[index],
                            onTap: () => _showDetail(state.collections[index], strings),
                          ),
                        ),
                      ],
                      if (state.collections.isEmpty && !state.loading && state.error == null)
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            strings.referenceNoCollections,
                            style: const TextStyle(color: _muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (state.collectionCursor != null)
              Center(
                child: TextButton(
                  onPressed: state.loading ? null : () => state.loadCollections(more: true),
                  child: Text(strings.referenceLoadMore),
                ),
              ),
            if (state.loading && state.collectionsLoaded) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection, required this.onTap});
  final CollectionRead collection;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final compact = _compact(context);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 13 : 17),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _softBlue, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.menu_book_outlined, size: 18, color: _blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          collection.displayText,
                          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
                        ),
                        if (collection.payload.reading != null)
                          Text(
                            collection.payload.reading!,
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                      ],
                    ),
                    if (compact)
                      Text(
                        collection.payload.contextMeaning,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (!compact)
                Expanded(
                  flex: 2,
                  child: Text(
                    collection.payload.contextMeaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              const SizedBox(width: 10),
              const Text('单词', style: TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: _blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionDetail extends StatelessWidget {
  const _CollectionDetail({required this.collection, required this.strings});
  final CollectionRead collection;
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '收藏详情',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: strings.referenceClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _LearningCard(
        payload: collection.payload,
        sources: collection.sourceRefs,
        language: collection.targetLanguage,
        strings: strings,
        framed: false,
      ),
    ],
  );
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({
    required this.payload,
    required this.sources,
    required this.language,
    required this.strings,
    this.footer,
    this.framed = true,
  });
  final WordCardPayload payload;
  final List<NovelContentLocator> sources;
  final String language;
  final AppLocalizations strings;
  final Widget? footer;
  final bool framed;
  @override
  Widget build(BuildContext context) {
    final compact = _compact(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22, vertical: 13),
          color: _softBlue,
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 19, color: _blue),
              const SizedBox(width: 8),
              const Text(
                '单词',
                style: TextStyle(color: _blue, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                language == 'ja' ? strings.referenceJapanese : strings.referenceEnglish,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 24, compact ? 16 : 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                payload.term,
                style: TextStyle(
                  color: _ink,
                  fontSize: compact ? 27 : 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (payload.reading != null || payload.partOfSpeech.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (payload.reading != null)
                      Text(payload.reading!, style: const TextStyle(color: _muted, fontSize: 14)),
                    if (payload.partOfSpeech.isNotEmpty) _Pill(label: payload.partOfSpeech),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: _blue, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('释义', style: TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        payload.contextMeaning,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (payload.otherMeanings.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${strings.referenceOtherMeanings}：${payload.otherMeanings.join('；')}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 22),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 18),
              Text(strings.referenceExamples, style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 10),
              for (var index = 0; index < payload.examples.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: const TextStyle(color: _blue, fontSize: 12),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              payload.examples[index].text,
                              style: const TextStyle(color: _ink, height: 1.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              payload.examples[index].meaning,
                              style: const TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 14),
                Text(strings.referenceSource, style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 6),
                for (final source in sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      [
                        if (source.sourceTitle != null) source.sourceTitle!,
                        if (source.nodeTitle != null) source.nodeTitle!,
                        source.quote,
                      ].join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xfff8faff),
              border: Border(top: BorderSide(color: _line)),
            ),
            child: footer,
          ),
      ],
    );
    if (!framed) return ClipRRect(borderRadius: BorderRadius.circular(16), child: content);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffc8d7ff)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x12152b42), blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: _softBlue, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: _blue), const SizedBox(width: 6)],
        Text(
          label,
          style: const TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _CollectionsLink extends StatelessWidget {
  const _CollectionsLink({required this.strings});
  final AppLocalizations strings;
  @override
  Widget build(BuildContext context) => Identified(
    id: UiTestIds.referenceOpenCollections,
    merge: true,
    child: TextButton.icon(
      onPressed: () => context.go('/collections'),
      icon: const Icon(Icons.bookmark_border, size: 18),
      label: Text(strings.referenceOpenCollections),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.state, required this.strings, required this.retry});
  final ReferenceController state;
  final AppLocalizations strings;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Identified(
      id: UiTestIds.referenceErrorState,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffff4f1),
          border: Border.all(color: const Color(0xfff1c5b9)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xffa74431)),
            const SizedBox(width: 10),
            Expanded(child: Text(ApiCatalog.message(strings, state.error!.code))),
            if (retry != null)
              TextButton(
                onPressed: state.loading || state.busy ? null : retry,
                child: Text(strings.referenceRetry),
              ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Column(
      children: [
        const Icon(Icons.menu_book_outlined, size: 28, color: _muted),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );
}

class _ReferenceScaffold extends StatelessWidget {
  const _ReferenceScaffold({
    required this.title,
    required this.backTooltip,
    required this.onBack,
    required this.maxWidth,
    required this.child,
    this.plainCompactReader = false,
  });
  final String title;
  final String backTooltip;
  final VoidCallback onBack;
  final double maxWidth;
  final Widget child;
  final bool plainCompactReader;
  @override
  Widget build(BuildContext context) {
    final compact = _compact(context);
    final plainReader = compact && plainCompactReader;
    return Scaffold(
      backgroundColor: plainReader ? Colors.white : const Color(0xfff4f7fb),
      appBar: AppBar(
        backgroundColor: plainReader ? Colors.white : null,
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 19 : 17),
        ),
        leading: Identified(
          id: UiTestIds.referenceBackAccount,
          merge: true,
          child: IconButton(
            onPressed: onBack,
            tooltip: backTooltip,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 32, vertical: compact ? 18 : 36),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

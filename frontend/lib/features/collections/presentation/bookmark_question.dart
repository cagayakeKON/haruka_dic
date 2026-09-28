import 'package:flutter/material.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/domain/learning_records.dart';

import 'collection_catalog_scope.dart';
import '../data/collection_catalog.dart';

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

Future<void> bookmarkQuestion(
  BuildContext context, {
  required String id,
  required String question,
  required String meaning,
  required String source,
  String? contextText,
  String notes = '',
}) async {
  final catalog = CollectionCatalogScope.of(context);
  await Future.wait([
    if (catalog.allCollectionStatus != CollectionCatalogStatus.ready)
      catalog.refreshAllCollections(preserveCurrent: true),
    if (catalog.notebookStatus != CollectionCatalogStatus.ready)
      catalog.refreshNotebooks(preserveCurrent: true),
  ]);
  if (!context.mounted ||
      catalog.allCollectionStatus != CollectionCatalogStatus.ready ||
      catalog.notebookStatus != CollectionCatalogStatus.ready) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
    }
    return;
  }
  final existing = catalog.findCollection(id);
  final l10n = AppLocalizations.of(context);
  final selected = await _showLearningPanel<Set<String>>(
    context,
    title: l10n.mockLearningPracticeBookmark,
    child: _BookmarkQuestionSelection(
      question: question,
      initialNotebookIds: existing?.notebookIds ?? const {},
    ),
  );
  if (selected == null || !context.mounted) return;
  String feedback;
  try {
    if (existing == null) {
      await catalog.addCollection(
        CollectionEntry(
          id: id,
          kind: CollectionKind.exercise,
          displayText: question,
          targetLanguage: 'ja',
          meaning: meaning,
          context: contextText,
          sourceTitle: source,
          notebookIds: selected,
          notes: notes,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      feedback = l10n.mockLearningResultSaved;
    } else if (existing.notebookIds.length == selected.length &&
        existing.notebookIds.containsAll(selected)) {
      feedback = l10n.mockLearningResultAlreadySaved;
    } else {
      await catalog.setCollectionNotebooks(id, selected);
      feedback = l10n.mockLearningResultNotebooksUpdated;
    }
  } on Object {
    feedback = l10n.authUnavailableShort;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(feedback)));
  }
}

class _BookmarkQuestionSelection extends StatefulWidget {
  const _BookmarkQuestionSelection({required this.question, required this.initialNotebookIds});
  final String question;
  final Set<String> initialNotebookIds;
  @override
  State<_BookmarkQuestionSelection> createState() => _BookmarkQuestionSelectionState();
}

class _BookmarkQuestionSelectionState extends State<_BookmarkQuestionSelection> {
  late final selected = <String>{...widget.initialNotebookIds};
  @override
  Widget build(BuildContext context) {
    final catalog = CollectionCatalogScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.question, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 9),
        Text(
          l10n.mockLearningPracticeBookmarkHint,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 17),
        for (final book in catalog.notebooks.where((book) => book.targetLanguage == 'ja'))
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
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: Text(l10n.mockLearningPracticeBookmarkConfirm),
          ),
        ),
      ],
    );
  }
}

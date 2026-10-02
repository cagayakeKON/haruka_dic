import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/motion.dart';
import '../../../generated/ui_test_ids.dart';
import '../../../shared/identified.dart';
import '../../../app/preview_shell.dart';
import '../../../core/api/responses.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../shared/presentation/components.dart';
import '../../collections/reference_feature_scope.dart';
import '../data/http_material_catalog.dart';
import '../domain/material_metadata.dart';
import '../domain/material_summary.dart';
import 'library_pages.dart';

bool materialMutationAllowed(HttpMaterialCatalog catalog, MaterialMetadata row, String action) =>
    catalog.allows('client.material.read') &&
    catalog.allows(action) &&
    (row.type != LearningMaterialType.exam || catalog.allows('client.exam.edit'));

bool materialReuseAllowed(HttpMaterialCatalog catalog, MaterialMetadata row) =>
    row.sourceFormat != null &&
    catalog.allows('client.material.read') &&
    catalog.allows('client.material.import') &&
    (row.type != LearningMaterialType.exam ||
        (catalog.allows('client.exam.read') && catalog.allows('client.exam.edit')));

bool materialImportTypeAllowed(HttpMaterialCatalog catalog, LearningMaterialType type) =>
    catalog.allows('client.material.import') &&
    (type != LearningMaterialType.exam || catalog.allows('client.exam.import'));

/// A dialog receives the existing projection. Only a missing detail is fetched;
/// route/menu changes have no invalidation semantics.
Future<void> showLiveMaterialDialog(
  BuildContext context,
  HttpMaterialCatalog catalog,
  String id, {
  required VoidCallback onOpenMaterial,
}) async {
  final ownerContext = context;
  final scope = catalog.scopeIdentity;
  try {
    await catalog.detail(id);
  } on Object {
    if (context.mounted && catalog.isCurrent(scope)) materialFailure(context);
    return;
  }
  if (!context.mounted || !catalog.isCurrent(scope)) return;
  await showHarukaDialog<void>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: catalog,
      builder: (context, _) {
        final row = catalog.isCurrent(scope) ? catalog.metadata(id) : null;
        return Identified(
          id: UiTestIds.materialDetailsDialog,
          child: HarukaDialogSurface(
            title: AppLocalizations.of(context).mockMaterialDetailsTitle,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).mockLibraryCancel),
              ),
            ],
            child: row == null
                ? Text(AppLocalizations.of(context).mockMaterialUnavailableMessage)
                : MaterialMetadataContent(
                    catalog: catalog,
                    row: row,
                    onOpen: () {
                      Navigator.pop(dialogContext);
                      onOpenMaterial();
                    },
                    onReuse: () {
                      if (!dialogContext.mounted ||
                          !ownerContext.mounted ||
                          !catalog.isCurrent(scope) ||
                          !materialReuseAllowed(catalog, row)) {
                        return;
                      }
                      Navigator.pop(dialogContext);
                      unawaited(ownerContext.push(materialReusePath(row.id)));
                    },
                    onDeleted: () {
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                  ),
          ),
        );
      },
    ),
  );
}

String materialReusePath(String id) =>
    Uri(path: AppRoutes.materialImport, queryParameters: {'source_material_id': id}).toString();

void materialFailure(BuildContext context, [Object? error]) {
  final l10n = AppLocalizations.of(context);
  final message = error is ApiFailure && error.code == 'REVISION_CONFLICT'
      ? l10n.materialRenameConflict
      : l10n.apiUnknownError;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class MaterialMetadataContent extends StatelessWidget {
  const MaterialMetadataContent({
    required this.catalog,
    required this.row,
    this.onOpen,
    this.onDeleted,
    this.onReuse,
    super.key,
  });
  final HttpMaterialCatalog catalog;
  final MaterialMetadata row;
  final VoidCallback? onOpen, onDeleted, onReuse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = catalog.findById(row.id)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(l10n.mockMaterialTypeDetail(materialTypeLabel(context, row.type))),
        Text(
          l10n.mockMaterialLanguageDetail(
            row.language == 'ja'
                ? l10n.mockMaterialJapanese
                : row.language == 'en'
                ? l10n.mockMaterialEnglish
                : '—',
          ),
        ),
        Text('${l10n.materialSourceFormat}：${row.sourceFormat?.toUpperCase() ?? '—'}'),
        Text(l10n.mockMaterialStatusDetail(materialStatusLabel(context, item))),
        Text('${l10n.materialSourceRevision}：${row.sourceRevisionNumber ?? '—'}'),
        if (!materialCanOpen(context, item)) ...[
          const SizedBox(height: 16),
          Text(l10n.materialSourceOnly),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (materialCanOpen(context, item))
              FilledButton(
                onPressed: onOpen ?? () => context.push(AppRoutes.materialPath(row.id)),
                child: Text(l10n.mockMaterialStartReading),
              ),
            if (row.jobId != null && catalog.allows('client.job.read'))
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.jobs),
                icon: const Icon(Icons.hourglass_empty),
                label: Text(l10n.materialJobSource),
              ),
            if (materialMutationAllowed(catalog, row, 'client.material.update'))
              Identified(
                id: UiTestIds.materialRename,
                child: OutlinedButton(
                  onPressed: () => unawaited(renameMaterial(context, catalog, row)),
                  child: Text(l10n.materialRename),
                ),
              ),
            if (materialReuseAllowed(catalog, row))
              Identified(
                id: UiTestIds.materialReuse,
                child: OutlinedButton(
                  onPressed: () {
                    if (!materialReuseAllowed(catalog, row)) return;
                    if (onReuse != null) {
                      onReuse!();
                    } else {
                      unawaited(context.push(materialReusePath(row.id)));
                    }
                  },
                  child: Text(l10n.materialReuse),
                ),
              ),
            if (materialMutationAllowed(catalog, row, 'client.material.delete'))
              TextButton(
                onPressed: () =>
                    unawaited(deleteLiveMaterial(context, catalog, row, onDeleted: onDeleted)),
                child: Text(l10n.mockLibraryDelete),
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> renameMaterial(
  BuildContext context,
  HttpMaterialCatalog catalog,
  MaterialMetadata row,
) async {
  final scope = catalog.scopeIdentity;
  final l10n = AppLocalizations.of(context);
  final title = TextEditingController(text: row.title);
  if (!materialMutationAllowed(catalog, row, 'client.material.update')) {
    title.dispose();
    return;
  }
  try {
    final selected = await showHarukaDialog<String>(
      context: context,
      waitForRemoval: true,
      builder: (dialogContext) => AnimatedBuilder(
        animation: catalog,
        builder: (context, _) => HarukaDialogSurface(
          title: l10n.materialRename,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.mockLibraryCancel),
            ),
            Identified(
              id: UiTestIds.materialRenameSave,
              child: FilledButton(
                onPressed:
                    catalog.isCurrent(scope) &&
                        catalog.metadata(row.id)?.revision == row.revision &&
                        materialMutationAllowed(catalog, row, 'client.material.update')
                    ? () {
                        if (title.text.trim().isNotEmpty && title.text.trim().runes.length <= 200) {
                          Navigator.pop(dialogContext, title.text.trim());
                        }
                      }
                    : null,
                child: Text(l10n.mockNotebookSave),
              ),
            ),
          ],
          child: catalog.isCurrent(scope)
              ? Identified(
                  id: UiTestIds.materialRenameTitle,
                  child: TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: InputDecoration(labelText: l10n.materialTitle),
                  ),
                )
              : Text(l10n.mockMaterialUnavailableMessage),
        ),
      ),
    );
    if (selected == null ||
        selected.trim().runes.length > 200 ||
        selected == row.title ||
        !catalog.isCurrent(scope) ||
        !materialMutationAllowed(catalog, row, 'client.material.update')) {
      return;
    }
    try {
      await catalog.rename(row.id, row.revision, selected);
    } on Object catch (error) {
      if (catalog.isCurrent(scope)) {
        catalog.record(
          'material.metadata.updated',
          row.type,
          error is ApiFailure && error.code == 'PERMISSION_DENIED' ? 'denied' : 'failure',
        );
        if (context.mounted) materialFailure(context, error);
      }
    }
  } finally {
    title.dispose();
  }
}

class LiveMaterialDetailsPage extends StatefulWidget {
  const LiveMaterialDetailsPage({
    required this.materialId,
    required this.catalog,
    this.reader,
    super.key,
  });
  final String materialId;
  final HttpMaterialCatalog catalog;
  final Widget Function(MaterialMetadata)? reader;
  @override
  State<LiveMaterialDetailsPage> createState() => _LiveMaterialDetailsPageState();
}

class _LiveMaterialDetailsPageState extends State<LiveMaterialDetailsPage> {
  Object? _scope;
  String? _id;
  bool _loading = true;
  bool _failed = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didUpdateWidget(LiveMaterialDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  void _prepare() {
    if (_scope == widget.catalog.scopeIdentity && _id == widget.materialId) return;
    _scope = widget.catalog.scopeIdentity;
    _id = widget.materialId;
    _loading = widget.catalog.metadata(widget.materialId) == null;
    _failed = false;
    if (_loading) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final scope = _scope;
    final id = widget.materialId;
    try {
      await widget.catalog.detail(id);
    } on Object {
      if (mounted && _scope == scope && widget.materialId == id) _failed = true;
    } finally {
      if (mounted && _scope == scope && widget.materialId == id) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.catalog,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final catalog = widget.catalog;
      final row = catalog.isCurrent(_scope!) ? catalog.metadata(widget.materialId) : null;
      final item = row == null ? null : catalog.findById(row.id);
      if (item != null && widget.reader != null && materialCanOpen(context, item)) {
        return widget.reader!(row!);
      }
      final content = _loading
          ? const Center(child: CircularProgressIndicator())
          : row == null || _failed
          ? Center(child: Text(l10n.mockMaterialUnavailableMessage))
          : HarukaSurface(
              child: MaterialMetadataContent(
                catalog: catalog,
                row: row,
                onDeleted: () {
                  if (mounted) this.context.go(AppRoutes.materials);
                },
              ),
            );
      return Identified(
        id: UiTestIds.materialDetailsPage,
        child: PreviewPageFrame(
          location: AppRoutes.materialDetailsPath(widget.materialId),
          title: l10n.mockMaterialDetailsTitle,
          detail: true,
          desktopBackLabel: l10n.mockLibraryTitle,
          onBack: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.materials);
            }
          },
          mobile: ListView(padding: const EdgeInsets.all(20), children: [content]),
          desktop: ListView(
            children: [
              Text(
                l10n.mockMaterialDetailsTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              content,
            ],
          ),
        ),
      );
    },
  );
}

Future<void> deleteLiveMaterial(
  BuildContext context,
  HttpMaterialCatalog catalog,
  MaterialMetadata row, {
  VoidCallback? onDeleted,
}) async {
  final scope = catalog.scopeIdentity;
  final reference = ReferenceFeatureScope.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  if (!materialMutationAllowed(catalog, row, 'client.material.delete')) return;
  final confirmed = await showHarukaDialog<bool>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: catalog,
      builder: (context, _) => HarukaDialogSurface(
        title: l10n.mockLibraryDeleteConfirmTitle,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.mockLibraryCancel),
          ),
          Identified(
            id: UiTestIds.materialDeleteConfirm,
            child: FilledButton(
              onPressed:
                  catalog.isCurrent(scope) &&
                      catalog.metadata(row.id)?.revision == row.revision &&
                      materialMutationAllowed(catalog, row, 'client.material.delete')
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(l10n.mockLibraryDelete),
            ),
          ),
        ],
        child: Text(
          catalog.isCurrent(scope)
              ? l10n.mockLibraryDeleteConfirmMessage(row.title)
              : l10n.mockMaterialUnavailableMessage,
        ),
      ),
    ),
  );
  if (confirmed != true ||
      !catalog.isCurrent(scope) ||
      !materialMutationAllowed(catalog, row, 'client.material.delete')) {
    return;
  }
  try {
    await catalog.deleteRevision(row);
    if (!catalog.isCurrent(scope)) return;
    reference?.retireMaterial(row.id);
    // Publishing the tombstone removes this content before the cache commit
    // finishes. The callback owns its dialog/page lifetime independently.
    onDeleted?.call();
  } on Object catch (error) {
    if (catalog.isCurrent(scope)) {
      catalog.record(
        'material.deleted',
        row.type,
        error is ApiFailure && error.code == 'PERMISSION_DENIED' ? 'denied' : 'failure',
      );
      if (context.mounted) materialFailure(context, error);
    }
  }
}

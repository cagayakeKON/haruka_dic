import 'package:flutter/material.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/collections/data/csv_file_port.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/collections/domain/vocabulary_csv.dart';

import 'collection_catalog_access.dart';
import 'collection_catalog_scope.dart';
import '../data/collection_catalog.dart';

class CsvPage extends StatefulWidget {
  const CsvPage({this.filePort, super.key});

  final CsvFilePort? filePort;

  @override
  State<CsvPage> createState() => _CsvPageState();
}

class _CsvPageState extends State<CsvPage> {
  CsvFilePort get _files => widget.filePort ?? const SystemCsvFilePort();

  PickedCsvFile? _picked;
  VocabularyCsvPreview? _preview;
  VocabularyCsvImportOutcome? _importResult;
  int? _importResultScopeGeneration;
  CsvProblem? _fileProblem;
  CsvDuplicateAction _duplicateAction = CsvDuplicateAction.skip;
  bool _excludeErrors = false;
  bool _busy = false;
  String? _defaultLanguage;

  Future<void> _export() async {
    final catalog = CollectionCatalogScope.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await Future.wait([
        catalog.refreshAllCollections(force: true, preserveCurrent: true),
        catalog.refreshNotebooks(force: true, preserveCurrent: true),
      ]);
      if (catalog.allCollectionStatus != CollectionCatalogStatus.ready ||
          catalog.notebookStatus != CollectionCatalogStatus.ready) {
        throw StateError('Collection export is unavailable');
      }
      final bytes = exportVocabularyCsv(catalog.allCollections, catalog.notebooks);
      final date = DateTime.now().toLocal().toIso8601String().substring(0, 10);
      final outcome = await _files.save('Haruka-words-$date.csv', bytes);
      if (!mounted || outcome == CsvSaveOutcome.cancelled) return;
      final message = switch (outcome) {
        CsvSaveOutcome.saved => l10n.mockCsvSaved,
        CsvSaveOutcome.downloadStarted => l10n.mockCsvDownloadStarted,
        CsvSaveOutcome.systemFlowOpened => l10n.mockCsvSystemFlowOpened,
        CsvSaveOutcome.cancelled => '',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.mockCsvSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFile() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final file = await _files.pick();
      if (!mounted || file == null) return;
      setState(() {
        _picked = file;
        _preview = null;
        _importResult = null;
        _fileProblem = null;
        _excludeErrors = false;
      });
    } on CsvReadException catch (error) {
      if (mounted) {
        setState(() {
          _picked = null;
          _preview = null;
          _importResult = null;
          _fileProblem = error.problem;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.mockCsvFileReadFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPreview() {
    final file = _picked;
    if (file == null) return;
    try {
      final store = PreviewStoreScope.of(context);
      final preview = previewVocabularyCsv(
        bytes: file.bytes,
        filename: file.name,
        existing: CollectionCatalogScope.of(context).allCollections,
        defaultLanguage: _defaultLanguage ?? store.activeLanguage,
      );
      setState(() {
        _preview = preview;
        _fileProblem = null;
        _importResult = null;
        _excludeErrors = false;
      });
    } on CsvReadException catch (error) {
      setState(() {
        _preview = null;
        _fileProblem = error.problem;
      });
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockCsvFileReadFailed)));
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    if (preview == null || preview.validCount == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final catalog = CollectionCatalogScope.of(context);
      final result = await catalog.importVocabularyCsv(
        preview,
        duplicateAction: _duplicateAction,
        excludeErrors: _excludeErrors,
      );
      if (!mounted) return;
      setState(() {
        _importResult = result;
        _importResultScopeGeneration = catalog.scopeGeneration;
        _preview = null;
        _picked = null;
        _fileProblem = null;
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).authUnavailableShort)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CollectionCatalogAccess(
    allCollections: true,
    builder: (context, catalog) => _buildContent(context, catalog),
    unavailableBuilder: (context, catalog) {
      final result = _importResultScopeGeneration == catalog.scopeGeneration ? _importResult : null;
      if (result == null) {
        return Center(child: Text(AppLocalizations.of(context).authUnavailableShort));
      }
      final l10n = AppLocalizations.of(context);
      return Center(
        child: Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.mockCsvImportResult(
                    result.added,
                    result.merged,
                    result.skipped,
                    result.excluded,
                  ),
                ),
                const SizedBox(height: 8),
                Text(l10n.authUnavailableShort),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _buildContent(BuildContext context, CollectionCatalog catalog) {
    final store = PreviewStoreScope.of(context);
    _defaultLanguage ??= store.activeLanguage;
    final exportCard = _CsvExportCard(busy: _busy, onExport: _export);
    final importCard = _CsvImportCard(
      busy: _busy,
      picked: _picked,
      preview: _preview,
      result: _importResultScopeGeneration == catalog.scopeGeneration ? _importResult : null,
      fileProblem: _fileProblem,
      defaultLanguage: _defaultLanguage!,
      onLanguageChanged: (value) => setState(() {
        _defaultLanguage = value;
        _preview = null;
      }),
      duplicateAction: _duplicateAction,
      onDuplicateActionChanged: (value) => setState(() => _duplicateAction = value),
      excludeErrors: _excludeErrors,
      onExcludeErrorsChanged: (value) => setState(() => _excludeErrors = value),
      onChooseFile: _chooseFile,
      onPreview: _showPreview,
      onConfirm: _confirmImport,
    );
    return PreviewPageFrame(
      location: AppRoutes.mockCsv,
      title: AppLocalizations.of(context).mockSupportCsvTitle,
      detail: true,
      detailNotifications: false,
      mobile: MobileCsvView(exportCard: exportCard, importCard: importCard),
      desktop: DesktopCsvView(exportCard: exportCard, importCard: importCard),
    );
  }
}

class MobileCsvView extends StatelessWidget {
  const MobileCsvView({required this.exportCard, required this.importCard, super.key});
  final Widget exportCard;
  final Widget importCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 66, 20, 20),
      children: [
        Text(
          l10n.mockSupportCsvImportExportTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.mockSupportCsvPreviewHint),
        const SizedBox(height: 34),
        exportCard,
        const SizedBox(height: 16),
        importCard,
        const SizedBox(height: 24),
      ],
    );
  }
}

class DesktopCsvView extends StatelessWidget {
  const DesktopCsvView({required this.exportCard, required this.importCard, super.key});
  final Widget exportCard;
  final Widget importCard;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: ListView(
        children: [
          Text(
            AppLocalizations.of(context).mockSupportCsvTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: exportCard),
              const SizedBox(width: 20),
              Expanded(child: importCard),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CsvExportCard extends StatelessWidget {
  const _CsvExportCard({required this.busy, required this.onExport});
  final bool busy;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.mockSupportCsvExportEntries, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(l10n.mockSupportCsvExportScopeHint),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onExport,
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.mockSupportCsvGenerateExample),
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvImportCard extends StatelessWidget {
  const _CsvImportCard({
    required this.busy,
    required this.picked,
    required this.preview,
    required this.result,
    required this.fileProblem,
    required this.defaultLanguage,
    required this.onLanguageChanged,
    required this.duplicateAction,
    required this.onDuplicateActionChanged,
    required this.excludeErrors,
    required this.onExcludeErrorsChanged,
    required this.onChooseFile,
    required this.onPreview,
    required this.onConfirm,
  });

  final bool busy;
  final PickedCsvFile? picked;
  final VocabularyCsvPreview? preview;
  final VocabularyCsvImportOutcome? result;
  final CsvProblem? fileProblem;
  final String defaultLanguage;
  final ValueChanged<String> onLanguageChanged;
  final CsvDuplicateAction duplicateAction;
  final ValueChanged<CsvDuplicateAction> onDuplicateActionChanged;
  final bool excludeErrors;
  final ValueChanged<bool> onExcludeErrorsChanged;
  final VoidCallback onChooseFile;
  final VoidCallback onPreview;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return HarukaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.mockSupportCsvImportPreview, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Text(l10n.mockSupportCsvChooseUtf8),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onChooseFile,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(picked?.name ?? l10n.mockSupportCsvChooseUtf8),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: defaultLanguage,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.mockCsvDefaultLanguage),
            items: [
              DropdownMenuItem(value: 'ja', child: Text(l10n.mockSupportJapanese)),
              DropdownMenuItem(value: 'en', child: Text(l10n.mockSupportEnglish)),
            ],
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) onLanguageChanged(value);
                  },
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: busy || picked == null ? null : onPreview,
              child: Text(l10n.mockSupportCsvShowPreview),
            ),
          ),
          if (fileProblem case final problem?) ...[
            const SizedBox(height: 12),
            Text(_problemText(l10n, problem), style: TextStyle(color: colors.error)),
          ],
          if (preview case final shown?) ...[
            const SizedBox(height: 18),
            Text(
              l10n.mockCsvPreviewCounts(
                shown.rows.length,
                shown.newCount,
                shown.duplicateCount,
                shown.errorCount,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final row in [
              ...shown.rows.where((item) => !item.valid),
              ...shown.rows.where((item) => item.valid),
            ].take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _CsvPreviewRow(row: row),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CsvDuplicateAction>(
              initialValue: duplicateAction,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.mockCsvDuplicateAction),
              items: [
                DropdownMenuItem(
                  value: CsvDuplicateAction.skip,
                  child: Text(l10n.mockCsvSkipDuplicates),
                ),
                DropdownMenuItem(
                  value: CsvDuplicateAction.merge,
                  child: Text(l10n.mockCsvMergeDuplicates),
                ),
                DropdownMenuItem(
                  value: CsvDuplicateAction.create,
                  child: Text(l10n.mockCsvCreateDuplicates),
                ),
              ],
              onChanged: (value) {
                if (value != null) onDuplicateActionChanged(value);
              },
            ),
            if (shown.errorCount > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.mockCsvExcludeErrors),
                value: excludeErrors,
                onChanged: (value) => onExcludeErrorsChanged(value ?? false),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: shown.validCount > 0 && (shown.errorCount == 0 || excludeErrors)
                    ? onConfirm
                    : null,
                child: Text(l10n.mockSupportCsvConfirmImport),
              ),
            ),
          ],
          if (result case final imported?) ...[
            const SizedBox(height: 12),
            Text(
              l10n.mockCsvImportResult(
                imported.added,
                imported.merged,
                imported.skipped,
                imported.excluded,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CsvPreviewRow extends StatelessWidget {
  const _CsvPreviewRow({required this.row});
  final VocabularyCsvRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final status = row.issues.isNotEmpty
        ? row.issues.map((issue) => _problemText(l10n, issue)).join('、')
        : row.unboundSource
        ? l10n.mockCsvSourceUnbound
        : switch (row.duplicate) {
            CsvDuplicateKind.existing => l10n.mockCsvExistingDuplicate,
            CsvDuplicateKind.file => l10n.mockCsvFileDuplicate,
            CsvDuplicateKind.none => l10n.mockCsvReadyRow,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.mockCsvRowLabel(row.number, row.word.isEmpty ? l10n.mockCsvEmptyWord : row.word),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              status,
              textAlign: TextAlign.end,
              style: TextStyle(color: row.issues.isEmpty ? colors.onSurfaceVariant : colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

String _problemText(AppLocalizations l10n, CsvProblem problem) => switch (problem) {
  CsvProblem.emptyFile => l10n.mockCsvProblemEmptyFile,
  CsvProblem.tooLarge => l10n.mockCsvProblemTooLarge,
  CsvProblem.tooManyRows => l10n.mockCsvProblemTooManyRows,
  CsvProblem.invalidUtf8 => l10n.mockCsvProblemInvalidUtf8,
  CsvProblem.invalidQuotes => l10n.mockCsvProblemInvalidQuotes,
  CsvProblem.missingWordColumn => l10n.mockCsvProblemMissingWordColumn,
  CsvProblem.repeatedColumn => l10n.mockCsvProblemRepeatedColumn,
  CsvProblem.rowWidth => l10n.mockCsvProblemRowWidth,
  CsvProblem.missingWord => l10n.mockCsvProblemMissingWord,
  CsvProblem.invalidLanguage => l10n.mockCsvProblemInvalidLanguage,
  CsvProblem.invalidVersion => l10n.mockCsvProblemInvalidVersion,
  CsvProblem.invalidEscape => l10n.mockCsvProblemInvalidEscape,
  CsvProblem.invalidTags => l10n.mockCsvProblemInvalidTags,
  CsvProblem.invalidWordbooks => l10n.mockCsvProblemInvalidWordbooks,
  CsvProblem.invalidStatus => l10n.mockCsvProblemInvalidStatus,
  CsvProblem.invalidExerciseControl => l10n.mockCsvProblemInvalidExerciseControl,
  CsvProblem.invalidDate => l10n.mockCsvProblemInvalidDate,
  CsvProblem.invalidLocator => l10n.mockCsvProblemInvalidLocator,
  CsvProblem.fieldTooLong => l10n.mockCsvProblemFieldTooLong,
};

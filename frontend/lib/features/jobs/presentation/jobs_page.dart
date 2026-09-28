import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/presentation/material_catalog_access.dart';

MaterialSummary? _activeJob(MaterialCatalog catalog) {
  for (final material in catalog.filterMaterials(const MaterialCatalogQuery())) {
    if (material.activeJobProgressPercent != null) return material;
  }
  return null;
}

bool _canOpen(MaterialSummary? material) => material?.status == 'readable';

class JobsPage extends StatelessWidget {
  const JobsPage({super.key});

  @override
  Widget build(BuildContext context) => MaterialCatalogAccess(
    builder: (context, catalog) => PreviewPageFrame(
      location: AppRoutes.mockJobs,
      title: AppLocalizations.of(context).mockSupportJobsTitle,
      detail: true,
      detailNotifications: false,
      desktopBackLabel: AppLocalizations.of(context).mockShellBack,
      onBack: () => context.canPop()
          ? context.pop()
          : context.go(AppRoutes.mockSettings),
      mobile: MobileJobsView(material: _activeJob(catalog)),
      desktop: DesktopJobsView(material: _activeJob(catalog)),
    ),
  );
}

class MobileJobsView extends StatelessWidget {
  const MobileJobsView({required this.material, super.key});
  final MaterialSummary? material;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final progress = (material?.activeJobProgressPercent ?? 0).clamp(0, 100);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 42, 20, 20),
      children: [
        Text(
          strings.mockSupportJobsConnected,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 36),
        if (material == null)
          Text(strings.authUnavailableShort)
        else ...[
          Text(
            strings.mockSupportJobsNovelDemo,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text(material!.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          Text(
            _canOpen(material) ? strings.mockLibraryReadable : strings.mockSupportProgress(progress),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress / 100),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _canOpen(material)
                  ? () => context.go(AppRoutes.mockMaterialPath(material!.id))
                  : null,
              child: Text(strings.mockSupportJobsOpenMaterial),
            ),
          ),
        ],
      ],
    );
  }
}

class DesktopJobsView extends StatelessWidget {
  const DesktopJobsView({required this.material, super.key});
  final MaterialSummary? material;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final progress = (material?.activeJobProgressPercent ?? 0).clamp(0, 100);
    return ListView(
      children: [
        Text(strings.mockSupportJobsTitle,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: HarukaSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.mockSupportJobsConnected,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),
                    if (material == null)
                      Text(strings.authUnavailableShort)
                    else ...[
                      Text(
                        strings.mockSupportJobsNovelDemo,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      Text(material!.title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 22),
                      Text(
                        _canOpen(material)
                            ? strings.mockLibraryReadable
                            : strings.mockSupportProgress(progress),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progress / 100),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _canOpen(material)
                              ? () => context.go(AppRoutes.mockMaterialPath(material!.id))
                              : null,
                          child: Text(strings.mockSupportJobsOpenMaterial),
                        ),
                      ),
                    ],
                  ],
                ),
            ),
          ),
        ),
      ],
    );
  }
}

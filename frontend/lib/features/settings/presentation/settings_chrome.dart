import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/core/telemetry/telemetry.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';

import 'settings_repository_scope.dart';

/// Authenticated settings keep the existing pages and point them at `/settings`.
/// Preview routes leave this scope unset and continue to use `/mock/settings`.
class SettingsLocations extends InheritedWidget {
  const SettingsLocations({required this.home, required super.child, super.key});

  final String home;

  String section(String id) => '$home/$id';

  static SettingsLocations? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsLocations>();

  @override
  bool updateShouldNotify(SettingsLocations oldWidget) => home != oldWidget.home;
}

String settingsHome(BuildContext context) =>
    SettingsLocations.maybeOf(context)?.home ?? AppRoutes.mockSettings;

String settingsSectionPath(BuildContext context, String section) =>
    SettingsLocations.maybeOf(context)?.section(section) ?? AppRoutes.mockSettingPath(section);

bool settingsUsePreviewAvatar(BuildContext context) =>
    settingsHome(context) == AppRoutes.mockSettings;

void trackSettingsMutation(BuildContext context, String event) {
  if (settingsUsePreviewAvatar(context)) return;
  try {
    ProviderScope.containerOf(context, listen: false).read(telemetryProvider)?.track(event);
  } on Object {
    // Telemetry is best effort and never changes a confirmed save.
  }
}

class AccountSettingsHost extends StatelessWidget {
  const AccountSettingsHost({
    required this.store,
    required this.cache,
    required this.repository,
    required this.child,
    super.key,
  });

  final PreviewFixtureStore store;
  final PreviewSettingsCacheAdapter cache;
  final CachedSettingsRepository repository;
  final Widget child;

  @override
  Widget build(BuildContext context) => SettingsLocations(
    home: AppRoutes.settings,
    child: PreviewStoreScope(
      store: store,
      child: PreviewSettingsCacheScope(
        adapter: cache,
        child: SettingsRepositoryScope(repository: repository, child: child),
      ),
    ),
  );
}

Widget settingsChrome({
  required BuildContext context,
  required bool framed,
  required String location,
  required String title,
  required Widget mobile,
  required Widget desktop,
  bool detail = false,
  bool detailNotifications = true,
  String? desktopBackLabel,
  VoidCallback? onBack,
}) {
  if (framed) {
    return PreviewPageFrame(
      location: location,
      title: title,
      detail: detail,
      detailNotifications: detailNotifications,
      desktopBackLabel: desktopBackLabel,
      onBack: onBack,
      mobile: mobile,
      desktop: desktop,
    );
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      final body = constraints.maxWidth < 760 ? mobile : desktop;
      if (!detail || constraints.maxWidth < 600) return body;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: Text(desktopBackLabel ?? title),
            ),
          ),
          Expanded(child: body),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/auth/auth_controller.dart';
import '../core/layout/adaptive_policy.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';
import 'routes.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.config, required this.location, required this.child, super.key});

  final AppConfig config;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = ProviderScope.containerOf(context).read(authControllerProvider);
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => auth.isAuthenticated && !auth.admin
          ? _ClientShell(location: location, auth: auth, child: child)
          : _buildPublicShell(context),
    );
  }

  Widget _buildPublicShell(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final selected = location == AppRoutes.environment ? 1 : 0;
    void navigate(int index) => context.go(index == 0 ? AppRoutes.home : AppRoutes.environment);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () => navigate(0),
        const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () => navigate(1),
      },
      child: FocusTraversalGroup(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = AdaptivePolicy.forWidth(constraints.maxWidth);
            final compact = layout == LayoutSize.compact;
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  config.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
                ),
                actions: [
                  Consumer(
                    builder: (context, ref, _) {
                      final auth = ref.watch(authControllerProvider);
                      if (!auth.isAuthenticated || auth.admin) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (auth.access!.allows('client.material.list'))
                            Identified(
                              id: UiTestIds.referenceMaterialsNav,
                              merge: true,
                              child: IconButton(
                                tooltip: strings.referenceMaterialsTitle,
                                onPressed: () => context.go(AppRoutes.materials),
                                icon: const Icon(Icons.auto_stories_outlined),
                              ),
                            ),
                          if (auth.access!.allows('client.collection.read'))
                            Identified(
                              id: UiTestIds.referenceCollectionsNav,
                              merge: true,
                              child: IconButton(
                                tooltip: strings.referenceCollectionsTitle,
                                onPressed: () => context.go(AppRoutes.collections),
                                icon: const Icon(Icons.bookmark_outline),
                              ),
                            ),
                          if (auth.access!.allows('client.profile.read'))
                            IconButton(
                              tooltip: strings.mockSettingMyTitle,
                              onPressed: () => context.go(AppRoutes.settings),
                              icon: const Icon(Icons.tune),
                            ),
                        ],
                      );
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final signedIn = ref.watch(authControllerProvider).isAuthenticated;
                      return Identified(
                        id: UiTestIds.accountNavigation,
                        merge: true,
                        child: IconButton(
                          tooltip: signedIn ? strings.authAccount : strings.authSignIn,
                          onPressed: () =>
                              context.go(signedIn ? AppRoutes.account : AppRoutes.login),
                          icon: Icon(signedIn ? Icons.account_circle : Icons.login),
                        ),
                      );
                    },
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: Theme.of(context).colorScheme.outline),
                ),
              ),
              body: SafeArea(
                top: false,
                bottom: !compact,
                child: Row(
                  children: [
                    if (!compact)
                      WideNavigation(
                        expanded: layout == LayoutSize.expanded,
                        selected: selected,
                        onSelected: navigate,
                      ),
                    Expanded(child: child),
                  ],
                ),
              ),
              bottomNavigationBar: compact
                  ? NavigationBar(
                      selectedIndex: selected,
                      onDestinationSelected: navigate,
                      destinations: [
                        Identified(
                          id: UiTestIds.homeNavigation,
                          merge: true,
                          child: NavigationDestination(
                            icon: const Icon(Icons.home_outlined),
                            selectedIcon: const Icon(Icons.home),
                            label: strings.home,
                          ),
                        ),
                        Identified(
                          id: UiTestIds.environmentNavigation,
                          merge: true,
                          child: NavigationDestination(
                            icon: const Icon(Icons.info_outline),
                            selectedIcon: const Icon(Icons.info),
                            label: strings.environment,
                          ),
                        ),
                      ],
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}

/// The wider shell keeps the registered test IDs on clickable controls.
class WideNavigation extends StatelessWidget {
  const WideNavigation({
    required this.expanded,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final bool expanded;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final items = [
      (UiTestIds.homeNavigation, strings.home, Icons.home_outlined),
      (UiTestIds.environmentNavigation, strings.environment, Icons.info_outline),
    ];
    return SizedBox(
      width: expanded ? 208 : 112,
      child: ColoredBox(
        color: colors.surface,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Identified(
                    id: items[index].$1,
                    merge: true,
                    child: TextButton(
                      autofocus: index == 0,
                      onPressed: () => onSelected(index),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 64),
                        foregroundColor: selected == index
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        backgroundColor: selected == index ? colors.primaryContainer : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.all(12),
                      ),
                      child: expanded
                          ? Row(
                              children: [
                                Icon(items[index].$3),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    items[index].$2,
                                    style: TextStyle(
                                      fontWeight: selected == index
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Icon(items[index].$3),
                                const SizedBox(height: 4),
                                Text(
                                  items[index].$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: selected == index
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The signed-in shell exposes only routes delivered in the current slice.
class _ClientShell extends StatelessWidget {
  const _ClientShell({required this.location, required this.child, required this.auth});

  final String location;
  final Widget child;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <(String, String, IconData, String)>[
      if (auth.access?.allows('client.material.list') ?? false)
        (UiTestIds.referenceMaterialsNav, '材料', Icons.auto_stories_outlined, AppRoutes.materials),
      if (auth.access?.allows('client.collection.read') ?? false)
        (
          UiTestIds.referenceCollectionsNav,
          l10n.mockShellNotebooks,
          Icons.bookmark_outline,
          AppRoutes.collections,
        ),
      if (auth.access?.allows('client.profile.read') ?? false)
        (
          UiTestIds.accountNavigation,
          l10n.mockSettingMyTitle,
          Icons.person_outline,
          AppRoutes.settings,
        ),
    ];
    final compact = MediaQuery.sizeOf(context).width < 600;
    final detail = location.startsWith('${AppRoutes.settings}/');
    final section = detail ? location.substring(AppRoutes.settings.length + 1) : '';
    final compactTitle = switch (section) {
      'profile' => l10n.mockSettingProfile,
      'languages' => l10n.mockSettingLanguageOptions,
      'appearance' => l10n.mockSettingAppearance,
      'readingPrefs' => l10n.mockSettingReadingPreferences,
      'queryPreferences' => l10n.mockSettingQueryContext,
      'cache' => l10n.mockSettingLocalCache,
      'security' => l10n.mockSettingSecurityAccount,
      'connection' => l10n.mockSettingServiceConnection,
      _ => l10n.mockSettingMyTitle,
    };
    final selection = items.indexWhere(
      (item) => location == item.$4 || location.startsWith('${item.$4}/'),
    );
    final selected = selection < 0 ? 0 : selection;
    return Scaffold(
      appBar: AppBar(
        leading: compact && detail
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(AppRoutes.settings),
              )
            : null,
        title: Text(
          compact && (location == AppRoutes.settings || detail) ? compactTitle : 'haruka',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: l10n.authAccount,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.go(AppRoutes.account),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: !compact,
        child: Row(
          children: [
            if (!compact && items.isNotEmpty)
              SizedBox(
                width: MediaQuery.sizeOf(context).width >= 1280 ? 248 : 224,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Identified(
                            id: items[i].$1,
                            merge: true,
                            child: ListTile(
                              leading: Icon(items[i].$3),
                              title: Text(items[i].$2),
                              selected: i == selected,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              tileColor: i == selected
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : null,
                              onTap: () => context.go(items[i].$4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: compact && !detail && items.isNotEmpty
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (index) => context.go(items[index].$4),
              destinations: [
                for (final item in items)
                  Identified(
                    id: item.$1,
                    merge: true,
                    child: NavigationDestination(icon: Icon(item.$3), label: item.$2),
                  ),
              ],
            )
          : null,
    );
  }
}

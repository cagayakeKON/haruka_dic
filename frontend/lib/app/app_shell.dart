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

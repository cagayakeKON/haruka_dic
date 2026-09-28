import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/dev/preview/fixture_store.dart';

class PreviewStoreScope extends InheritedNotifier<PreviewFixtureStore> {
  const PreviewStoreScope({required PreviewFixtureStore store, required super.child, super.key})
    : super(notifier: store);

  static PreviewFixtureStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreviewStoreScope>()!.notifier!;
}

/// Marks routed pages whose navigation is owned by the persistent app shell.
class PreviewShellHost extends InheritedWidget {
  const PreviewShellHost({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreviewShellHost>() != null;

  @override
  bool updateShouldNotify(PreviewShellHost oldWidget) => false;
}

class PreviewShellActionRegistry extends ChangeNotifier {
  String? location;
  String? backLabel;
  VoidCallback? onBack;
  ValueChanged<String>? onNavigate;
  bool showNotifications = true;

  void register(
    String path,
    String? label,
    VoidCallback? back,
    ValueChanged<String>? navigate,
    bool notifications,
  ) {
    final changed = location != path || backLabel != label || showNotifications != notifications;
    location = path;
    backLabel = label;
    onBack = back;
    onNavigate = navigate;
    showNotifications = notifications;
    if (changed) notifyListeners();
  }
}

class PreviewShellActionScope extends InheritedWidget {
  const PreviewShellActionScope({required this.registry, required super.child, super.key});

  final PreviewShellActionRegistry registry;

  static PreviewShellActionRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreviewShellActionScope>()?.registry;

  @override
  bool updateShouldNotify(PreviewShellActionScope oldWidget) => registry != oldWidget.registry;
}

enum PreviewSection { library, notebooks, query, exercise, settings }

/// The navigator and its shell stay mounted across route and viewport changes.
class PreviewPersistentShell extends StatelessWidget {
  const PreviewPersistentShell({
    required this.location,
    required this.onNavigate,
    required this.onBack,
    required this.onOpenNotifications,
    required this.actions,
    required this.child,
    this.adminFrameBuilder,
    super.key,
  });

  final ValueListenable<String> location;
  final ValueChanged<String> onNavigate;
  final VoidCallback onBack;
  final VoidCallback onOpenNotifications;
  final PreviewShellActionRegistry actions;
  final Widget? child;
  final Widget Function(BuildContext, String, Widget)? adminFrameBuilder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: actions,
    builder: (context, _) => ValueListenableBuilder<String>(
      valueListenable: location,
      builder: (context, path, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final mobile = width < 600;
          final previewContent =
              !path.startsWith('/mock/admin') &&
              path != AppRoutes.mockLogin &&
              path != AppRoutes.mockRegister;
          final showBottom =
              mobile &&
              const {
                AppRoutes.mockLibrary,
                AppRoutes.mockNotebooks,
                AppRoutes.mockQuery,
                AppRoutes.mockExercise,
                AppRoutes.mockSettings,
              }.contains(path);
          final sideWidth = mobile || !previewContent
              ? 0.0
              : width >= 1280
              ? 248.0
              : width >= 1024
              ? 224.0
              : 80.0;
          final desktopHeader = !mobile && previewContent && width - sideWidth >= 760;
          void navigate(String next) {
            if (actions.location == path && actions.onNavigate != null) {
              actions.onNavigate!(next);
            } else {
              onNavigate(next);
            }
          }

          return Scaffold(
            backgroundColor: HarukaColors.of(context).canvas,
            body: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  key: const ValueKey('preview-routed-content'),
                  child: Column(
                    verticalDirection: VerticalDirection.up,
                    children: [
                      Expanded(
                        key: const ValueKey('preview-shell-page'),
                        child: PreviewShellHost(
                          child: PreviewShellActionScope(
                            registry: actions,
                            child: path.startsWith('/mock/admin') && adminFrameBuilder != null
                                ? adminFrameBuilder!(
                                    context,
                                    path,
                                    child ?? const SizedBox.shrink(),
                                  )
                                : child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      if (desktopHeader)
                        _PersistentDesktopHeader(
                          location: path,
                          backLabel: actions.location == path ? actions.backLabel : null,
                          onBack: actions.location == path && actions.onBack != null
                              ? actions.onBack!
                              : onBack,
                          showNotifications: actions.location != path || actions.showNotifications,
                          onOpenNotifications: () {
                            if (actions.location == path && actions.onNavigate != null) {
                              actions.onNavigate!(AppRoutes.mockNotifications);
                            } else {
                              onOpenNotifications();
                            }
                          },
                        ),
                    ],
                  ),
                ),
                if (!mobile && previewContent)
                  PreviewSideNavigation(location: path, width: sideWidth, onNavigate: navigate),
              ],
            ),
            bottomNavigationBar: showBottom
                ? PreviewBottomNavigation(
                    location: path,
                    onSelected: (section) =>
                        navigateSection(context, section, onNavigate: navigate),
                  )
                : null,
          );
        },
      ),
    ),
  );
}

class _PersistentDesktopHeader extends StatelessWidget {
  const _PersistentDesktopHeader({
    required this.location,
    required this.backLabel,
    required this.onBack,
    required this.showNotifications,
    required this.onOpenNotifications,
  });

  final String location;
  final String? backLabel;
  final VoidCallback onBack;
  final bool showNotifications;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final store = PreviewStoreScope.of(context);
    final root = const {
      AppRoutes.mockLibrary,
      AppRoutes.mockNotebooks,
      AppRoutes.mockQuery,
      AppRoutes.mockExercise,
      AppRoutes.mockSettings,
    }.contains(location);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              if (root)
                Text(
                  _activeLanguageLabel(l10n, store.activeLanguage),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                )
              else
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.chevron_left, size: 19),
                  label: Text(backLabel ?? l10n.mockShellBack),
                ),
              const Spacer(),
              if (showNotifications)
                IconButton(
                  tooltip: l10n.mockShellNotifications,
                  onPressed: onOpenNotifications,
                  icon: Badge(
                    isLabelVisible: store.unreadCount > 0,
                    child: const Icon(Icons.notifications_none),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PreviewSideNavigation extends StatelessWidget {
  const PreviewSideNavigation({
    required this.location,
    required this.width,
    required this.onNavigate,
    super.key,
  });

  final String location;
  final double width;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final selected = sectionFor(location);
    final store = PreviewStoreScope.of(context);
    final rail = width <= 80;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outline.withValues(alpha: .7))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(rail ? 24 : 22, 23, 12, 24),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      'h',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!rail) ...[
                    const SizedBox(width: 10),
                    Text(
                      'haruka',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
            for (final section in PreviewSection.values)
              Padding(
                padding: EdgeInsets.fromLTRB(rail ? 8 : 14, 2, rail ? 8 : 14, 2),
                child: Tooltip(
                  message: _sectionLabel(l10n, section),
                  excludeFromSemantics: !rail,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => navigateSection(context, section, onNavigate: onNavigate),
                    child: AnimatedContainer(
                      duration: HarukaMotion.reduced(context, reducedMotion: store.reducedMotion)
                          ? Duration.zero
                          : HarukaMotion.selection,
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 14),
                      decoration: BoxDecoration(
                        color: section == selected ? roles.selected : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: rail
                          ? Center(
                              child: Icon(
                                previewSectionIcons[section.index],
                                size: 22,
                                color: section == selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            )
                          : Row(
                              children: [
                                Icon(
                                  previewSectionIcons[section.index],
                                  size: 22,
                                  color: section == selected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    _sectionLabel(l10n, section),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: section == selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: section == selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (rail)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: IconButton(
                  tooltip: l10n.mockShellSettings,
                  onPressed: () => onNavigate(AppRoutes.mockSettings),
                  icon: CircleAvatar(
                    radius: 17,
                    backgroundColor: roles.signal,
                    child: Text(
                      String.fromCharCode(
                        displayNameOrFallback(context, store.displayName).runes.first,
                      ),
                      style: TextStyle(color: roles.onSignal),
                    ),
                  ),
                ),
              )
            else
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                  leading: CircleAvatar(
                    backgroundColor: roles.signal,
                    child: Text(
                      String.fromCharCode(
                        displayNameOrFallback(context, store.displayName).runes.first,
                      ),
                      style: TextStyle(color: roles.onSignal),
                    ),
                  ),
                  title: Text(
                    displayNameOrFallback(context, store.displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_activeLanguageLabel(l10n, store.activeLanguage)),
                  onTap: () => onNavigate(AppRoutes.mockSettings),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const previewSectionIcons = [
  Icons.auto_stories_outlined,
  Icons.bookmarks_outlined,
  Icons.chat_bubble_outline,
  Icons.auto_awesome_outlined,
  Icons.person_outline,
];

String _sectionLabel(AppLocalizations l10n, PreviewSection section) => switch (section) {
  PreviewSection.library => l10n.mockShellLibrary,
  PreviewSection.notebooks => l10n.mockShellNotebooks,
  PreviewSection.query => l10n.mockShellQuery,
  PreviewSection.exercise => l10n.mockShellExercise,
  PreviewSection.settings => l10n.mockShellSettings,
};

String _mobileNavLabel(AppLocalizations l10n, PreviewSection section) => switch (section) {
  PreviewSection.library => l10n.mockShellNavMaterials,
  PreviewSection.notebooks => l10n.mockShellNavNotebooks,
  _ => _sectionLabel(l10n, section),
};

String _activeLanguageLabel(AppLocalizations l10n, String language) => switch (language) {
  'ja' => l10n.mockShellJapanese,
  'en' => l10n.mockShellEnglish,
  _ => language,
};

PreviewSection sectionFor(String location) {
  if (location.startsWith(AppRoutes.mockNotebooks) ||
      location.startsWith(AppRoutes.mockCollection) ||
      location.startsWith(AppRoutes.mockWordPrefix) ||
      location == AppRoutes.mockDailyWords) {
    return PreviewSection.notebooks;
  }
  if (location.startsWith(AppRoutes.mockQuery)) return PreviewSection.query;
  if (location.startsWith(AppRoutes.mockExercise) ||
      location.startsWith(AppRoutes.mockMistakes) ||
      location.startsWith(AppRoutes.mockDiagnosis)) {
    return PreviewSection.exercise;
  }
  if (location.startsWith(AppRoutes.mockSettings) ||
      location.startsWith(AppRoutes.mockNotifications) ||
      location.startsWith(AppRoutes.mockJobs)) {
    return PreviewSection.settings;
  }
  return PreviewSection.library;
}

void navigateSection(
  BuildContext context,
  PreviewSection section, {
  ValueChanged<String>? onNavigate,
}) {
  final path = switch (section) {
    PreviewSection.library => AppRoutes.mockLibrary,
    PreviewSection.notebooks => AppRoutes.mockNotebooks,
    PreviewSection.query => AppRoutes.mockQuery,
    PreviewSection.exercise => AppRoutes.mockExercise,
    PreviewSection.settings => AppRoutes.mockSettings,
  };
  if (onNavigate != null) {
    onNavigate(path);
  } else {
    context.go(path);
  }
}

class PreviewPageFrame extends StatelessWidget {
  const PreviewPageFrame({
    required this.location,
    required this.title,
    required this.mobile,
    required this.desktop,
    this.detail = false,
    this.detailNotifications = true,
    this.mobileActions = const [],
    this.mobileHeader,
    this.mobileBackground,
    this.desktopBackLabel,
    this.onBack,
    this.onNavigate,
    super.key,
  });

  final String location;
  final String title;
  final Widget mobile;
  final Widget desktop;
  final bool detail;
  final bool detailNotifications;
  final List<Widget> mobileActions;
  final Widget? mobileHeader;
  final Color? mobileBackground;
  final String? desktopBackLabel;
  final VoidCallback? onBack;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final actions = PreviewShellActionScope.maybeOf(context);
    if (actions != null && (ModalRoute.isCurrentOf(context) ?? true)) {
      final routePath = GoRouterState.of(context).uri.path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
          actions.register(routePath, desktopBackLabel, onBack, onNavigate, detailNotifications);
        }
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? MobilePreviewShell(
              location: location,
              title: title,
              detail: detail,
              detailNotifications: detailNotifications,
              actions: mobileActions,
              header: mobileHeader,
              background: mobileBackground,
              onBack: onBack,
              child: mobile,
            )
          : DesktopPreviewShell(
              location: location,
              title: title,
              backLabel: desktopBackLabel,
              onBack: onBack,
              onNavigate: onNavigate,
              child: desktop,
            ),
    );
  }
}

class MobilePreviewShell extends StatelessWidget {
  const MobilePreviewShell({
    required this.location,
    required this.title,
    required this.child,
    this.detail = false,
    this.detailNotifications = true,
    this.actions = const [],
    this.header,
    this.background,
    this.onBack,
    super.key,
  });

  final String location;
  final String title;
  final Widget child;
  final bool detail;
  final bool detailNotifications;
  final List<Widget> actions;
  final Widget? header;
  final Color? background;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final section = sectionFor(location);
    return Scaffold(
      backgroundColor: background ?? roles.canvas,
      body: SafeArea(
        child: Column(
          children: [
            if (header != null)
              Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 8), child: header!)
            else if (detail)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.mockShellBack,
                      onPressed:
                          onBack ??
                          () =>
                              context.canPop() ? context.pop() : navigateSection(context, section),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 19),
                    ),
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 18, 8),
                child: Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'h',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 23,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    ...actions,
                  ],
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Stays mounted while the five root routes replace one another, so Material's
/// selected indicator can animate independently from the page transition.
class PreviewBottomNavigation extends StatelessWidget {
  const PreviewBottomNavigation({required this.location, required this.onSelected, super.key});

  final String location;
  final ValueChanged<PreviewSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final reducedMotion = PreviewStoreScope.of(context).reducedMotion;
    return NavigationBar(
      height: 68,
      animationDuration: HarukaMotion.reduced(context, reducedMotion: reducedMotion)
          ? Duration.zero
          : HarukaMotion.selection,
      selectedIndex: sectionFor(location).index,
      onDestinationSelected: (index) => onSelected(PreviewSection.values[index]),
      destinations: [
        for (var index = 0; index < PreviewSection.values.length; index++)
          NavigationDestination(
            icon: Icon(previewSectionIcons[index]),
            selectedIcon: Icon(previewSectionIcons[index], color: colors.primary),
            label: _mobileNavLabel(l10n, PreviewSection.values[index]),
          ),
      ],
    );
  }
}

class DesktopPreviewShell extends StatelessWidget {
  const DesktopPreviewShell({
    required this.location,
    required this.title,
    required this.child,
    this.backLabel,
    this.onBack,
    this.onNavigate,
    super.key,
  });

  final String location;
  final String title;
  final Widget child;
  final String? backLabel;
  final VoidCallback? onBack;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final store = PreviewStoreScope.of(context);
    final section = sectionFor(location);
    final hosted = PreviewShellHost.of(context);
    if (hosted) {
      return Scaffold(
        backgroundColor: roles.canvas,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth < 900 ? 24.0 : 32.0;
              return Center(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(inset, 14, inset, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: HarukaLayout.pageMaxWidth),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: roles.canvas,
      body: Row(
        children: [
          if (!hosted)
            SizedBox(
              width: 212,
              child: Material(
                color: colors.surface,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 18, 42),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                'h',
                                style: TextStyle(
                                  color: colors.onPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'haruka',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      for (var index = 0; index < PreviewSection.values.length; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                          child: TextButton.icon(
                            onPressed: () => navigateSection(
                              context,
                              PreviewSection.values[index],
                              onNavigate: onNavigate,
                            ),
                            icon: Icon(previewSectionIcons[index], size: 20),
                            label: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_sectionLabel(l10n, PreviewSection.values[index])),
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              foregroundColor: section.index == index
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                              backgroundColor: section.index == index ? roles.selected : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: roles.signal,
                          child: Text(
                            String.fromCharCode(
                              displayNameOrFallback(context, store.displayName).runes.first,
                            ),
                            style: TextStyle(color: roles.onSignal),
                          ),
                        ),
                        title: Text(displayNameOrFallback(context, store.displayName)),
                        subtitle: Text(_activeLanguageLabel(l10n, store.activeLanguage)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onNavigate == null
                            ? context.go(AppRoutes.mockSettings)
                            : onNavigate!(AppRoutes.mockSettings),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(46, 24, 42, 0),
                    child: Row(
                      children: [
                        if (backLabel == null)
                          Text(
                            _activeLanguageLabel(l10n, store.activeLanguage),
                            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                          )
                        else
                          TextButton.icon(
                            onPressed: onBack,
                            icon: const Icon(Icons.chevron_left, size: 18),
                            label: Text(backLabel!),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.onSurfaceVariant,
                              textStyle: const TextStyle(fontSize: 12),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: l10n.mockShellNotifications,
                          onPressed: () => onNavigate == null
                              ? context.push(AppRoutes.mockNotifications)
                              : onNavigate!(AppRoutes.mockNotifications),
                          icon: Badge(
                            isLabelVisible: store.unreadCount > 0,
                            child: const Icon(Icons.notifications_none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(56, 42, 56, 32),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/core/cache/cache_models.dart';

import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/dev/preview/fixture_settings_source.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/fixture_material_remote.dart';
import 'package:haruka/dev/preview/fixture_learning_result_remote.dart';
import 'package:haruka/dev/preview/fixture_collection_remote.dart';
import 'package:haruka/dev/preview/fixture_query_card_collection.dart';
import 'package:haruka/dev/preview/fixture_notification_remote.dart';
import 'package:haruka/features/agent/data/cached_query_result_repository.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/agent/presentation/query_result_scope.dart';
import 'package:haruka/features/agent/presentation/query_card_collection_scope.dart';
import 'package:haruka/features/admin/presentation/admin_pages.dart';
import 'package:haruka/features/library/data/cached_material_catalog.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/notifications/data/cached_notification_repository.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';
import 'package:haruka/features/notifications/presentation/notification_repository_scope.dart';
import 'package:haruka/features/notifications/platform/notification_shade.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

import 'routes.dart';
import 'page_route_activity.dart';
import 'theme.dart';
import 'cache_blocked_screen.dart';

/// Opt-in frontend preview. Production and B1 paths never instantiate this app.
class PreviewHarukaApp extends StatefulWidget {
  const PreviewHarukaApp({
    this.clock = DateTime.now,
    this.materialCatalog,
    this.queryResultRepository,
    this.collectionCatalog,
    this.notificationRepository,
    this.settingsCacheAdapter,
    this.settingsSource,
    super.key,
  });

  final MaterialCatalog? materialCatalog;
  final DateTime Function() clock;
  final QueryResultRepository? queryResultRepository;
  final CollectionCatalog? collectionCatalog;
  final NotificationRepository? notificationRepository;
  final PreviewSettingsCacheAdapter? settingsCacheAdapter;
  final SettingsSource? settingsSource;

  @override
  State<PreviewHarukaApp> createState() => _PreviewHarukaAppState();
}

class _PreviewHarukaAppState extends State<PreviewHarukaApp> with WidgetsBindingObserver {
  final AdminPreviewState adminState = AdminPreviewState();
  final _mobileNavigatorKey = GlobalKey<NavigatorState>();
  final _mobilePageObserver = PageRouteActivityObserver();
  final _activeMobileLocation = ValueNotifier<String>(AppRoutes.mockLibrary);
  final _shellActions = PreviewShellActionRegistry();
  bool _routeSyncScheduled = false;
  NotificationShadeController? _notificationShade;
  StreamSubscription<void>? _notificationScopeChanges;
  StreamSubscription<void>? _cacheStateChanges;
  Timer? _notificationRefresh;
  String? _observedNotificationBinding;
  bool _notificationForeground = true;
  late final PreviewFixtureStore store = PreviewFixtureStore();
  late final PreviewSettingsCacheAdapter settingsCache =
      widget.settingsCacheAdapter ?? PreviewSettingsCacheAdapter();
  late final CachedSettingsRepository settings = CachedSettingsRepository(
    cache: settingsCache.coordinator,
    source: widget.settingsSource ?? FixtureSettingsSource(store, settingsCache.coordinator),
    waitForReadiness: settingsCache.initialize,
  );
  late final MaterialCatalog catalog =
      widget.materialCatalog ??
      CachedMaterialCatalog(
        cache: settingsCache.coordinator,
        remote: FixtureMaterialRemote(store),
        importSource: (type, title, language) async => store.importMaterial(type, title, language),
        deleteSource: (id) async => store.deleteMaterial(id),
      );
  late final QueryResultRepository queryResults =
      widget.queryResultRepository ??
      CachedQueryResultRepository(
        cache: settingsCache.coordinator,
        waitForReadiness: settingsCache.initialize,
        resolveSource: (request) =>
            store.resolveQuery(request, scopeBinding: _requireFixtureQueryScope()),
        generateSource: (request) =>
            store.generateQuery(request, scopeBinding: _requireFixtureQueryScope()),
        remote: FixtureLearningResultRemote(store, settingsCache.coordinator),
      );
  late final CollectionCatalog collections =
      widget.collectionCatalog ??
      CachedCollectionCatalog(
        cache: settingsCache.coordinator,
        waitForReadiness: settingsCache.initialize,
        source: FixtureCollectionSource(store),
      );
  late final FixtureNotificationRemote notificationRemote = FixtureNotificationRemote(store);
  late final FixtureQueryCardCollection queryCardCollection = FixtureQueryCardCollection(
    store: store,
    catalog: collections,
    cache: settingsCache.coordinator,
  );
  late final NotificationRepository notifications =
      widget.notificationRepository ??
      CachedNotificationRepository(
        cache: settingsCache.coordinator,
        remote: notificationRemote,
        readSource: notificationRemote.markRead,
        readAllSource: notificationRemote.markAllRead,
        waitForReadiness: settingsCache.initialize,
      );
  late final router = createPreviewRouter(clock: widget.clock);

  String _requireFixtureQueryScope() {
    final cache = settingsCache.coordinator;
    final scope = cache.scope;
    if (!cache.accessReady ||
        scope?.endpointKey != 'http://127.0.0.1/mock-preview' ||
        scope?.instanceId != 'preview-fixtures' ||
        scope?.userId != 'preview-user' ||
        scope?.audience != 'client') {
      throw const CacheBlocked('identity_unconfirmed');
    }
    return scope!.binding;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    router.routerDelegate.addListener(_scheduleMobileRouteSync);
    router.routeInformationProvider.addListener(_scheduleMobileRouteSync);
    _cacheStateChanges = settingsCache.coordinator.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_initializeCatalog());
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _notificationShade = NotificationShadeController(
        repository: notifications,
        shade: AndroidNotificationShade(),
        currentBinding: _currentNotificationBinding,
        onOpen: () => router.go(AppRoutes.mockNotifications),
      );
      _notificationScopeChanges = settingsCache.coordinator.changes.listen((_) {
        final binding = _currentNotificationBinding();
        if (binding == _observedNotificationBinding) return;
        _observedNotificationBinding = binding;
        unawaited(_notificationShade!.synchronize(refresh: _notificationForeground));
      });
      _notificationRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_notificationForeground) unawaited(_notificationShade!.synchronize());
      });
      unawaited(_notificationShade!.start());
    }
  }

  String? _currentNotificationBinding() {
    final cache = settingsCache.coordinator;
    return cache.accessReady ? cache.scope?.binding : null;
  }

  void _scheduleMobileRouteSync() {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      _syncMobileRoute();
      return;
    }
    if (_routeSyncScheduled) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      _syncMobileRoute();
    });
  }

  void _syncMobileRoute() {
    if (!mounted) return;
    final configuration = router.routerDelegate.currentConfiguration;
    final last = configuration.matches.lastOrNull;
    final location = last is ImperativeRouteMatch ? last.matches.uri.path : configuration.uri.path;
    if (_activeMobileLocation.value != location) _activeMobileLocation.value = location;
  }

  @override
  Future<bool> didPopRoute() async {
    final navigator = _mobileNavigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  Future<void> _initializeCatalog() async {
    await settingsCache.initialize();
    if (!mounted || !settingsCache.ready) return;
    try {
      await catalog.refresh();
    } on Object {
      // The domain catalog owns its blocked/error state; startup must not
      // surface an uncaught asynchronous error from a failed preview source.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _notificationForeground;
    _notificationForeground = foregroundAfterLifecycle(state, wasForeground: wasForeground);
    if (!wasForeground && _notificationForeground && settingsCache.ready) {
      // Local invalidation epochs can change while the app is hidden. Reading
      // them does not start a business refresh unless storage actually changed.
      unawaited(settingsCache.coordinator.synchronizeStorage().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationRefresh?.cancel();
    if (_notificationScopeChanges != null) unawaited(_notificationScopeChanges!.cancel());
    _notificationShade?.dispose();
    unawaited(_cacheStateChanges?.cancel());
    router.routerDelegate.removeListener(_scheduleMobileRouteSync);
    router.routeInformationProvider.removeListener(_scheduleMobileRouteSync);
    router.dispose();
    adminState.dispose();
    _activeMobileLocation.dispose();
    _shellActions.dispose();
    settingsCache.dispose();
    settings.dispose();
    if (catalog is CachedMaterialCatalog) (catalog as CachedMaterialCatalog).dispose();
    if (widget.queryResultRepository == null) {
      (queryResults as CachedQueryResultRepository).dispose();
    }
    if (widget.collectionCatalog == null) (collections as CachedCollectionCatalog).dispose();
    if (widget.notificationRepository == null) {
      (notifications as CachedNotificationRepository).dispose();
    }
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminPreviewScope(
    state: adminState,
    child: PreviewSettingsCacheScope(
      adapter: settingsCache,
      child: SettingsRepositoryScope(
        repository: settings,
        child: MaterialCatalogScope(
          catalog: catalog,
          child: QueryResultScope(
            repository: queryResults,
            child: QueryCardCollectionScope(
              repository: queryCardCollection,
              child: CollectionCatalogScope(
                catalog: collections,
                child: NotificationRepositoryScope(
                  repository: notifications,
                  child: PreviewStoreScope(
                    store: store,
                    child: AnimatedBuilder(
                      animation: store,
                      builder: (context, child) => MaterialApp.router(
                        onGenerateTitle: (context) =>
                            AppLocalizations.of(context).mockShellAppTitle,
                        debugShowCheckedModeBanner: false,
                        localizationsDelegates: AppLocalizations.localizationsDelegates,
                        supportedLocales: AppLocalizations.supportedLocales,
                        theme: HarukaTheme.light(),
                        darkTheme: HarukaTheme.dark(),
                        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                          value: HarukaTheme.systemUiOverlayStyle(context),
                          child: switch (settingsCache.coordinator.terminalReason) {
                            'cache_update_required' || 'cache_writer_unavailable' =>
                              CacheBlockedScreen(reason: settingsCache.coordinator.terminalReason!),
                            _ => Navigator(
                              key: _mobileNavigatorKey,
                              observers: [_mobilePageObserver],
                              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                                settings: settings,
                                transitionDuration: Duration.zero,
                                reverseTransitionDuration: Duration.zero,
                                pageBuilder: (outerContext, animation, secondaryAnimation) =>
                                    PreviewPersistentShell(
                                      location: _activeMobileLocation,
                                      onNavigate: router.go,
                                      onBack: () => router.canPop()
                                          ? router.pop()
                                          : router.go(switch (sectionFor(
                                              _activeMobileLocation.value,
                                            )) {
                                              PreviewSection.library => AppRoutes.mockLibrary,
                                              PreviewSection.notebooks => AppRoutes.mockNotebooks,
                                              PreviewSection.query => AppRoutes.mockQuery,
                                              PreviewSection.exercise => AppRoutes.mockExercise,
                                              PreviewSection.settings => AppRoutes.mockSettings,
                                            }),
                                      onOpenNotifications: () =>
                                          unawaited(router.push<void>(AppRoutes.mockNotifications)),
                                      actions: _shellActions,
                                      adminFrameBuilder: (context, location, child) =>
                                          AdminPersistentFrame(
                                            location: location,
                                            onNavigate: router.go,
                                            child: child,
                                          ),
                                      child: child,
                                    ),
                              ),
                            ),
                          },
                        ),
                        themeMode: switch (store.themeMode) {
                          'light' => ThemeMode.light,
                          'dark' => ThemeMode.dark,
                          _ => ThemeMode.system,
                        },
                        routerConfig: router,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

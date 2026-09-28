import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/auth_repository.dart';
import '../core/cache/cache_coordinator.dart';
import '../core/cache/cache_session_binding.dart';
import '../core/auth/email_action_link.dart';
import '../core/telemetry/telemetry.dart';
import '../dev/preview/fixture_store.dart';
import '../dev/preview/settings_cache_adapter.dart';
import '../features/collections/reference_controller.dart';
import '../features/collections/reference_repository.dart';
import '../features/settings/data/cached_settings_repository.dart';
import '../features/settings/data/http_settings_source.dart';
import '../features/settings/data/language_capabilities.dart';
import '../features/settings/data/service_endpoint_store.dart';
import '../features/settings/domain/settings_snapshot.dart';
import '../features/settings/domain/service_endpoint.dart';
import '../features/settings/presentation/service_endpoint_form.dart';
import '../features/settings/presentation/settings_chrome.dart';
import '../features/settings/presentation/settings_pages.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';
import 'routes.dart';
import 'theme.dart';
import 'cache_blocked_screen.dart';

export 'routes.dart' show createRouter;

ThemeData appTheme() => HarukaTheme.light();

class HarukaApp extends StatefulWidget {
  const HarukaApp({
    required this.config,
    this.initialLocation,
    this.api,
    this.emailAction,
    this.installErrorHandlers = false,
    super.key,
  });

  final AppConfig config;
  final String? initialLocation;
  final ApiClient? api;
  final CapturedEmailAction? emailAction;
  final bool installErrorHandlers;

  @override
  State<HarukaApp> createState() => _HarukaAppState();
}

class _HarukaAppState extends State<HarukaApp> {
  late final GoRouter _router;
  late final ApiClient _api;
  late final ProviderContainer _providers;
  late final AuthController _auth;
  late final CacheCoordinator _cache;
  late final CacheSessionBinding _cacheBinding;
  late final PreviewFixtureStore _settingsDraft;
  late final PreviewSettingsCacheAdapter _settingsCache;
  late final CachedSettingsRepository _settingsRepository;
  late final ServiceEndpointController _serviceEndpoints;
  final ServiceEndpointStore _endpointStore = ServiceEndpointStore();
  StreamSubscription<void>? _cacheChanges;
  late final Telemetry _telemetry;
  FlutterExceptionHandler? _previousFlutterError;
  bool Function(Object, StackTrace)? _previousPlatformError;
  String? _lastRoute;
  SemanticsHandle? _semantics;
  int? _preferencesRequestedScope;
  int? _languagesRequestedScope;
  LanguageCapabilities? _languages;
  bool _languageReadFailed = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiClient(widget.config, requireSessionBinding: true);
    _cache = CacheCoordinator(
      onEvent: (event, attributes) => _telemetry.track(event, attributes: attributes),
    );
    _providers = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(widget.config),
        cacheCoordinatorProvider.overrideWithValue(_cache),
        authRepositoryProvider.overrideWithValue(AuthRepository(_api, widget.config)),
        referenceRepositoryProvider.overrideWithValue(ReferenceRepository(_api)),
        telemetryProvider.overrideWith((ref) => _telemetry),
      ],
    );
    _auth = _providers.read(authControllerProvider);
    _cacheBinding = CacheSessionBinding(
      _auth,
      widget.config,
      _cache,
      endpoint: () => _api.endpoint,
      instanceId: () => _api.instanceId,
    );
    _serviceEndpoints = ServiceEndpointController(
      canSwitch: widget.config.platform != AppPlatform.web,
      allowDevelopmentHttp: widget.config.environment == 'dev',
      currentEndpoint: () => _api.endpoint,
      currentInstance: () => _api.instanceId,
      signedIn: () => _auth.isAuthenticated,
      probe: probeServiceEndpoint,
      signOut: () => _auth.signOut(),
      clearCache: _cache.closeScope,
      retarget: _api.retarget,
      stopOldActions: _auth.invalidateForInstanceSwitch,
      resumeActions: _auth.finishInstanceSwitch,
      bindInstance: _auth.adoptInstance,
      verify: () async {
        await _api.verifyInstance();
        await _auth.reloadPolicy();
        if (widget.config.platform == AppPlatform.web) return;
        await _endpointStore.save(_api.endpoint, _api.instanceId);
      },
      recordProbe: ({required result, required durationMs}) {
        _telemetry.track(
          'connection.probed',
          attributes: {'result': result, 'duration_ms': durationMs},
        );
      },
      recordSwitch: ({required result}) {
        _telemetry.track(
          'account.scope.changed',
          attributes: {'reason': 'instance_switch', 'result': result},
        );
      },
    );
    _settingsDraft = PreviewFixtureStore();
    _settingsCache = PreviewSettingsCacheAdapter(coordinator: _cache, ownsScope: false);
    _settingsRepository = CachedSettingsRepository(
      cache: _cache,
      source: HttpSettingsSource(
        _api,
        read: <T>(action) => _auth.authorizedRead(action),
        write: <T>(action) => _auth.authorizedWrite(action),
      ),
      waitForReadiness: () => _cacheBinding.settled,
    );
    _settingsRepository.addListener(_onSettingsChanged);
    _auth.addListener(_onAuthChanged);
    _cacheChanges = _cache.changes.listen((_) {
      _requestPreferencesForScope();
      _requestLanguagesForScope();
      if (mounted) setState(() {});
    });
    _telemetry = Telemetry(widget.config, _api, _auth);
    _api.beginRequestObservation = _telemetry.beginHttpObservation;
    _router = createRouter(
      widget.config,
      _api,
      _auth,
      initialLocation: widget.initialLocation,
      emailAction: widget.emailAction,
      telemetry: _telemetry,
      settingsPage: (context, section) => AccountSettingsHost(
        store: _settingsDraft,
        cache: _settingsCache,
        repository: _settingsRepository,
        child: section == null
            ? const SettingsPage(framed: false)
            : SettingsDetailPage(section: section, framed: false),
      ),
      settingsSource: _settingsRepository.source,
      settingsRepository: _settingsRepository,
    );
    _router.routeInformationProvider.addListener(_observeRoute);
    _observeRoute();
    _telemetry.track('app.started');
    if (widget.installErrorHandlers) {
      _previousFlutterError = FlutterError.onError;
      FlutterError.onError = (details) =>
          _telemetry.captureException(category: 'flutter_framework', stack: details.stack);
      _previousPlatformError = WidgetsBinding.instance.platformDispatcher.onError;
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        _telemetry.captureException(category: 'dart_unhandled', stack: stack);
        return true;
      };
    }
    unawaited(_openSavedEndpoint());
    if (kIsWeb) {
      _semantics = SemanticsBinding.instance.ensureSemantics();
    }
  }

  @override
  void dispose() {
    if (widget.installErrorHandlers) {
      FlutterError.onError = _previousFlutterError;
      WidgetsBinding.instance.platformDispatcher.onError = _previousPlatformError;
    }
    _serviceEndpoints.dispose();
    _auth.removeListener(_onAuthChanged);
    _settingsRepository.removeListener(_onSettingsChanged);
    _settingsRepository.dispose();
    _settingsCache.dispose();
    _settingsDraft.dispose();
    _router.routeInformationProvider.removeListener(_observeRoute);
    _router.dispose();
    _api.beginRequestObservation = null;
    unawaited(_cacheChanges?.cancel());
    unawaited(_cacheBinding.dispose());
    unawaited(_telemetry.dispose());
    _providers.dispose();
    if (widget.api == null) _api.close();
    _semantics?.dispose();
    super.dispose();
  }

  Future<void> _openSavedEndpoint() async {
    final saved = await _endpointStore.read(
      allowDevelopmentHttp: widget.config.environment == 'dev',
    );
    if (!mounted) return;
    if (saved != null && widget.config.platform != AppPlatform.web) {
      _api.retarget(saved.endpoint, saved.instanceId);
      _auth.adoptInstance(saved.endpoint, saved.instanceId);
    }
    await _auth.start(admin: (widget.initialLocation ?? Uri.base.path).startsWith(AppRoutes.admin));
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    _requestPreferencesForScope();
    _requestLanguagesForScope();
    if (mounted) setState(() {});
  }

  void _requestLanguagesForScope() {
    if (!_auth.isAuthenticated || _auth.admin) {
      _languagesRequestedScope = null;
      _languages = null;
      _languageReadFailed = false;
      return;
    }
    final scope = _cache.scopeGeneration;
    if (_languagesRequestedScope == scope) return;
    _languagesRequestedScope = scope;
    _languages = null;
    _languageReadFailed = false;
    unawaited(
      Future<void>(() async {
        try {
          final loaded = await readLanguageCapabilities(_api, _auth);
          if (!mounted ||
              !_auth.isAuthenticated ||
              _auth.admin ||
              _languagesRequestedScope != scope ||
              _cache.scopeGeneration != scope) {
            return;
          }
          setState(() {
            _languages = loaded;
            _languageReadFailed = false;
          });
        } on Object {
          if (!mounted || _languagesRequestedScope != scope || _cache.scopeGeneration != scope) {
            return;
          }
          setState(() {
            _languagesRequestedScope = null;
            _languageReadFailed = true;
          });
        }
      }),
    );
  }

  void _requestPreferencesForScope() {
    if (!_auth.isAuthenticated ||
        _auth.admin ||
        !(_auth.access?.allows('client.profile.read') ?? false)) {
      _preferencesRequestedScope = null;
      return;
    }
    final scope = _settingsRepository.scopeGeneration;
    if (_preferencesRequestedScope == scope) return;
    _preferencesRequestedScope = scope;
    scheduleMicrotask(() => _settingsRepository.refresh(SettingsGroup.preferences));
  }

  void _observeRoute() {
    final path = _router.routeInformationProvider.value.uri.path;
    if (path == _lastRoute) return;
    _lastRoute = path;
    final screen = switch (path) {
      AppRoutes.home => 'welcome',
      AppRoutes.login => 'login',
      AppRoutes.register => 'register',
      AppRoutes.recovery => 'recovery',
      AppRoutes.verifyEmail => 'verify_email',
      AppRoutes.resetPassword => 'reset_password',
      AppRoutes.account => 'account',
      AppRoutes.accountSessions || AppRoutes.adminSessions => 'sessions',
      AppRoutes.materials => 'materials',
      AppRoutes.collections => 'collection',
      AppRoutes.settings => 'settings',
      AppRoutes.admin => 'admin_policy',
      _ => null,
    };
    if (screen != null) _telemetry.track('screen.viewed', attributes: {'screen_name': screen});
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _auth.isAuthenticated
        ? _settingsRepository.snapshot(SettingsGroup.preferences)
        : null;
    final themeMode = switch (preferences?.fields['theme_mode']) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final reduceMotion = preferences?.fields['reduce_motion'] == 'on';
    return UncontrolledProviderScope(
      container: _providers,
      child: MaterialApp.router(
        title: widget.config.displayName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: appTheme(),
        darkTheme: HarukaTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => ServiceEndpointScope(
          controller: _serviceEndpoints,
          child: LanguageCapabilitiesScope(
            value: _languages,
            failed: _languageReadFailed,
            retry: _requestLanguagesForScope,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: MediaQuery.disableAnimationsOf(context) || reduceMotion,
              ),
              child: AnimatedBuilder(
                animation: _cacheBinding.foregroundRevalidating,
                builder: (context, _) {
                  final revalidating = _cacheBinding.foregroundRevalidating.value;
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: HarukaTheme.systemUiOverlayStyle(context),
                    child: switch (_cache.terminalReason) {
                      'cache_update_required' || 'cache_writer_unavailable' => CacheBlockedScreen(
                        reason: _cache.terminalReason!,
                      ),
                      _ => Stack(
                        children: [
                          Positioned.fill(
                            child: Offstage(
                              offstage: revalidating,
                              child: ExcludeFocus(
                                excluding: revalidating,
                                child: IgnorePointer(
                                  ignoring: revalidating,
                                  child: child ?? const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                          if (revalidating)
                            const Positioned.fill(
                              child: CacheBlockedScreen(reason: 'revalidating'),
                            ),
                        ],
                      ),
                    },
                  );
                },
              ),
            ),
          ),
        ),
        routerConfig: _router,
      ),
    );
  }
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: appTheme(),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: HarukaTheme.systemUiOverlayStyle(context),
      child: child ?? const SizedBox.shrink(),
    ),
    home: Builder(
      builder: (context) {
        final strings = AppLocalizations.of(context);
        return Identified(
          id: UiTestIds.configurationError,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              strings.configurationTitle,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              strings.configurationDescription,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

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
import '../features/collections/reference_controller.dart';
import '../features/collections/reference_repository.dart';
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
  StreamSubscription<void>? _cacheChanges;
  late final Telemetry _telemetry;
  FlutterExceptionHandler? _previousFlutterError;
  bool Function(Object, StackTrace)? _previousPlatformError;
  String? _lastRoute;
  SemanticsHandle? _semantics;

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
    _cacheBinding = CacheSessionBinding(_auth, widget.config, _cache);
    _cacheChanges = _cache.changes.listen((_) {
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
    unawaited(
      _auth.start(admin: (widget.initialLocation ?? Uri.base.path).startsWith(AppRoutes.admin)),
    );
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
      AppRoutes.admin => 'admin_policy',
      _ => null,
    };
    if (screen != null) _telemetry.track('screen.viewed', attributes: {'screen_name': screen});
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _providers,
    child: MaterialApp.router(
      title: widget.config.displayName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appTheme(),
      builder: (context, child) => AnimatedBuilder(
        animation: _cacheBinding.foregroundRevalidating,
        builder: (context, _) {
          final revalidating = _cacheBinding.foregroundRevalidating.value;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: HarukaTheme.systemUiOverlayStyle(context),
            child: switch (_cache.terminalReason) {
              'cache_update_required' ||
              'cache_writer_unavailable' => CacheBlockedScreen(reason: _cache.terminalReason!),
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
                    const Positioned.fill(child: CacheBlockedScreen(reason: 'revalidating')),
                ],
              ),
            },
          );
        },
      ),
      routerConfig: _router,
    ),
  );
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

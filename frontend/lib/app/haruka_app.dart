import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/api/api_client.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';
import 'app_shell.dart';
import 'environment_page.dart';
import 'home_page.dart';
import 'platform_routes.dart';
import 'status_page.dart';

GoRouter createRouter(AppConfig config, ApiClient api, {String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          AppShell(config: config, location: state.uri.path, child: const HomePage()),
    ),
    GoRoute(
      path: '/environment',
      builder: (context, state) => AppShell(
        config: config,
        location: state.uri.path,
        child: EnvironmentPage(config: config, api: api),
      ),
    ),
    ...platformRoutes(),
  ],
  errorBuilder: (context, state) {
    final strings = AppLocalizations.of(context);
    return StatusPage(
      id: UiTestIds.notFoundPage,
      title: strings.notFoundTitle,
      description: strings.notFoundDescription,
    );
  },
);

ThemeData appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff2563eb),
    primary: const Color(0xff2563eb),
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: Colors.white,
  navigationRailTheme: const NavigationRailThemeData(backgroundColor: Color(0xfff5f6f8)),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
);

class HarukaApp extends StatefulWidget {
  const HarukaApp({required this.config, this.initialLocation, this.api, super.key});

  final AppConfig config;
  final String? initialLocation;
  final ApiClient? api;

  @override
  State<HarukaApp> createState() => _HarukaAppState();
}

class _HarukaAppState extends State<HarukaApp> {
  late final GoRouter _router;
  late final ApiClient _api;
  SemanticsHandle? _semantics;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiClient(widget.config);
    _router = createRouter(widget.config, _api, initialLocation: widget.initialLocation);
    if (kIsWeb) _semantics = SemanticsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
    _router.dispose();
    if (widget.api == null) _api.close();
    _semantics?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: widget.config.displayName,
    debugShowCheckedModeBanner: false,
    locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: appTheme(),
    routerConfig: _router,
  );
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: appTheme(),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.configurationTitle,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(strings.configurationDescription),
                    ],
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

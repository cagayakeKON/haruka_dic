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
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: Color(0xff2457ed),
    onPrimary: Colors.white,
    primaryContainer: Color(0xffe8efff),
    onPrimaryContainer: Color(0xff152b42),
    secondary: Color(0xffd8f36a),
    onSecondary: Color(0xff26370b),
    surface: Colors.white,
    onSurface: Color(0xff152b42),
    onSurfaceVariant: Color(0xff58697b),
    outline: Color(0xffdde5ee),
  ),
  scaffoldBackgroundColor: const Color(0xfff4f7fb),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, height: 1.2),
    headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25),
    titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.3),
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
    bodyLarge: TextStyle(fontSize: 16, height: 1.55),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xffe8efff),
    surfaceTintColor: Colors.transparent,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xfff4f7fb),
    foregroundColor: Color(0xff152b42),
    surfaceTintColor: Colors.transparent,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
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

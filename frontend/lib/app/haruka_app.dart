import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart';
import '../core/api/api_client.dart';
import '../core/api/request_ids.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/email_action_link.dart';
import '../core/telemetry/telemetry.dart';
import '../features/auth/account_pages.dart';
import '../features/auth/auth_forms.dart';
import '../features/auth/email_action_page.dart';
import '../features/collections/reference_controller.dart';
import '../features/collections/reference_pages.dart';
import '../features/collections/reference_repository.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';
import 'app_shell.dart';
import 'environment_page.dart';
import 'home_page.dart';
import 'platform_routes.dart';
import 'status_page.dart';

ValueKey<String> _accountScope(AppConfig config, AuthController auth, String page) {
  final access = auth.access;
  return ValueKey(
    [
      page,
      config.instanceId,
      access?.userId ?? '',
      access?.audience ?? '',
      access?.sessionRef ?? '',
      access?.authzVersion.user ?? 0,
      access?.authzVersion.policy ?? 0,
    ].join(':'),
  );
}

Widget _watchAuth(AuthController auth, Widget Function() build) =>
    ListenableBuilder(listenable: auth, builder: (context, child) => build());

GoRouter createRouter(
  AppConfig config,
  ApiClient api,
  AuthController auth, {
  String? initialLocation,
  CapturedEmailAction? emailAction,
  Telemetry? telemetry,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: auth,
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
    GoRoute(
      path: '/login',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.phase == AuthPhase.starting || auth.phase == AuthPhase.unavailable
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start()),
              )
            : CredentialFormPage(
                mode: CredentialMode.clientLogin,
                registrationEnabled: auth.policy?.registrationEnabled ?? false,
                onSubmit: (email, password) async {
                  final router = GoRouter.of(context);
                  final watch = Stopwatch()..start();
                  final operationId = newRequestId();
                  bool active;
                  final login = auth.login(email, password, operationId: operationId);
                  final attemptEpoch = auth.actionEpoch;
                  try {
                    active = await login;
                  } on Object {
                    if (auth.actionEpoch != attemptEpoch) return;
                    telemetry?.track(
                      'auth.login.result',
                      attributes: {
                        'result': 'failure',
                        'transport': config.platform == AppPlatform.web ? 'web' : 'native',
                        'duration_ms': watch.elapsedMilliseconds,
                        'error_category': 'authentication',
                      },
                      operationId: operationId,
                    );
                    rethrow;
                  }
                  if (auth.actionEpoch != attemptEpoch) return;
                  if (!active && auth.phase != AuthPhase.pendingEmail) return;
                  telemetry?.track(
                    'auth.login.result',
                    attributes: {
                      'result': active
                          ? 'success'
                          : auth.phase == AuthPhase.pendingEmail
                          ? 'denied'
                          : 'denied',
                      'transport': config.platform == AppPlatform.web ? 'web' : 'native',
                      'duration_ms': watch.elapsedMilliseconds,
                    },
                    operationId: operationId,
                  );
                  if (active) {
                    router.go('/account');
                  } else if (auth.phase == AuthPhase.pendingEmail) {
                    router.go('/activation');
                  }
                },
              ),
      ),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.policy == null
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start()),
              )
            : auth.policy!.registrationEnabled
            ? CredentialFormPage(
                mode: CredentialMode.register,
                passwordMinLength: auth.policy!.passwordMinLength,
                passwordMaxLength: auth.policy!.passwordMaxLength,
                onSubmit: (email, password) async {
                  final router = GoRouter.of(context);
                  final attemptEpoch = auth.actionEpoch;
                  final operationId = newRequestId();
                  telemetry?.track('auth.register.submitted', operationId: operationId);
                  await auth.register(email, password, operationId: operationId);
                  if (auth.actionEpoch == attemptEpoch) {
                    router.go('/registration-received');
                  }
                },
              )
            : StatusPage(
                id: UiTestIds.registerPage,
                title: AppLocalizations.of(context).authRegistrationClosed,
                description: AppLocalizations.of(context).authAdminPolicyHint,
              ),
      ),
    ),
    GoRoute(
      path: '/registration-received',
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authRegisterReceived,
        message: AppLocalizations.of(context).authRegisterReceivedHint,
        actionLocation: '/verify-email',
        actionLabel: AppLocalizations.of(context).authVerifyTitle,
        actionId: UiTestIds.registrationAcceptedVerifyLink,
      ),
    ),
    GoRoute(
      path: '/activation',
      builder: (context, state) =>
          ActivationPage(onStatus: auth.activationStatus, onResend: auth.resend),
    ),
    GoRoute(
      path: '/recovery',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.policy == null || !auth.policy!.recoveryEnabled
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start()),
              )
            : RecoveryRequestPage(
                admin: state.uri.queryParameters['from'] == 'admin',
                onSubmit: (email) async {
                  final router = GoRouter.of(context);
                  final attemptEpoch = auth.actionEpoch;
                  await auth.requestRecovery(email);
                  if (auth.actionEpoch == attemptEpoch) {
                    router.go(
                      state.uri.queryParameters['from'] == 'admin'
                          ? '/recovery-received?from=admin'
                          : '/recovery-received',
                    );
                  }
                },
              ),
      ),
    ),
    GoRoute(
      path: '/recovery-received',
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authRecoveryReceived,
        message: AppLocalizations.of(context).authRecoveryReceivedHint,
        backLocation: state.uri.queryParameters['from'] == 'admin' ? '/admin/login' : '/login',
        actionLocation: '/reset-password',
        actionLabel: AppLocalizations.of(context).authCompleteRecovery,
        actionId: UiTestIds.recoveryAcceptedResetLink,
      ),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.policy == null
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start()),
              )
            : EmailActionPage(
                kind: EmailActionKind.verify,
                trustedActionBase: auth.policy!.actionLinkBase,
                passwordMinLength: auth.policy!.passwordMinLength,
                passwordMaxLength: auth.policy!.passwordMaxLength,
                initialToken: emailAction?.path == '/verify-email' ? emailAction!.token : null,
                onSubmit: (token, _) async {
                  final router = GoRouter.of(context);
                  final attemptEpoch = auth.actionEpoch;
                  await auth.verifyEmail(token);
                  if (auth.actionEpoch == attemptEpoch) router.go('/verified');
                },
              ),
      ),
    ),
    GoRoute(
      path: '/verified',
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authVerified,
        message: AppLocalizations.of(context).authBackToLogin,
      ),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.policy == null
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start()),
              )
            : EmailActionPage(
                kind: EmailActionKind.resetPassword,
                trustedActionBase: auth.policy!.actionLinkBase,
                passwordMinLength: auth.policy!.passwordMinLength,
                passwordMaxLength: auth.policy!.passwordMaxLength,
                initialToken: emailAction?.path == '/reset-password' ? emailAction!.token : null,
                onSubmit: (token, password) async {
                  final router = GoRouter.of(context);
                  final owned = await auth.completeRecovery(token, password!);
                  if (owned) {
                    router.go('/password-changed');
                  }
                },
              ),
      ),
    ),
    GoRoute(
      path: '/password-changed',
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authResetComplete,
        message: AppLocalizations.of(context).authBackToLogin,
      ),
    ),
    GoRoute(
      path: '/signed-out-locally',
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authSignOut,
        message: AppLocalizations.of(context).authSignedOutLocally,
      ),
    ),
    GoRoute(
      path: '/account',
      builder: (context, state) =>
          _watchAuth(auth, () => AccountPage(key: _accountScope(config, auth, 'account'))),
    ),
    GoRoute(
      path: '/account/password',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin
            ? PasswordChangePage(key: _accountScope(config, auth, 'password'))
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    GoRoute(
      path: '/account/sessions',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin
            ? DeviceSessionsPage(key: _accountScope(config, auth, 'sessions'))
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    GoRoute(
      path: '/reference/materials',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin && auth.access!.allows('client.material.list')
            ? ReferenceMaterialsPage(
                key: _accountScope(config, auth, 'reference-materials'),
                scope: _accountScope(config, auth, 'reference-materials').value,
              )
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiPermissionDenied,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    GoRoute(
      path: '/collections',
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin && auth.access!.allows('client.collection.read')
            ? CollectionsPage(
                key: _accountScope(config, auth, 'collections'),
                scope: _accountScope(config, auth, 'collections').value,
              )
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiPermissionDenied,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    ...platformRoutes(
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? AdminPolicyPage(key: _accountScope(config, auth, 'admin-policy'))
            : auth.phase == AuthPhase.starting || auth.phase == AuthPhase.unavailable
            ? AuthUnavailablePage(
                loading: auth.phase == AuthPhase.starting,
                onRetry: () => unawaited(auth.start(admin: true)),
              )
            : CredentialFormPage(
                mode: CredentialMode.adminLogin,
                onSubmit: (email, password) async {
                  final router = GoRouter.of(context);
                  final watch = Stopwatch()..start();
                  final operationId = newRequestId();
                  bool active;
                  final login = auth.login(email, password, admin: true, operationId: operationId);
                  final attemptEpoch = auth.actionEpoch;
                  try {
                    active = await login;
                  } on Object {
                    if (auth.actionEpoch != attemptEpoch) return;
                    telemetry?.track(
                      'auth.login.result',
                      attributes: {
                        'result': 'failure',
                        'transport': 'web',
                        'duration_ms': watch.elapsedMilliseconds,
                        'error_category': 'authentication',
                      },
                      operationId: operationId,
                    );
                    rethrow;
                  }
                  if (auth.actionEpoch != attemptEpoch || !active) return;
                  telemetry?.track(
                    'auth.login.result',
                    attributes: {
                      'result': 'success',
                      'transport': 'web',
                      'duration_ms': watch.elapsedMilliseconds,
                    },
                    operationId: operationId,
                  );
                  router.go('/admin');
                },
              ),
      ),
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? PasswordChangePage(key: _accountScope(config, auth, 'admin-password'), admin: true)
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? DeviceSessionsPage(key: _accountScope(config, auth, 'admin-sessions'), admin: true)
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
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
  late final Telemetry _telemetry;
  FlutterExceptionHandler? _previousFlutterError;
  bool Function(Object, StackTrace)? _previousPlatformError;
  String? _lastRoute;
  SemanticsHandle? _semantics;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiClient(widget.config);
    _providers = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(widget.config),
        authRepositoryProvider.overrideWithValue(AuthRepository(_api, widget.config)),
        referenceRepositoryProvider.overrideWithValue(ReferenceRepository(_api)),
        telemetryProvider.overrideWith((ref) => _telemetry),
      ],
    );
    _auth = _providers.read(authControllerProvider);
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
    unawaited(_auth.start(admin: (widget.initialLocation ?? Uri.base.path).startsWith('/admin')));
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
      '/' => 'welcome',
      '/login' => 'login',
      '/register' => 'register',
      '/recovery' => 'recovery',
      '/verify-email' => 'verify_email',
      '/reset-password' => 'reset_password',
      '/account' => 'account',
      '/account/sessions' || '/admin/sessions' => 'sessions',
      '/reference/materials' => 'materials',
      '/collections' => 'collection',
      '/admin' => 'admin_policy',
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
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appTheme(),
      routerConfig: _router,
    ),
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

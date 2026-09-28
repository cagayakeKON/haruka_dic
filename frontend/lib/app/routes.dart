import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'page_route_activity.dart';

import '../core/config/app_config.dart';
import '../core/api/api_client.dart';
import '../core/api/request_ids.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/email_action_link.dart';
import '../core/telemetry/telemetry.dart';
import '../features/auth/account_pages.dart';
import '../features/auth/auth_forms.dart';
import '../features/auth/email_action_page.dart';
import '../features/collections/reference_pages.dart';

import 'package:haruka/features/ai_exercises/presentation/exercise_pages.dart';
import 'package:haruka/features/admin/presentation/admin_pages.dart';
import 'package:haruka/features/account/presentation/preview_auth_pages.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/features/textbooks/presentation/textbook_practice_page.dart';
import 'package:haruka/features/exams/presentation/exam_result_page.dart';
import 'package:haruka/features/collections/presentation/collection_detail_page.dart';
import 'package:haruka/features/collections/presentation/daily_words_page.dart';
import 'package:haruka/features/collections/presentation/csv_page.dart';
import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/profile_guide.dart';
import 'package:haruka/features/settings/presentation/profile_guide_page.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_snapshot_gate.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/ai_exercises/presentation/exercise_support_pages.dart';
import 'package:haruka/features/notifications/presentation/notifications_page.dart';
import 'package:haruka/features/jobs/presentation/jobs_page.dart';
import 'package:haruka/features/exams/presentation/exam_session_page.dart';
import 'package:haruka/app/preview_shell.dart';

import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import 'app_shell.dart';
import 'environment_page.dart';
import 'home_page.dart';
import 'motion.dart';
import 'query_prefill.dart';
import 'status_page.dart';

/// Every application location is declared here. Feature widgets use these constants.
abstract final class AppRoutes {
  static const home = '/';
  static const environment = '/environment';
  static const login = '/login';
  static const register = '/register';
  static const registrationReceived = '/registration-received';
  static const activation = '/activation';
  static const recovery = '/recovery';
  static const recoveryFromAdmin = '/recovery?from=admin';
  static const recoveryReceived = '/recovery-received';
  static const verifyEmail = '/verify-email';
  static const verified = '/verified';
  static const resetPassword = '/reset-password';
  static const passwordChanged = '/password-changed';
  static const signedOutLocally = '/signed-out-locally';
  static const account = '/account';
  static const accountPassword = '/account/password';
  static const accountSessions = '/account/sessions';
  static const materials = '/reference/materials';
  static const collections = '/collections';
  static const settings = '/settings';
  static const settingsSection = '/settings/:section';
  static const guide = '/guide';
  static const admin = '/admin';
  static const adminLogin = '/admin/login';
  static const adminPassword = '/admin/password';
  static const adminSessions = '/admin/sessions';
  static const mockLibrary = '/mock/library';
  static const mockLogin = '/mock/login';
  static const mockRegister = '/mock/register';
  static const mockImport = '/mock/import';
  static const mockMaterial = '/mock/material/:id';
  static const mockMaterialDetails = '/mock/material/:id/details';
  static const mockNotebooks = '/mock/notebooks';
  static const mockDailyWords = '/mock/daily-words';
  static const mockCollection = '/mock/collection/:id';
  static const mockWord = '/mock/word/:id';
  static const mockWordPrefix = '/mock/word/';
  static const mockCollectionNew = '/mock/collection/new';
  static const mockCsv = '/mock/csv';
  static const mockQuery = '/mock/query';
  static const mockExercise = '/mock/exercise';
  static const mockExerciseBuilder = '/mock/exercise/builder';
  static const mockPractice = '/mock/exercise/practice';
  static const mockTextbookPractice = '/mock/textbook/practice';
  static const mockMistakes = '/mock/mistakes';
  static const mockMistake = '/mock/mistakes/:index';
  static const mockDiagnosis = '/mock/diagnosis';
  static const mockExamSession = '/mock/exam/session';
  static const mockExamResult = '/mock/exam/result';
  static const mockSettings = '/mock/settings';
  static const mockSetting = '/mock/settings/:section';
  static const mockNotifications = '/mock/notifications';
  static const mockJobs = '/mock/jobs';
  static const mockAdminLogin = '/mock/admin/login';
  static const mockAdmin = '/mock/admin/:section';

  static String mockMaterialPath(String id) => '/mock/material/$id';
  static String mockMaterialDetailsPath(String id) => '/mock/material/$id/details';
  static String mockCollectionPath(String id) => '/mock/collection/$id';
  static String mockWordPath(String id) => '$mockWordPrefix$id';
  static String mockMistakePath(int index) => '/mock/mistakes/$index';
  static String mockSettingPath(String section) => '/mock/settings/$section';
  static String mockAdminPath(String section) => '/mock/admin/$section';
}

/// Preview locations remain private to the mock build and never call the API.
GoRoute _previewRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) => GoRoute(
  path: path,
  pageBuilder: (context, state) {
    final reduced = HarukaMotion.reduced(
      context,
      reducedMotion: PreviewStoreScope.of(context).reducedMotion,
    );
    final root = const {
      AppRoutes.mockLibrary,
      AppRoutes.mockNotebooks,
      AppRoutes.mockQuery,
      AppRoutes.mockExercise,
      AppRoutes.mockSettings,
    }.contains(path);
    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: reduced ? Duration.zero : HarukaMotion.pageEnter,
      reverseTransitionDuration: reduced ? Duration.zero : HarukaMotion.exit,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          HarukaMotion.pageTransition(context, animation, secondaryAnimation, child, root: root),
      child: builder(context, state),
    );
  },
);

GoRouter createPreviewRouter() {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
    initialLocation: AppRoutes.mockLibrary,
    observers: [PageRouteActivityObserver()],
    routes: [
      _previewRoute(
        path: AppRoutes.mockLogin,
        builder: (context, state) => const PreviewLoginPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockRegister,
        builder: (context, state) => const PreviewRegisterPage(),
      ),
      _previewRoute(path: AppRoutes.mockLibrary, builder: (context, state) => const LibraryPage()),
      _previewRoute(path: AppRoutes.mockImport, builder: (context, state) => const ImportPage()),
      _previewRoute(
        path: AppRoutes.mockMaterial,
        builder: (context, state) => MaterialEntryPage(materialId: state.pathParameters['id']!),
      ),
      _previewRoute(
        path: AppRoutes.mockMaterialDetails,
        builder: (context, state) => MaterialDetailsPage(materialId: state.pathParameters['id']!),
      ),
      _previewRoute(
        path: AppRoutes.mockNotebooks,
        builder: (context, state) => const NotebooksPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockDailyWords,
        builder: (context, state) => const DailyWordsPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockCollectionNew,
        builder: (context, state) => const NewCollectionPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockCollection,
        builder: (context, state) => CollectionDetailPage(itemId: state.pathParameters['id']!),
      ),
      _previewRoute(
        path: AppRoutes.mockWord,
        builder: (context, state) => WordDetailPage(itemId: state.pathParameters['id']!),
      ),
      _previewRoute(path: AppRoutes.mockCsv, builder: (context, state) => const CsvPage()),
      _previewRoute(
        path: AppRoutes.mockQuery,
        builder: (context, state) => ScopedQueryPage(
          prefill: state.extra is QueryPrefill ? state.extra! as QueryPrefill : null,
        ),
      ),
      _previewRoute(
        path: AppRoutes.mockExercise,
        builder: (context, state) => const ExercisePage(),
      ),
      _previewRoute(
        path: AppRoutes.mockExerciseBuilder,
        builder: (context, state) => const ExerciseBuilderPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockPractice,
        builder: (context, state) => const PracticePage(),
      ),
      _previewRoute(
        path: AppRoutes.mockTextbookPractice,
        builder: (context, state) => const TextbookPracticePage(),
      ),
      _previewRoute(
        path: AppRoutes.mockMistakes,
        builder: (context, state) => const MistakesPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockMistake,
        builder: (context, state) =>
            MistakeDetailPage(index: int.tryParse(state.pathParameters['index']!) ?? -1),
      ),
      _previewRoute(
        path: AppRoutes.mockDiagnosis,
        builder: (context, state) => const DiagnosisPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockExamSession,
        builder: (context, state) => const ExamSessionPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockExamResult,
        builder: (context, state) =>
            ExamResultPage(answers: PreviewStoreScope.of(context).examAnswers),
      ),
      _previewRoute(
        path: AppRoutes.mockSettings,
        builder: (context, state) => const SettingsPage(),
      ),
      _previewRoute(
        path: AppRoutes.mockSetting,
        builder: (context, state) => SettingsDetailPage(section: state.pathParameters['section']!),
      ),
      _previewRoute(
        path: AppRoutes.mockNotifications,
        builder: (context, state) => const NotificationsPage(),
      ),
      _previewRoute(path: AppRoutes.mockJobs, builder: (context, state) => const JobsPage()),
      _previewRoute(
        path: AppRoutes.mockAdminLogin,
        builder: (context, state) => const AdminPage(section: 'login'),
      ),
      _previewRoute(
        path: AppRoutes.mockAdmin,
        builder: (context, state) =>
            AdminPage(section: state.pathParameters['section'] ?? 'overview'),
      ),
    ],
  );
}

GoRoute _appRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) => GoRoute(
  path: path,
  pageBuilder: (context, state) {
    final reduced = HarukaMotion.reduced(context);
    final root = const {AppRoutes.home, AppRoutes.environment}.contains(path);
    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: reduced ? Duration.zero : HarukaMotion.pageEnter,
      reverseTransitionDuration: reduced ? Duration.zero : HarukaMotion.exit,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          HarukaMotion.pageTransition(context, animation, secondaryAnimation, child, root: root),
      child: builder(context, state),
    );
  },
);

List<RouteBase> _adminRoutes(
  bool enabled,
  Widget Function(BuildContext, GoRouterState) adminBuilder,
  Widget Function(BuildContext, GoRouterState) passwordBuilder,
  Widget Function(BuildContext, GoRouterState) sessionsBuilder,
) => enabled
    ? [
        _appRoute(path: AppRoutes.admin, builder: adminBuilder),
        _appRoute(path: AppRoutes.adminLogin, builder: adminBuilder),
        _appRoute(path: AppRoutes.adminPassword, builder: passwordBuilder),
        _appRoute(path: AppRoutes.adminSessions, builder: sessionsBuilder),
      ]
    : const [];

ValueKey<String> _accountScope(AuthController auth, String page) {
  final access = auth.access;
  return ValueKey(
    [
      page,
      auth.boundInstanceId,
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

Widget _settingsRoute(
  BuildContext context,
  AppConfig config,
  AuthController auth,
  String location,
  SettingsPageBuilder? settingsPage,
  String? section,
) => _watchAuth(auth, () {
  final allowed =
      auth.isAuthenticated && !auth.admin && (auth.access?.allows('client.profile.read') ?? false);
  if (!allowed || settingsPage == null) {
    return StatusPage(
      id: UiTestIds.notFoundPage,
      title: AppLocalizations.of(context).apiPermissionDenied,
      description: AppLocalizations.of(context).authBackToLogin,
    );
  }
  return AppShell(config: config, location: location, child: settingsPage(context, section));
});

typedef SettingsPageBuilder = Widget Function(BuildContext context, String? section);

GoRouter createRouter(
  AppConfig config,
  ApiClient api,
  AuthController auth, {
  String? initialLocation,
  CapturedEmailAction? emailAction,
  Telemetry? telemetry,
  SettingsPageBuilder? settingsPage,
  SettingsSource? settingsSource,
  CachedSettingsRepository? settingsRepository,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: auth,
  routes: [
    _appRoute(
      path: AppRoutes.home,
      builder: (context, state) =>
          AppShell(config: config, location: state.uri.path, child: const HomePage()),
    ),
    _appRoute(
      path: AppRoutes.environment,
      builder: (context, state) => AppShell(
        config: config,
        location: state.uri.path,
        child: EnvironmentPage(config: config, api: api),
      ),
    ),
    _appRoute(
      path: AppRoutes.login,
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
                    final location = await profileGuideLocation(
                      canReadProfile: auth.access?.allows('client.profile.read') ?? false,
                      source: settingsSource,
                    );
                    if (auth.actionEpoch != attemptEpoch) return;
                    router.go(location);
                  } else if (auth.phase == AuthPhase.pendingEmail) {
                    router.go(AppRoutes.activation);
                  }
                },
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.register,
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
                    router.go(AppRoutes.registrationReceived);
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
    _appRoute(
      path: AppRoutes.registrationReceived,
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authRegisterReceived,
        message: AppLocalizations.of(context).authRegisterReceivedHint,
        actionLocation: AppRoutes.verifyEmail,
        actionLabel: AppLocalizations.of(context).authVerifyTitle,
        actionId: UiTestIds.registrationAcceptedVerifyLink,
      ),
    ),
    _appRoute(
      path: AppRoutes.activation,
      builder: (context, state) =>
          ActivationPage(onStatus: auth.activationStatus, onResend: auth.resend),
    ),
    _appRoute(
      path: AppRoutes.recovery,
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
                          : AppRoutes.recoveryReceived,
                    );
                  }
                },
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.recoveryReceived,
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authRecoveryReceived,
        message: AppLocalizations.of(context).authRecoveryReceivedHint,
        backLocation: state.uri.queryParameters['from'] == 'admin'
            ? AppRoutes.adminLogin
            : AppRoutes.login,
        actionLocation: AppRoutes.resetPassword,
        actionLabel: AppLocalizations.of(context).authCompleteRecovery,
        actionId: UiTestIds.recoveryAcceptedResetLink,
      ),
    ),
    _appRoute(
      path: AppRoutes.verifyEmail,
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
                initialToken: emailAction?.path == AppRoutes.verifyEmail
                    ? emailAction!.token
                    : null,
                onSubmit: (token, _) async {
                  final router = GoRouter.of(context);
                  final attemptEpoch = auth.actionEpoch;
                  await auth.verifyEmail(token);
                  if (auth.actionEpoch == attemptEpoch) router.go(AppRoutes.verified);
                },
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.verified,
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authVerified,
        message: AppLocalizations.of(context).authBackToLogin,
      ),
    ),
    _appRoute(
      path: AppRoutes.resetPassword,
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
                initialToken: emailAction?.path == AppRoutes.resetPassword
                    ? emailAction!.token
                    : null,
                onSubmit: (token, password) async {
                  final router = GoRouter.of(context);
                  final owned = await auth.completeRecovery(token, password!);
                  if (owned) {
                    router.go(AppRoutes.passwordChanged);
                  }
                },
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.passwordChanged,
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authResetComplete,
        message: AppLocalizations.of(context).authBackToLogin,
      ),
    ),
    _appRoute(
      path: AppRoutes.signedOutLocally,
      builder: (context, state) => AuthResultPage(
        title: AppLocalizations.of(context).authSignOut,
        message: AppLocalizations.of(context).authSignedOutLocally,
      ),
    ),
    _appRoute(
      path: AppRoutes.account,
      builder: (context, state) =>
          _watchAuth(auth, () => AccountPage(key: _accountScope(auth, 'account'))),
    ),
    _appRoute(
      path: AppRoutes.accountPassword,
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin
            ? PasswordChangePage(key: _accountScope(auth, 'password'))
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.accountSessions,
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin
            ? DeviceSessionsPage(key: _accountScope(auth, 'sessions'))
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.materials,
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin && auth.access!.allows('client.material.list')
            ? ReferenceMaterialsPage(
                key: _accountScope(auth, 'reference-materials'),
                scope: _accountScope(auth, 'reference-materials').value,
              )
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiPermissionDenied,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    _appRoute(
      path: AppRoutes.guide,
      builder: (context, state) => _watchAuth(auth, () {
        final repository = settingsRepository;
        final allowed =
            auth.isAuthenticated &&
            !auth.admin &&
            (auth.access?.allows('client.profile.read') ?? false);
        if (!allowed || repository == null) {
          return StatusPage(
            id: UiTestIds.notFoundPage,
            title: AppLocalizations.of(context).apiPermissionDenied,
            description: AppLocalizations.of(context).authBackToLogin,
          );
        }
        return AppShell(
          config: config,
          location: state.uri.path,
          child: SettingsRepositoryScope(
            repository: repository,
            child: SettingsSnapshotGate(
              groups: const {
                SettingsGroup.profile,
                SettingsGroup.studyProfile,
                SettingsGroup.preferences,
              },
              builder: (context) => ProfileGuidePage(
                key: _accountScope(auth, 'profile-guide'),
                canSave: auth.access?.allows('client.profile.update') ?? false,
                profile: repository.snapshot(SettingsGroup.profile)!,
                study: repository.snapshot(SettingsGroup.studyProfile)!,
                preferences: repository.snapshot(SettingsGroup.preferences)!,
                onSkip: () => context.go(AppRoutes.settings),
                onSave: (input) async {
                  final epoch = auth.actionEpoch;
                  final instance = auth.boundInstanceId;
                  final user = auth.access?.userId;
                  final scope = repository.scopeGeneration;
                  final profileBefore = repository.snapshot(SettingsGroup.profile);
                  final studyBefore = repository.snapshot(SettingsGroup.studyProfile);
                  final preferencesBefore = repository.snapshot(SettingsGroup.preferences);
                  bool stillOwned() =>
                      auth.isAuthenticated &&
                      !auth.admin &&
                      auth.actionEpoch == epoch &&
                      auth.boundInstanceId == instance &&
                      auth.access?.userId == user &&
                      repository.scopeGeneration == scope;
                  for (final entry in profileGuidePatches(
                    input,
                    profile: profileBefore,
                    studyProfile: studyBefore,
                    preferences: preferencesBefore,
                  ).entries) {
                    if (!stillOwned()) return;
                    await repository.save(entry.key, entry.value);
                    if (!stillOwned()) return;
                    telemetry?.track(switch (entry.key) {
                      SettingsGroup.profile => 'profile.updated',
                      SettingsGroup.studyProfile => 'study_profile.updated',
                      SettingsGroup.preferences => 'settings.updated',
                    });
                  }
                  if (context.mounted && stillOwned()) context.go(AppRoutes.settings);
                },
              ),
            ),
          ),
        );
      }),
    ),
    _appRoute(
      path: AppRoutes.settings,
      builder: (context, state) =>
          _settingsRoute(context, config, auth, state.uri.path, settingsPage, null),
    ),
    _appRoute(
      path: AppRoutes.settingsSection,
      builder: (context, state) => _settingsRoute(
        context,
        config,
        auth,
        state.uri.path,
        settingsPage,
        state.pathParameters['section'] ?? '',
      ),
    ),
    _appRoute(
      path: AppRoutes.collections,
      builder: (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && !auth.admin && auth.access!.allows('client.collection.read')
            ? CollectionsPage(
                key: _accountScope(auth, 'collections'),
                scope: _accountScope(auth, 'collections').value,
              )
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiPermissionDenied,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
    ),
    ..._adminRoutes(
      config.platform == AppPlatform.web,
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? AdminPolicyPage(key: _accountScope(auth, 'admin-policy'))
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
                  router.go(AppRoutes.admin);
                },
              ),
      ),
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? PasswordChangePage(key: _accountScope(auth, 'admin-password'), admin: true)
            : StatusPage(
                id: UiTestIds.notFoundPage,
                title: AppLocalizations.of(context).apiAuthRequired,
                description: AppLocalizations.of(context).authBackToLogin,
              ),
      ),
      (context, state) => _watchAuth(
        auth,
        () => auth.isAuthenticated && auth.admin
            ? DeviceSessionsPage(key: _accountScope(auth, 'admin-sessions'), admin: true)
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

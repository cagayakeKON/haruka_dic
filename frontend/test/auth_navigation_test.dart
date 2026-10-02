import 'dart:async';
import 'dart:convert';

import 'support/generated/api_compatibility_samples.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async_frames.dart';

import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/auth/email_action_link.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/presentation/settings_chrome.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import 'support/sample_adapter.dart';
import 'features/settings/cached_settings_repository_test.mocks.dart';

final class _EmptyVault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

final class _NoSync implements AuthSync {
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  void dispose() {}
}

void main() {
  setUp(() {
    // Each router is given an explicit starting location. A prior browser test
    // must not supply a different platform deep link to the next test.
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.defaultRouteNameTestValue =
        '/';
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  testWidgets('client login waits for identity startup before accepting input', (tester) async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    final releaseMeta = Completer<void>();
    ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          await releaseMeta.future;
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
            'data': {
              'registration_enabled': false,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': true,
              'recovery_mode': 'email',
              'action_link_base_url': 'https://localhost:18443',
              'password_min_length': 15,
              'password_max_length': 128,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
        case '/api/v1/admin/me/access':
          return jsonBody({
            'error': {'code': 'AUTH_REQUIRED', 'message': 'required', 'field_errors': <Object?>[]},
            'meta': {'request_id': requestId},
          }, 401);
      }
      throw StateError('Unexpected endpoint ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final router = createRouter(config, api, auth, initialLocation: '/login');
    addTearDown(() {
      router.dispose();
      providers.dispose();
      api.close();
    });
    var startupFinished = false;
    await tester.runAsync(() async {
      unawaited(auth.start().whenComplete(() => startupFinished = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp.router(
          locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    const pageId = UiTestIds.loginPage;
    expect(find.byKey(ValueKey<String>(pageId)), findsNothing);
    expect(find.byKey(const ValueKey<String>(UiTestIds.authResultPage)), findsOneWidget);
    releaseMeta.complete();
    for (var attempt = 0; attempt < 50 && !startupFinished; attempt++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(startupFinished, isTrue);
    expect(auth.phase, AuthPhase.anonymous);
    // Router refresh can finish in the real async zone. Keep advancing it
    // while the old loading indicator still schedules fake-zone frames.
    for (
      var attempt = 0;
      attempt < 50 && find.byKey(ValueKey<String>(pageId)).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    await tester.runAsync(() => tester.pump(const Duration(milliseconds: 300)));
    expect(find.byKey(ValueKey<String>(pageId)), findsOneWidget);
    const emailId = UiTestIds.loginEmail;
    await tester.runAsync(() async {
      await tester.enterText(find.byKey(ValueKey<String>(emailId)), 'user@example.test');
      await tester.pump();
    });
    expect(find.text('user@example.test'), findsOneWidget);
  });

  testWidgets('late password reset from A cannot navigate over newer login B', (tester) async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    final resetStarted = Completer<void>();
    final finishReset = Completer<ResponseBody>();
    final requested = <String>[];
    var signedIn = false;
    ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final adapter = SampleAdapter((options, _) async {
      requested.add(options.path);
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
            'data': {
              'registration_enabled': false,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': true,
              'recovery_mode': 'email',
              'action_link_base_url': 'https://localhost:18443',
              'password_min_length': 15,
              'password_max_length': 128,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/recovery/complete':
          resetStarted.complete();
          return finishReset.future;
        case '/api/v1/auth/login':
          signedIn = true;
          return jsonBody(samples['auth_web_authenticated'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {
              'session_ref': '018f1234-0000-7000-8000-000000000002',
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return signedIn
              ? jsonBody(samples['auth_client_access_login_only'] as Object)
              : jsonBody({
                  'error': {
                    'code': 'AUTH_REQUIRED',
                    'message': 'required',
                    'field_errors': <Object?>[],
                  },
                  'meta': {'request_id': requestId},
                }, 401);
        case '/api/v1/users/me/account':
          return jsonBody(samples['auth_account_legacy_unverified'] as Object);
      }
      throw StateError('Unexpected endpoint ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final router = createRouter(
      config,
      api,
      auth,
      initialLocation: '/reset-password',
      emailAction: CapturedEmailAction(path: '/reset-password', token: 'A' * 43),
    );
    addTearDown(() {
      router.dispose();
      providers.dispose();
      api.close();
    });
    await tester.runAsync(auth.start);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp.router(
          locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settleAsyncFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.recoveryCompletePassword)),
      'valid-test-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.recoveryCompleteConfirm)),
      'valid-test-password',
    );
    expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
    final submit = find.byKey(const ValueKey<String>(UiTestIds.recoveryCompleteSubmit));
    await tester.ensureVisible(submit);
    // Start the user action in the real async zone, then interleave real IO
    // and widget microtasks. Waiting on resetStarted inside runAsync would
    // prevent the fake-zone response stream from advancing to the POST.
    await tester.runAsync(() => tester.tap(submit));
    for (var attempt = 0; attempt < 50 && !resetStarted.isCompleted; attempt++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
    expect(resetStarted.isCompleted, isTrue, reason: requested.join(', '));
    expect(find.text('请使用本服务邮件中的正确链接'), findsNothing);
    expect(find.text('账号服务暂不可用，请稍后重试。'), findsNothing);
    expect(find.text('正在重置…'), findsOneWidget);
    expect(requested, contains('/api/v1/auth/recovery/complete'));
    await tester.runAsync(() async {
      expect(await auth.login('b@example.test', 'valid-test-password'), isTrue);
      router.go('/account');
      finishReset.complete(ResponseBody.fromString('', 204));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await settleAsyncFrames(tester);
    expect(router.routeInformationProvider.value.uri.path, '/account');
    expect(find.byKey(const ValueKey<String>(UiTestIds.accountPage)), findsOneWidget);
  });

  testWidgets('successful login navigates after auth notifier rebuilds its form', (tester) async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    var signedIn = false;
    ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
            'data': {
              'registration_enabled': false,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': true,
              'recovery_mode': 'email',
              'action_link_base_url': 'https://localhost:18443',
              'password_min_length': 15,
              'password_max_length': 128,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          signedIn = true;
          return jsonBody(samples['auth_web_authenticated'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {
              'session_ref': '018f1234-0000-7000-8000-000000000002',
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return signedIn
              ? jsonBody(samples['auth_client_access_login_only'] as Object)
              : jsonBody({
                  'error': {
                    'code': 'AUTH_REQUIRED',
                    'message': 'required',
                    'field_errors': <Object?>[],
                  },
                  'meta': {'request_id': requestId},
                }, 401);
        case '/api/v1/users/me/account':
          return jsonBody(samples['auth_account_legacy_unverified'] as Object);
      }
      throw StateError('Unexpected endpoint ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final router = createRouter(config, api, auth, initialLocation: '/login');
    addTearDown(() {
      router.dispose();
      providers.dispose();
      api.close();
    });
    await tester.runAsync(auth.start);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp.router(
          locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settleAsyncFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.loginEmail)),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.loginPassword)),
      'valid-test-password',
    );
    await tester.tap(find.byKey(const ValueKey<String>(UiTestIds.loginSubmit)));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 30 && !auth.isAuthenticated; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await settleAsyncFrames(tester);
    expect(auth.phase, AuthPhase.authenticated);
    expect(router.routeInformationProvider.value.uri.path, '/account');
    expect(find.byKey(const ValueKey<String>(UiTestIds.accountPage)), findsOneWidget);
    auth.pauseAccessDeadline();
  });

  for (final logoutFails in [false, true]) {
    testWidgets(
      'self session revoke ${logoutFails ? 'unknown remote result' : 'confirmed'} navigates after page disposal',
      (tester) async {
        final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
        final config = AppConfig.parse(
          platform: AppPlatform.web,
          environment: 'dev',
          instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
          apiBaseUrl: 'https://localhost:18443',
        );
        const requestId = '018f1234-1234-7123-8123-123456789abc';
        const sessionId = '018f1234-0000-7000-8000-000000000002';
        final finishLogout = Completer<ResponseBody>();
        var signedIn = false;
        var logoutRequested = false;
        ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
          jsonEncode(value),
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
        final adapter = SampleAdapter((options, _) async {
          if (options.path.startsWith('/api/v1/auth/sessions?')) {
            return jsonBody(samples['auth_sessions_page'] as Object);
          }
          switch (options.path) {
            case '/api/v1/meta':
              return jsonBody({
                'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
                'meta': {'request_id': requestId},
              });
            case '/api/v1/auth/policy':
              return jsonBody({
                'data': {
                  'registration_enabled': false,
                  'approval_required': false,
                  'email_verification_required': true,
                  'recovery_enabled': true,
                  'recovery_mode': 'email',
                  'action_link_base_url': 'https://localhost:18443',
                  'password_min_length': 15,
                  'password_max_length': 128,
                },
                'meta': {'request_id': requestId},
              });
            case '/api/v1/auth/login':
              signedIn = true;
              return jsonBody(samples['auth_web_authenticated'] as Object);
            case '/api/v1/auth/csrf':
              return jsonBody({
                'data': {
                  'session_ref': sessionId,
                  'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                },
                'meta': {'request_id': requestId},
              });
            case '/api/v1/me/access':
              return signedIn
                  ? jsonBody(samples['auth_client_access_login_only'] as Object)
                  : jsonBody({
                      'error': {
                        'code': 'AUTH_REQUIRED',
                        'message': 'required',
                        'field_errors': <Object?>[],
                      },
                      'meta': {'request_id': requestId},
                    }, 401);
            case '/api/v1/auth/logout':
              logoutRequested = true;
              return finishLogout.future;
          }
          throw StateError('Unexpected endpoint ${options.path}');
        });
        final api = ApiClient(config, adapter: adapter);
        final auth = AuthController(
          AuthRepository(api, config),
          config,
          vault: _EmptyVault(),
          sync: _NoSync(),
        );
        final providers = ProviderContainer(
          overrides: [authControllerProvider.overrideWith((ref) => auth)],
        );
        final router = createRouter(config, api, auth, initialLocation: '/account/sessions');
        addTearDown(() {
          router.dispose();
          providers.dispose();
          api.close();
        });
        await tester.runAsync(auth.start);
        expect(
          await tester.runAsync(() => auth.login('a@example.test', 'valid-test-password')),
          isTrue,
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: providers,
            child: MaterialApp.router(
              locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await settleAsyncFrames(tester);
        expect(find.byKey(const ValueKey<String>(UiTestIds.accountSessions)), findsOneWidget);
        final revokeId = UiTestIds.sessionRevoke(sessionId);
        for (
          var attempt = 0;
          attempt < 50 && find.byKey(ValueKey<String>(revokeId)).evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump();
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
        expect(find.byKey(ValueKey<String>(revokeId)), findsOneWidget);
        await tester.tap(find.byKey(ValueKey<String>(revokeId)));
        await tester.pump();
        expect(auth.isAuthenticated, isFalse);
        await waitForAsyncState(
          tester,
          () => logoutRequested,
          reason: 'The self revoke must start its remote logout before release',
        );
        await tester.runAsync(() async {
          if (logoutFails) {
            finishLogout.complete(
              jsonBody({
                'error': {
                  'code': 'SERVICE_UNAVAILABLE',
                  'message': 'unavailable',
                  'field_errors': <Object?>[],
                },
                'meta': {'request_id': requestId},
              }, 503),
            );
          } else {
            finishLogout.complete(ResponseBody.fromString('', 204));
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await settleAsyncFrames(tester);
        await waitForAsyncState(
          tester,
          () =>
              router.routeInformationProvider.value.uri.path ==
              (logoutFails ? '/signed-out-locally' : '/login'),
          reason: 'The self revoke must reach its completed logout route',
        );
        expect(
          router.routeInformationProvider.value.uri.path,
          logoutFails ? '/signed-out-locally' : '/login',
        );
      },
    );
  }

  testWidgets('settings security logout reaches login after its page is removed', (tester) async {
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    const sessionId = '018f1234-0000-7000-8000-000000000002';
    final finishLogout = Completer<ResponseBody>();
    var signedIn = false;
    var logoutRequested = false;
    final access =
        jsonDecode(jsonEncode(samples['auth_client_access_login_only'])) as Map<String, dynamic>;
    final permissions = (access['data'] as Map<String, dynamic>)['permissions'] as List<dynamic>;
    permissions.add({'code': 'client.profile.read', 'data_scope': 'self'});
    ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return jsonBody({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/policy':
          return jsonBody({
            'data': {
              'registration_enabled': false,
              'approval_required': false,
              'email_verification_required': true,
              'recovery_enabled': true,
              'recovery_mode': 'email',
              'action_link_base_url': 'https://localhost:18443',
              'password_min_length': 15,
              'password_max_length': 128,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          signedIn = true;
          return jsonBody(samples['auth_web_authenticated'] as Object);
        case '/api/v1/auth/csrf':
          return jsonBody({
            'data': {
              'session_ref': sessionId,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return signedIn
              ? jsonBody(access)
              : jsonBody({
                  'error': {
                    'code': 'AUTH_REQUIRED',
                    'message': 'required',
                    'field_errors': <Object?>[],
                  },
                  'meta': {'request_id': requestId},
                }, 401);
        case '/api/v1/users/me/account':
          return jsonBody(samples['auth_account_legacy_unverified'] as Object);
        case '/api/v1/auth/logout':
          logoutRequested = true;
          return finishLogout.future;
      }
      throw StateError('Unexpected endpoint ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final cache = CacheCoordinator();
    final settings = CachedSettingsRepository(cache: cache, source: MockSettingsSource());
    final store = PreviewFixtureStore();
    final cacheAdapter = PreviewSettingsCacheAdapter(coordinator: cache, ownsScope: false);
    final router = createRouter(
      config,
      api,
      auth,
      initialLocation: '/settings/security',
      settingsPage: (context, section) => AccountSettingsHost(
        store: store,
        cache: cacheAdapter,
        repository: settings,
        child: SettingsDetailPage(section: section!, framed: false),
      ),
    );
    addTearDown(() {
      router.dispose();
      providers.dispose();
      settings.dispose();
      cacheAdapter.dispose();
      store.dispose();
      api.close();
    });
    await tester.runAsync(auth.start);
    expect(
      await tester.runAsync(() => auth.login('a@example.test', 'valid-test-password')),
      isTrue,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp.router(
          locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settleAsyncFrames(tester);
    expect(router.routeInformationProvider.value.uri.path, '/settings/security');
    final logout = find.text('退出登录');
    expect(logout, findsOneWidget);
    await tester.tap(logout);
    await tester.pump();
    expect(auth.isAuthenticated, isFalse);
    expect(find.text('退出登录'), findsNothing);
    await waitForAsyncState(
      tester,
      () => logoutRequested,
      reason: 'The settings logout must start its remote logout before release',
    );
    finishLogout.complete(ResponseBody.fromString('', 204));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await settleAsyncFrames(tester);
    await waitForAsyncState(
      tester,
      () => router.routeInformationProvider.value.uri.path == '/login',
      reason: 'The settings logout must reach its completed logout route',
    );
    expect(router.routeInformationProvider.value.uri.path, '/login');
  });
}

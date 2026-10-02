import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/async_frames.dart';

import 'package:go_router/go_router.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/auth/account_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import '../../support/sample_adapter.dart';

final class _Vault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

final class _Sync implements AuthSync {
  @override
  void dispose() {}
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void publishChanged() {}
  @override
  void publishStarted() {}
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
}

ResponseBody _json(Object data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.defaultRouteNameTestValue =
        '/';
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearDefaultRouteNameTestValue();
  });

  const instanceId = 'haruka-test-0123456789abcdef0123456789abcdef';
  const sessionA = '018f1234-0000-7000-8000-000000000002';
  const sessionB = '018f1234-0000-7000-8000-000000000003';
  const userA = '018f1234-0000-7000-8000-000000000011';
  const userB = '018f1234-0000-7000-8000-000000000012';
  const requestId = '018f1234-1234-7123-8123-123456789abc';

  testWidgets('account read survives layout remount and hides A while B is pending', (
    tester,
  ) async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    var accountGets = 0;
    var currentSession = sessionA;
    final releaseB = Completer<ResponseBody>();
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'client',
              'session_ref': currentSession,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/csrf':
          return _json({
            'data': {
              'session_ref': currentSession,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return _json({
            'data': {
              'user_id': currentSession == sessionA ? userA : userB,
              'instance_id': instanceId,
              'audience': 'client',
              'session_ref': currentSession,
              'account_status': 'active',
              'permissions': <Object>[],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/users/me/account':
          accountGets += 1;
          if (currentSession == sessionB) return releaseB.future;
          return _json({
            'data': {
              'status': 'active',
              'email': 'a@example.test',
              'email_verified_at': null,
              'created_at': '2026-09-01T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected path ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    addTearDown(() {
      providers.dispose();
      api.close();
    });
    expect(await tester.runAsync(() => auth.login('a@example.test', 'test-password')), isTrue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: AccountIdentitySummary(
                  key: ValueKey(constraints.maxWidth >= 760),
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 50 && find.text('a@example.test').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(
      find.text('a@example.test'),
      findsOneWidget,
      reason:
          'visible=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()} gets=$accountGets',
    );
    expect(accountGets, 1);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    await tester.pump();
    expect(find.text('a@example.test'), findsOneWidget);
    expect(accountGets, 1);

    currentSession = sessionB;
    expect(await tester.runAsync(() => auth.login('b@example.test', 'test-password')), isTrue);
    await tester.pump();
    expect(find.text('a@example.test'), findsNothing);
    for (var attempt = 0; attempt < 50 && accountGets < 2; attempt++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(accountGets, 2);
    releaseB.complete(
      _json({
        'data': {
          'status': 'active',
          'email': 'b@example.test',
          'email_verified_at': null,
          'created_at': '2026-09-02T00:00:00Z',
        },
        'meta': {'request_id': requestId},
      }),
    );
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('b@example.test'), findsOneWidget);
  });

  testWidgets('identity loss closes its own password dialog and removes secret fields', (
    tester,
  ) async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final adapter = SampleAdapter((options, _) async {
      switch (options.path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'client',
              'session_ref': sessionA,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/csrf':
          return _json({
            'data': {
              'session_ref': sessionA,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return _json({
            'data': {
              'user_id': userA,
              'instance_id': instanceId,
              'audience': 'client',
              'session_ref': sessionA,
              'account_status': 'active',
              'permissions': <Object>[],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected path ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    addTearDown(() {
      providers.dispose();
      api.close();
    });
    expect(await tester.runAsync(() => auth.login('a@example.test', 'test-password')), isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => unawaited(showPasswordChangeDialog(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleAsyncFrames(tester);
    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.enterText(find.byType(TextFormField).first, 'synthetic-secret');
    await tester.runAsync(auth.logout);
    await settleAsyncFrames(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('synthetic-secret'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoking another session replaces the displayed session page', (tester) async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    var sessionsReads = 0;
    var revoked = false;
    var revokeWrites = 0;
    final requested = <String>[];
    Map<String, Object?> session(String id, {required bool current}) => {
      'id': id,
      'platform': 'web',
      'audience': 'client',
      'transport': 'web',
      'device_summary': current ? 'Current browser' : 'Other browser',
      'created_at': '2026-09-27T00:00:00Z',
      'last_seen_at': '2026-09-27T00:00:00Z',
      'absolute_expires_at': '2026-10-01T00:00:00Z',
      'revoked_at': null,
      'is_current': current,
    };
    final adapter = SampleAdapter((options, _) async {
      requested.add(options.path);
      if (options.uri.path == '/api/v1/auth/sessions') {
        sessionsReads += 1;
        return _json({
          'data': [
            session(sessionA, current: true),
            if (!revoked) session(sessionB, current: false),
          ],
          'meta': {'request_id': requestId, 'has_more': false, 'next_cursor': null},
        });
      }
      if (options.uri.path == '/api/v1/auth/sessions/$sessionB/revoke') {
        revokeWrites += 1;
        revoked = true;
        return ResponseBody.fromString('', 204);
      }
      switch (options.uri.path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'client',
              'session_ref': sessionA,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/auth/csrf':
          return _json({
            'data': {
              'session_ref': sessionA,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/me/access':
          return _json({
            'data': {
              'user_id': userA,
              'instance_id': instanceId,
              'audience': 'client',
              'session_ref': sessionA,
              'account_status': 'active',
              'permissions': <Object>[],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected path ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(showDeviceSessionsDialog(context)),
              child: const Text('open sessions'),
            ),
          ),
        ),
      ],
    );
    addTearDown(() {
      router.dispose();
      providers.dispose();
      api.close();
    });
    expect(await tester.runAsync(() => auth.login('a@example.test', 'test-password')), isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: providers,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('open sessions')));
    await settleAsyncFrames(tester);
    final revokeKey = ValueKey<String>(UiTestIds.sessionRevoke(sessionB));
    for (var i = 0; i < 50 && find.byKey(revokeKey).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(
      find.byKey(revokeKey),
      findsOneWidget,
      reason:
          'reads=$sessionsReads requests=$requested phase=${auth.phase} spinner=${find.byType(CircularProgressIndicator).evaluate().length} error=${tester.takeException()} visible=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
    );
    expect(sessionsReads, 1);
    await tester.runAsync(() => tester.tap(find.byKey(revokeKey)));
    await settleAsyncFrames(tester);
    for (var i = 0; i < 50 && sessionsReads < 2; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
    final sessionsBuilder = find.byWidgetPredicate(
      (widget) => widget is FutureBuilder<PageResponse<SessionSummary>> && widget.future != null,
    );
    expect(revoked, true);
    expect(
      sessionsBuilder,
      findsOneWidget,
      reason:
          'futureBuilders=${tester.widgetList<FutureBuilder<PageResponse<SessionSummary>>>(sessionsBuilder).map((e) => e.key).toList()}',
    );
    final sessionsFuture = tester
        .widget<FutureBuilder<PageResponse<SessionSummary>>>(sessionsBuilder)
        .future!;
    final refreshed = await tester.runAsync(
      () => sessionsFuture.timeout(const Duration(seconds: 2)),
    );
    expect(refreshed!.data.length, 1);
    await settleAsyncFrames(tester);
    for (var i = 0; i < 50 && find.textContaining('Current browser').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
    expect(revokeWrites, 1);
    expect(sessionsReads, 2);
    expect(find.textContaining('Other browser'), findsNothing);
    expect(find.byKey(revokeKey), findsNothing);
    expect(
      find.textContaining('Current browser'),
      findsOneWidget,
      reason:
          'reads=$sessionsReads requests=$requested phase=${auth.phase} spinner=${find.byType(CircularProgressIndicator).evaluate().length} error=${tester.takeException()} visible=${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
    );
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/admin/presentation/governance_overview_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

import '../../../test_support/sample_adapter.dart';

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
  const instanceId = 'haruka-test-0123456789abcdef0123456789abcdef';
  const sessionRef = '018f1234-0000-7000-8000-000000000002';
  const userId = '018f1234-0000-7000-8000-000000000011';
  const eventId = '018f1234-0000-7000-8000-0000000000ee';
  const requestId = '018f1234-0000-7000-8000-000000000099';

  testWidgets('audit detail uses the loaded row and lost rights clear the page', (tester) async {
    var auditReads = 0;
    var revoke = false;
    var policy = 1;
    final adapter = SampleAdapter((options, _) async {
      final path = options.uri.path;
      switch (path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'admin',
              'session_ref': sessionRef,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/csrf':
          return _json({
            'data': {
              'session_ref': sessionRef,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/me/access':
          return _json({
            'data': {
              'user_id': userId,
              'instance_id': instanceId,
              'audience': 'admin',
              'session_ref': sessionRef,
              'account_status': 'active',
              'permissions': [
                if (!revoke) {'code': 'admin.audit.read', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': policy},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/audit-events':
          auditReads += 1;
          return _json({
            'data': [
              {
                'event_id': eventId,
                'action': 'user.updated',
                'actor': 'admin',
                'actor_user_id': userId,
                'audience': 'admin',
                'permission_code': null,
                'target_type': 'user',
                'target_id': null,
                'target_code': 'desk',
                'result': 'committed',
                'reason_code': 'status',
                'authorization_revision': 4,
                'request_id': requestId,
                'operation_id': null,
                'change_summary': {'status': 'disabled'},
                'created_at': '2026-09-29T00:00:00Z',
              },
            ],
            'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
          });
      }
      throw StateError('Unexpected ${options.method} $path');
    });
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    addTearDown(api.close);
    expect(
      await tester.runAsync(() => auth.login('admin@demo.test', 'preview-password', admin: true)),
      isTrue,
    );
    auth.pauseAccessDeadline();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminAuditEvents(auth: auth)),
      ),
    );
    await _until(tester, find.text('user.updated'));
    expect(auditReads, 1);
    policy = 2;
    expect(await tester.runAsync(() => auth.verifyCurrentAccess()), isTrue);
    await tester.pump();
    expect(auditReads, 1);
    expect(find.text('user.updated'), findsOneWidget);
    await tester.tap(find.text('user.updated'));
    await tester.pumpAndSettle();
    expect(find.text('审计详情'), findsOneWidget);
    expect(find.text('status: disabled'), findsOneWidget);
    expect(auditReads, 1);
    revoke = true;
    expect(await tester.runAsync(() => auth.verifyCurrentAccess()), isTrue);
    await tester.pump();
    expect(find.text('当前管理会话没有此操作权限。'), findsWidgets);
    expect(find.text('status: disabled'), findsNothing);
    expect(find.text('user.updated'), findsNothing);
    expect(auditReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets('a late audit page cannot overwrite a newer result filter', (tester) async {
    final moreGate = Completer<void>();
    final adapter = SampleAdapter((options, _) async {
      final path = options.uri.path;
      switch (path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'admin',
              'session_ref': sessionRef,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/csrf':
          return _json({
            'data': {
              'session_ref': sessionRef,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/me/access':
          return _json({
            'data': {
              'user_id': userId,
              'instance_id': instanceId,
              'audience': 'admin',
              'session_ref': sessionRef,
              'account_status': 'active',
              'permissions': [
                {'code': 'admin.audit.read', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/audit-events':
          final cursor = options.uri.queryParameters['cursor'];
          final result = options.uri.queryParameters['result'];
          if (cursor != null) {
            await moreGate.future;
            return _auditPage('role.updated', eventId: '018f1234-0000-7000-8000-0000000000ef');
          }
          if (result == 'denied') {
            return _auditPage(
              'auth.login.denied',
              eventId: '018f1234-0000-7000-8000-0000000000f0',
              result: 'denied',
            );
          }
          return _auditPage(
            'user.updated',
            eventId: eventId,
            cursor: '2026-09-29T00:00:00Z|$eventId',
          );
      }
      throw StateError('Unexpected ${options.method} $path');
    });
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    addTearDown(api.close);
    expect(
      await tester.runAsync(() => auth.login('admin@demo.test', 'preview-password', admin: true)),
      isTrue,
    );
    auth.pauseAccessDeadline();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminAuditEvents(auth: auth)),
      ),
    );
    await _until(tester, find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.tap(find.text('全部结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已拒绝').last);
    await _until(tester, find.text('auth.login.denied'));
    moreGate.complete();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('auth.login.denied'), findsOneWidget);
    expect(find.text('role.updated'), findsNothing);
    expect(find.text('user.updated'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets('overview shows identity counts from one read', (tester) async {
    var summaryReads = 0;
    var policy = 1;
    final adapter = SampleAdapter((options, _) async {
      final path = options.uri.path;
      switch (path) {
        case '/api/v1/meta':
          return _json({
            'data': {'instance_id': instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/login':
          return _json({
            'data': {
              'state': 'authenticated',
              'audience': 'admin',
              'session_ref': sessionRef,
              'absolute_expires_at': '2026-10-01T00:00:00Z',
              'idle_expires_at': '2026-10-01T00:00:00Z',
              'server_time': '2026-09-28T00:00:00Z',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth/csrf':
          return _json({
            'data': {
              'session_ref': sessionRef,
              'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/me/access':
          return _json({
            'data': {
              'user_id': userId,
              'instance_id': instanceId,
              'audience': 'admin',
              'session_ref': sessionRef,
              'account_status': 'active',
              'permissions': [
                {'code': 'admin.dashboard.view', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': policy},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/governance-summary':
          summaryReads += 1;
          return _json({
            'data': {
              'accounts_active': 3,
              'accounts_pending': 1,
              'accounts_disabled': 0,
              'approvals_pending': 2,
              'roles_enabled': 5,
              'authorization_revision': 8,
              'open_manual_recoveries': 0,
            },
            'meta': {'request_id': requestId},
          });
      }
      throw StateError('Unexpected ${options.method} $path');
    });
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: instanceId,
      apiBaseUrl: 'https://localhost:18443',
    );
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    addTearDown(api.close);
    expect(
      await tester.runAsync(() => auth.login('admin@demo.test', 'preview-password', admin: true)),
      isTrue,
    );
    auth.pauseAccessDeadline();
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminGovernanceOverview(auth: auth)),
      ),
    );
    await _until(tester, find.text('3'));
    expect(find.text('待审批'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('任务、存储和模型用量仍未开放。'), findsOneWidget);
    expect(summaryReads, 1);
    policy = 2;
    expect(await tester.runAsync(() => auth.verifyCurrentAccess()), isTrue);
    await tester.pump();
    expect(summaryReads, 1);
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
}

ResponseBody _auditPage(
  String action, {
  required String eventId,
  String result = 'committed',
  String? cursor,
}) => _json({
  'data': [
    {
      'event_id': eventId,
      'action': action,
      'actor': 'admin',
      'actor_user_id': null,
      'audience': 'admin',
      'permission_code': null,
      'target_type': 'user',
      'target_id': null,
      'target_code': 'desk',
      'result': result,
      'reason_code': 'status',
      'authorization_revision': 4,
      'request_id': '018f1234-0000-7000-8000-000000000099',
      'operation_id': null,
      'change_summary': {'status': 'disabled'},
      'created_at': '2026-09-29T00:00:00Z',
    },
  ],
  'meta': {
    'request_id': '018f1234-0000-7000-8000-000000000099',
    'next_cursor': cursor,
    'has_more': cursor != null,
  },
});

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(finder, findsWidgets);
}

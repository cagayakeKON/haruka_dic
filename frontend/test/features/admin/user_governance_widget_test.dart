import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/admin/presentation/user_governance_page.dart';
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
  const accountId = '018f1234-0000-7000-8000-0000000000aa';
  const createdId = '018f1234-0000-7000-8000-0000000000bb';
  const requestId = '018f1234-0000-7000-8000-000000000099';

  testWidgets('account dialog reuses the loaded list and creates without a password', (
    tester,
  ) async {
    var accountReads = 0;
    var sessionReads = 0;
    var detailReads = 0;
    var policyRevision = 1;
    var recoveryAllowed = true;
    var recoveryReads = 0;
    var recoveryIssues = 0;
    Object? created;
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
                {'code': 'admin.login', 'data_scope': 'platform_metadata'},
                {'code': 'admin.user.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.user.create', 'data_scope': 'platform_metadata'},
                if (recoveryAllowed)
                  {'code': 'admin.user.update', 'data_scope': 'platform_metadata'},
                {'code': 'admin.session.read', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': policyRevision},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users':
          if (options.method == 'GET') {
            accountReads += 1;
            return _json({
              'data': [
                {
                  'user_id': accountId,
                  'email': 'learner-a@example.test',
                  'display_name': '学习者 A',
                  'status': 'active',
                  'email_verified': true,
                  'locked': false,
                  'approval_status': 'not_required',
                  'audiences': ['client'],
                  'roles': <Object>[],
                  'live_session_count': 0,
                  'revision': 2,
                },
              ],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          created = _body(options);
          return _json({
            'data': {
              'user_id': createdId,
              'revision': 2,
              'authorization_revision': 4,
              'audit_id': requestId,
              'affected_count': 1,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/account-ceilings':
          return _json({
            'data': {
              'assign_role_ids': <Object>[],
              'manage_account_role_ids': <Object>[],
              'manage_unassigned_accounts': false,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId/sessions':
          sessionReads += 1;
          return _json({
            'data': <Object>[],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId/recovery-requests':
          recoveryReads += 1;
          return _json({
            'data': [
              {
                'challenge_id': requestId,
                'status': 'requested',
                'created_at': '2026-09-28T00:00:00Z',
                'expires_at': '2026-10-01T00:00:00Z',
              },
            ],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId/recovery-decisions':
          recoveryIssues += 1;
          return _json({
            'data': {
              'challenge_id': requestId,
              'status': 'issued',
              'expires_at': '2026-10-01T00:00:00Z',
              'token': 'synthetic-one-time-recovery',
              'revision': 3,
              'authorization_revision': policyRevision,
              'audit_id': requestId,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$createdId':
          detailReads += 1;
          return _json({
            'data': {
              'user_id': createdId,
              'email': 'desk@example.test',
              'display_name': '服务台账号',
              'status': 'pending',
              'email_verified': false,
              'locked': false,
              'approval_status': 'not_required',
              'audiences': <Object>[],
              'roles': <Object>[],
              'live_session_count': 0,
              'revision': 2,
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
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = createRouter(config, api, auth, initialLocation: '/admin/users');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await _until(tester, find.text('学习者 A'));
    expect(accountReads, 1);
    expect(find.text('learner-a@example.test'), findsOneWidget);
    expect(find.text('用户端'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    final originalState = tester.state(find.byType(AdminUserGovernance));
    await tester.enterText(find.byType(TextField), '学习者');
    policyRevision += 1;
    expect(await tester.runAsync(auth.verifyCurrentAccess), isTrue);
    await tester.pump();
    expect(tester.state(find.byType(AdminUserGovernance)), same(originalState));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '学习者');
    expect(accountReads, 1);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pump();
    expect(find.text('没有匹配的账号'), findsOneWidget);
    expect(accountReads, 1);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.text('查看运维摘要'));
    await tester.pumpAndSettle();
    await _until(tester, find.text('运维摘要'));
    await _until(tester, find.text('核验签发'));
    expect(recoveryReads, 1);
    expect(sessionReads, 1);
    expect(accountReads, 1);
    expect(recoveryReads, 1);
    await tester.tap(find.text('核验签发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当面核验'));
    await _until(tester, find.text('synthetic-one-time-recovery'));
    expect(recoveryIssues, 1);
    recoveryAllowed = false;
    policyRevision += 1;
    expect(await tester.runAsync(auth.verifyCurrentAccess), isTrue);
    await tester.pump();
    expect(find.text('synthetic-one-time-recovery'), findsNothing);
    expect(find.text('核验签发'), findsNothing);
    // Both the token dialog and its account owner are closed to the old scope.
    await tester.tap(find.text('关闭').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('关闭'));
    await _until(tester, find.text('学习者 A'));
    await tester.tap(find.text('查看运维摘要'));
    await tester.pumpAndSettle();
    expect(sessionReads, 2);
    expect(accountReads, 2);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'desk@example.test');
    await tester.enterText(find.byType(TextField).at(2), '服务台');
    await tester.tap(find.widgetWithText(FilledButton, '创建账号').last);
    for (var attempt = 0; attempt < 12 && created == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(created, {'email': 'desk@example.test', 'display_name': '服务台', 'role_ids': <Object>[]});
    await _until(tester, find.text('服务台账号'));
    expect(detailReads, 1);
    expect(accountReads, 2);
    expect(find.text('学习者 A'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets('disable marks cached sessions and a conflict reloads before resubmit', (
    tester,
  ) async {
    const roleId = '018f1234-0000-7000-8000-0000000000cc';
    const sessionId = '018f1234-0000-7000-8000-0000000000dd';
    var accountReads = 0;
    var sessionReads = 0;
    var detailReads = 0;
    var rolePosts = 0;
    final roleBodies = <Object?>[];
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
                {'code': 'admin.user.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.user.disable', 'data_scope': 'platform_metadata'},
                {'code': 'admin.user.role.assign', 'data_scope': 'platform_metadata'},
                {'code': 'admin.role.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.session.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.session.revoke', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users':
          accountReads += 1;
          return _json({
            'data': [
              {
                'user_id': accountId,
                'email': 'learner-a@example.test',
                'display_name': '学习者 A',
                'status': 'active',
                'email_verified': true,
                'locked': false,
                'approval_status': 'not_required',
                'audiences': ['client'],
                'roles': <Object>[],
                'live_session_count': 1,
                'revision': 2,
              },
            ],
            'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
          });
        case '/api/v1/admin/account-ceilings':
          return _json({
            'data': {
              'assign_role_ids': [roleId],
              'manage_account_role_ids': <Object>[],
              'manage_unassigned_accounts': true,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/roles':
          return _json({
            'data': [
              {
                'id': roleId,
                'code': 'desk',
                'name': '服务台',
                'description': null,
                'protected': false,
                'enabled': true,
                'revision': 1,
                'grants': <Object>[],
                'parents': <Object>[],
                'member_count': 0,
              },
            ],
            'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
          });
        case '/api/v1/admin/users/$accountId/sessions':
          sessionReads += 1;
          return _json({
            'data': [
              {
                'session_id': sessionId,
                'audience': 'client',
                'transport': 'web',
                'platform': 'web',
                'device_summary': 'web',
                'created_at': '2026-09-28T00:00:00Z',
                'last_seen_at': '2026-09-28T00:00:00Z',
                'absolute_expires_at': '2026-10-01T00:00:00Z',
                'revoked_at': null,
              },
            ],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId/status':
          return _json({
            'data': {
              'user_id': accountId,
              'revision': 3,
              'authorization_revision': 4,
              'audit_id': requestId,
              'affected_count': 1,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId':
          detailReads += 1;
          final saved = rolePosts > 1;
          return _json({
            'data': {
              'user_id': accountId,
              'email': 'learner-a@example.test',
              'display_name': '学习者 A',
              'status': 'disabled',
              'email_verified': true,
              'locked': false,
              'approval_status': 'not_required',
              'audiences': <Object>[],
              'roles': saved
                  ? [
                      {
                        'role_id': roleId,
                        'code': 'desk',
                        'name': '服务台',
                        'enabled': true,
                        'protected': false,
                      },
                    ]
                  : <Object>[],
              'live_session_count': 0,
              'revision': detailReads == 1
                  ? 3
                  : saved
                  ? 10
                  : 9,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/users/$accountId/roles':
          rolePosts += 1;
          roleBodies.add(_body(options));
          if (rolePosts == 1) {
            return ResponseBody.fromString(
              jsonEncode({
                'error': {
                  'code': 'REVISION_CONFLICT',
                  'details': {'kind': 'revision_conflict', 'current_revision': 9},
                },
                'meta': {'request_id': requestId},
              }),
              409,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          return _json({
            'data': {
              'user_id': accountId,
              'revision': 10,
              'authorization_revision': 5,
              'audit_id': requestId,
              'affected_count': 1,
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
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminUserGovernance(auth: auth)),
      ),
    );
    await _until(tester, find.text('学习者 A'));
    expect(accountReads, 1);
    await tester.tap(find.text('查看运维摘要'));
    await tester.pumpAndSettle();
    await _until(tester, find.text('撤销'));
    expect(sessionReads, 1);

    await tester.tap(find.text('停用'));
    await _until(tester, find.textContaining('已停用'));
    expect(detailReads, 1);
    expect(sessionReads, 1);
    expect(find.text('撤销'), findsNothing);
    expect(accountReads, 1);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('已停用'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);
    expect(accountReads, 1);

    await tester.tap(find.text('查看运维摘要'));
    await tester.pumpAndSettle();
    expect(sessionReads, 1);
    await tester.tap(find.text('服务台'));
    await tester.pump();
    await tester.tap(find.text('保存角色'));
    await _until(tester, find.text('重新加载'));
    expect(rolePosts, 1);
    expect(roleBodies.single, {
      'expected_revision': 3,
      'role_ids': [roleId],
    });
    await tester.tap(find.text('重新加载'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(detailReads, 2);
    expect(rolePosts, 1);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);

    await tester.tap(find.text('服务台'));
    await tester.pump();
    await tester.tap(find.text('保存角色'));
    for (var attempt = 0; attempt < 12 && rolePosts < 2; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(rolePosts, 2);
    expect(roleBodies[1], {
      'expected_revision': 9,
      'role_ids': [roleId],
    });
    expect(accountReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
}

Object? _body(RequestOptions options) {
  final data = options.data;
  if (data is String) return jsonDecode(data);
  return data;
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(
    finder,
    findsWidgets,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((item) => item.data)
        .whereType<String>()
        .join(' | '),
  );
}

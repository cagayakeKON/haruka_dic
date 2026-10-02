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
import 'package:haruka/features/admin/presentation/role_governance_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

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
  const instanceId = 'haruka-test-0123456789abcdef0123456789abcdef';
  const sessionRef = '018f1234-0000-7000-8000-000000000002';
  const userId = '018f1234-0000-7000-8000-000000000011';
  const roleId = '018f1234-0000-7000-8000-0000000000aa';
  const createdId = '018f1234-0000-7000-8000-0000000000bb';
  const requestId = '018f1234-0000-7000-8000-000000000099';

  testWidgets('role dialog reuses the loaded list and creates an empty role', (tester) async {
    var roleReads = 0;
    var boundaryReads = 0;
    Object? created;
    Object? renamed;
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
                {'code': 'admin.role.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.role.create', 'data_scope': 'platform_metadata'},
                {'code': 'admin.role.update', 'data_scope': 'platform_metadata'},
                {'code': 'admin.permission.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.grant_boundary.read', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/roles':
          if (options.method == 'GET') {
            roleReads += 1;
            return _json({
              'data': [
                {
                  'id': roleId,
                  'code': 'learner',
                  'name': '学习者',
                  'description': null,
                  'protected': false,
                  'enabled': true,
                  'revision': 2,
                  'grants': [
                    {
                      'permission_code': 'client.library.read',
                      'effect': 'allow',
                      'data_scope': 'self',
                    },
                  ],
                  'parents': <Object>[],
                  'member_count': 3,
                },
              ],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          created = _body(options);
          return _json({
            'data': {
              'role_id': createdId,
              'revision': 2,
              'authorization_revision': 4,
              'audit_id': requestId,
              'affected_count': 0,
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/permissions':
          return _json({
            'data': [
              {
                'code': 'client.library.read',
                'audience': 'client',
                'data_scope': 'self',
                'enabled': true,
              },
            ],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/roles/$roleId/grant-boundaries':
          boundaryReads += 1;
          return _json({
            'data': [
              {
                'boundary_kind': 'assign_role',
                'target_role_id': roleId,
                'permission_code': null,
                'data_scope': null,
                'revision': 1,
              },
            ],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/roles/$roleId':
          renamed = _body(options);
          return _json({
            'data': {
              'role_id': roleId,
              'revision': 3,
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

    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AdminRoleGovernance(auth: auth)),
      ),
    );
    await _until(tester, find.text('学习者'));
    expect(roleReads, 1);
    expect(find.text('用户端'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);

    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    await _until(tester, find.text('可分配角色'));
    expect(roleReads, 1);
    expect(boundaryReads, 1);
    expect(find.text('运维摘要'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    await _until(tester, find.text('可分配角色'));
    expect(boundaryReads, 1);
    expect(roleReads, 1);

    await tester.enterText(find.byType(TextField).first, '学习者甲');
    await tester.tap(find.text('保存名称'));
    await tester.pump();
    await _until(tester, find.text('受影响账号 1'));
    expect(roleReads, 1);
    expect(renamed, {'expected_revision': 2, 'name': '学习者甲', 'description': null});

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('学习者甲'), findsOneWidget);
    expect(roleReads, 1);

    await tester.tap(find.text('创建角色'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'desk');
    await tester.enterText(find.byType(TextField).at(1), '服务台');
    await tester.tap(find.widgetWithText(FilledButton, '创建角色').last);
    for (var attempt = 0; attempt < 12 && created == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(roleReads, 1);
    expect(
      created,
      {'code': 'desk', 'name': '服务台', 'description': null},
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((item) => item.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('学习者甲'), findsOneWidget);
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

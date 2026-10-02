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
import 'package:haruka/features/admin/presentation/menu_governance_page.dart';
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
  const menuId = '018f1234-0000-7000-8000-0000000000aa';
  const requestId = '018f1234-0000-7000-8000-000000000099';

  testWidgets('menu dialog reuses the loaded list and hides without a new route', (tester) async {
    var menuReads = 0;
    Object? layout;
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
                {'code': 'admin.menu.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.menu.update', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': [
                {'key': 'library', 'route_key': '/reference/materials', 'title': '书库'},
              ],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/menus':
          menuReads += 1;
          return _json({
            'data': [
              {
                'id': menuId,
                'code': 'library',
                'audience': 'client',
                'route_key': '/reference/materials',
                'component_key': 'client.library',
                'parent_menu_id': null,
                'title': '书库',
                'icon_key': 'library',
                'sort_order': 10,
                'permission_match': 'all',
                'enabled': true,
                'floor': ['client.material.list'],
                'permission_codes': <Object>[],
                'revision': 1,
              },
            ],
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/menu-catalog':
          return _json({
            'data': {
              'pages': <Object>[],
              'icons': <Object>['library'],
              'permission_codes': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/menus/layout':
          expect(options.headers['Idempotency-Key'], options.headers['X-Operation-ID']);
          expect(options.headers['Idempotency-Key'], isNotEmpty);
          layout = _body(options);
          return _json({
            'data': {
              'authorization_revision': 4,
              'audit_id': requestId,
              'affected_count': 1,
              'menus': [
                {
                  'id': menuId,
                  'code': 'library',
                  'audience': 'client',
                  'route_key': '/reference/materials',
                  'component_key': 'client.library',
                  'parent_menu_id': null,
                  'title': '书库',
                  'icon_key': 'library',
                  'sort_order': 10,
                  'permission_match': 'all',
                  'enabled': false,
                  'floor': ['client.material.list'],
                  'permission_codes': <Object>[],
                  'revision': 2,
                },
              ],
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
        home: Scaffold(body: AdminMenuGovernance(auth: auth)),
      ),
    );
    await _until(tester, find.text('书库'));
    expect(menuReads, 1);
    expect(find.text('用户端导航'), findsOneWidget);
    expect(find.text('授权后显示'), findsOneWidget);

    await tester.tap(find.text('书库'));
    await tester.pumpAndSettle();
    await _until(tester, find.text('隐藏菜单'));
    expect(menuReads, 1);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书库'));
    await tester.pumpAndSettle();
    expect(menuReads, 1);

    await tester.enterText(find.byType(TextField).at(0), '材料入口');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('保存'));
    for (var attempt = 0; attempt < 12 && layout == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final body = layout! as Map<String, Object?>;
    final items = body['items']! as List<Object?>;
    final item = items.single! as Map<String, Object?>;
    expect(item['enabled'], isFalse);
    expect(item['title'], '材料入口');
    expect(item['sort_order'], 5);
    expect(item.containsKey('route_key'), isFalse);
    expect(item.containsKey('password'), isFalse);
    await _until(tester, find.text('已隐藏'));
    expect(menuReads, 1);
    expect(find.text('书库'), findsWidgets);
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
  expect(finder, findsWidgets);
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/auth/account_pages.dart';
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
  const requestId = '018f1234-0000-7000-8000-000000000099';

  testWidgets('policy preview reuses the loaded revision and applies approval', (tester) async {
    var policyReads = 0;
    Object? update;
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
                {'code': 'admin.auth_policy.read', 'data_scope': 'platform_metadata'},
                {'code': 'admin.auth_policy.update', 'data_scope': 'platform_metadata'},
              ],
              'authz_version': {'user': 1, 'policy': 1},
              'navigation': <Object>[],
              'feature_flags': <Object>[],
            },
            'meta': {'request_id': requestId},
          });
        case '/api/v1/admin/auth-policy':
          if (options.method == 'GET') policyReads += 1;
          if (options.method == 'PATCH') update = _body(options);
          final mode = update == null ? 'closed' : 'approval';
          return _json({
            'data': {
              'registration_mode': mode,
              'registration_enabled': mode != 'closed',
              'email_verification_required': true,
              'recovery_mode': 'email',
              'revision': update == null ? 1 : 2,
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
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => auth)],
        child: MaterialApp(
          theme: HarukaTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminPolicyEditor()),
        ),
      ),
    );
    await _until(tester, find.text('关闭新注册'));
    expect(policyReads, 1);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('需审批').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览策略变化'));
    await tester.pumpAndSettle();
    expect(policyReads, 1);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(policyReads, 1);
    await tester.tap(find.text('预览策略变化'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用策略'));
    for (var attempt = 0; attempt < 12 && update == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final body = update! as Map<String, Object?>;
    expect(body['registration_mode'], 'approval');
    expect(body['expected_revision'], 1);
    expect(body.containsKey('recovery_mode'), isFalse);
    await _until(tester, find.text('当前策略'));
    expect(policyReads, 1);
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

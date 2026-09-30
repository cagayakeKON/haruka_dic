import 'dart:convert';
import 'dart:io';

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
import 'package:haruka/features/admin/presentation/model_operations_page.dart';

import '../test_support/sample_adapter.dart';

final class _NoVault implements CredentialVault {
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

ResponseBody _json(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  final samples = jsonDecode(
    File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final config = AppConfig.parse(
    platform: AppPlatform.web,
    environment: 'dev',
    instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
    apiBaseUrl: 'https://localhost:18443',
  );

  for (final section in ['models', 'jobs']) {
    testWidgets(
      section == 'models'
          ? 'catalog confirmation consumes complete backend PATCH projection without reloading'
          : 'admin safe retry serializes JobCancel only and consumes backend safe-stage response',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final mutations = <Map<String, dynamic>>[];
        final paths = <String>[];
        var businessReads = 0;
        final access = jsonDecode(jsonEncode(samples['auth_admin_access'])) as Map<String, dynamic>;
        (access['data'] as Map<String, dynamic>)['permissions'] = [
          for (final code in [
            'admin.model_catalog.read',
            'admin.model_catalog.update',
            'admin.job.read',
            'admin.job.retry',
          ])
            {'code': code, 'data_scope': 'platform_metadata'},
        ];
        final adapter = SampleAdapter((options, stream) async {
          final path = options.uri.path;
          paths.add('${options.method} $path');
          switch (path) {
            case '/api/v1/meta':
              return _json({
                'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
                'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
              });
            case '/api/v1/admin/auth/login':
              return _json(samples['auth_web_authenticated'] as Object);
            case '/api/v1/admin/auth/csrf':
              return _json({
                'data': {
                  'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                  'session_ref': '018f1234-0000-7000-8000-000000000002',
                },
                'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
              });
            case '/api/v1/admin/me/access':
              return _json(access);
            case '/api/v1/admin/model-catalog':
              businessReads++;
              final baseline = jsonDecode(
                jsonEncode(samples['admin_model_catalog_patch']),
              ) as Map<String, dynamic>;
              final data = baseline['data'] as Map<String, dynamic>;
              data['revision'] = 1;
              for (final rawModel in data['models'] as List) {
                final model = rawModel as Map<String, dynamic>;
                model['enabled'] = true;
                model['revision'] = 1;
              }
              return _json(baseline);
            case '/api/v1/admin/jobs':
              businessReads++;
              return _json(samples['admin_model_jobs_blocked'] as Object);
          }
          if ((options.method == 'PATCH' && path.startsWith('/api/v1/admin/model-catalog/')) ||
              (options.method == 'POST' &&
                  path.startsWith('/api/v1/admin/jobs/') &&
                  path.endsWith('/retry'))) {
            expect(options.headers['X-CSRF-Token'], isNotEmpty);
            expect(options.headers['Idempotency-Key'], isNotEmpty);
            if (stream == null) throw StateError('Mutation JSON stream missing');
            final chunks = await stream.toList();
            mutations.add(
              jsonDecode(utf8.decode([for (final chunk in chunks) ...chunk]))
                  as Map<String, dynamic>,
            );
            return _json(
              samples[section == 'models'
                      ? 'admin_model_catalog_patch'
                      : 'admin_model_retry_response']
                  as Object,
            );
          }
          throw StateError('Unexpected transport route ${options.method} $path');
        });
        final api = ApiClient(config, adapter: adapter);
        final auth = AuthController(
          AuthRepository(api, config),
          config,
          vault: _NoVault(),
          sync: _NoSync(),
        );
        addTearDown(api.close);
        expect(
          await tester.runAsync(
            () => auth.login('fixture@example.test', 'fixture-only-password', admin: true),
          ),
          true,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: HarukaTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminModelOperations(auth: auth, section: section),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(businessReads, 1);
        if (section == 'models') {
          expect(tester.widget<Switch>(find.byType(Switch)).value, true);
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          expect(mutations, isEmpty);
          expect(businessReads, 1);
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '提交变更'));
          await tester.pumpAndSettle();
          expect(mutations, [
            {'expected_revision': 1, 'enabled': false},
          ]);
          expect(tester.widget<Switch>(find.byType(Switch)).value, false);
          // Cancelling another confirmation preserves the updated directory without reads.
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, '取消'));
          await tester.pumpAndSettle();
          expect(mutations, hasLength(1));
        } else {
          await tester.tap(find.text('查看摘要').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('恢复安全阶段'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '确认'));
          await tester.pumpAndSettle();
          expect(mutations.single, samples['admin_model_retry_request']);
          expect(mutations.single.keys, ['expected_revision']);
          expect(find.text('已受理'), findsOneWidget);
          await tester.tap(find.text('查看摘要').first);
          await tester.pumpAndSettle();
          expect(find.text('恢复安全阶段'), findsNothing);
          await tester.tap(find.widgetWithText(TextButton, '关闭'));
          await tester.pumpAndSettle();
        }
        expect(businessReads, 1);
        expect(find.textContaining('INVALID_RESPONSE'), findsNothing);
        expect(
          paths.where((path) => path.contains('/provider-credentials/') || path.endsWith('/test')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
      },
    );
  }
}

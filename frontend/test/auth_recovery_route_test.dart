import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import 'support/sample_adapter.dart';

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
  testWidgets('direct recovery route says closed when policy disables recovery', (tester) async {
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'https://localhost:18443',
    );
    const requestId = '018f1234-1234-7123-8123-123456789abc';
    ResponseBody jsonBody(Object value, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final api = ApiClient(
      config,
      adapter: SampleAdapter((options, _) async {
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
                'recovery_enabled': false,
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
              'error': {
                'code': 'AUTH_REQUIRED',
                'message': 'required',
                'field_errors': <Object?>[],
              },
              'meta': {'request_id': requestId},
            }, 401);
        }
        throw StateError('Unexpected endpoint ${options.path}');
      }),
    );
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _EmptyVault(),
      sync: _NoSync(),
    );
    final providers = ProviderContainer(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
    );
    final router = createRouter(config, api, auth, initialLocation: '/recovery');
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
    for (var attempt = 0; attempt < 40 && find.text('当前未开放找回').evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    }
    expect(auth.policy?.recoveryEnabled, isFalse);
    expect(find.text('当前未开放找回'), findsOneWidget);
    expect(find.text('账号服务暂不可用。请检查连接后重试。'), findsNothing);
    expect(find.byKey(const ValueKey<String>(UiTestIds.recoveryRequestPage)), findsOneWidget);
  });
}

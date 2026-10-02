import 'dart:convert';

import 'support/generated/api_compatibility_samples.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/config/app_config.dart';

import 'support/sample_adapter.dart';

void main() {
  final samples = wireObject(jsonDecode(apiCompatibilitySamplesJson));

  test('activation uses the opaque Bearer continuation without a session', () async {
    const token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');
    final api = ApiClient(
      config,
      adapter: SampleAdapter((options, _) async {
        expect(options.uri.path, '/api/v1/auth/activation/status');
        expect(options.headers['Authorization'], 'Bearer $token');
        return ResponseBody.fromString(
          jsonEncode({
            'data': {
              'state': 'pending_approval',
              'action_required': null,
              'expires_at': '2026-10-01T00:00:00Z',
            },
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }),
    );
    addTearDown(api.close);
    expect((await AuthRepository(api, config).activationStatus(token)).state, 'pending_approval');
  });

  test('Python login variants preserve active and restricted pending state', () {
    for (final (key, decode) in [
      ('auth_web_authenticated', LoginResult.web),
      ('auth_native_authenticated', LoginResult.native),
      ('auth_web_action_required', LoginResult.web),
      ('auth_native_action_required', LoginResult.native),
    ]) {
      final login = SuccessResponse<LoginResult>.fromJson(samples[key], decode).data;
      if (key.endsWith('action_required')) {
        expect(login.pending, isTrue);
        expect(login.continuationToken, isNotEmpty);
        expect(login.continuationExpiresAt?.isUtc, isTrue);
        expect(login.sessionRef, isNull);
        expect(login.accessToken, isNull);
      } else {
        expect(login.pending, isFalse);
        expect(login.sessionRef, isNotNull);
        expect(login.continuationToken, isNull);
        if (key.contains('native')) {
          expect(login.generation, greaterThan(0));
          expect(login.refreshToken, isNotEmpty);
        } else {
          expect(login.refreshToken, isNull);
        }
      }
    }
  });

  test('access retains versions, scopes and navigation without role assumptions', () {
    final client = SuccessResponse<AccessRead>.fromJson(
      samples['auth_client_access_login_only'],
      AccessRead.fromJson,
    ).data;
    expect(client.audience, 'client');
    expect(client.navigation, isEmpty);
    expect(client.authzVersion.user, greaterThan(0));
    expect(client.authzVersion.policy, greaterThan(0));
    expect(client.permissions.every((grant) => grant.dataScope.isNotEmpty), isTrue);
    final admin = SuccessResponse<AccessRead>.fromJson(
      samples['auth_admin_access'],
      AccessRead.fromJson,
    ).data;
    expect(admin.audience, 'admin');
    expect(admin.permissions, isNotEmpty);
    expect(admin.navigation.every((item) => item.routeKey.isNotEmpty), isTrue);
  });

  test('navigation customization consumes Python flags and old fields remain compatible', () {
    final custom = SuccessResponse<AccessRead>.fromJson(
      samples['auth_admin_access_custom_navigation'],
      AccessRead.fromJson,
    ).data.navigation.single;
    expect(custom.title, '账号治理');
    expect(custom.iconKey, 'book');
    expect(custom.titleCustomized, isTrue);
    expect(custom.iconCustomized, isTrue);
    final legacy = NavigationItem.fromJson({
      'key': 'users',
      'route_key': 'users',
      'title': '用户与会话',
    });
    expect(legacy.iconKey, isNull);
    expect(legacy.titleCustomized, isFalse);
    expect(legacy.iconCustomized, isFalse);
  });

  test('account nullable verification, session fields and 202/204 transport', () {
    final account = SuccessResponse<AccountRead>.fromJson(
      samples['auth_account_legacy_unverified'],
      AccountRead.fromJson,
    ).data;
    expect(account.emailVerifiedAt, isNull);
    final page = PageResponse<SessionSummary>.fromJson(
      samples['auth_sessions_page'],
      SessionSummary.fromJson,
    );
    expect(page.data, isNotEmpty);
    for (final session in page.data) {
      expect(session.absoluteExpiresAt.isUtc, isTrue);
      expect(session.createdAt.isUtc, isTrue);
      expect(session.audience, anyOf('client', 'admin'));
      expect(session.transport, anyOf('web', 'native'));
    }
    final accepted = wireObject(samples['auth_mail_accepted']);
    expect(accepted['status'], 202);
    expect(
      SuccessResponse<MailReceipt>.fromJson(
        accepted['response'],
        MailReceipt.fromJson,
      ).data.nextStep,
      'check_email',
    );
    final empty = wireObject(samples['auth_verified_empty']);
    expect(empty['status'], 204);
    expect(empty['body'], '');
  });
}

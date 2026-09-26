import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';

void main() {
  final samples = wireObject(
    jsonDecode(File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync()),
  );

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

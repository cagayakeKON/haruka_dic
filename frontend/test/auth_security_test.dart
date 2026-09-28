import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/auth/credential_vault_native.dart';
import 'package:haruka/core/auth/email_action_link.dart';

final class _FileSecretStore implements SecretStore {
  _FileSecretStore(this.directory);

  final Directory directory;

  File _file(String key) => File('${directory.path}${Platform.pathSeparator}$key');

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) => _file(key).writeAsString(value);

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) await file.delete();
  }
}

void main() {
  test('refresh secrets are isolated by endpoint even with the same instance id', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-vault-scope-');
    try {
      final store = _FileSecretStore(directory);
      const instanceId = 'haruka-test-0123456789abcdef0123456789abcdef';
      final first = PlatformCredentialVault(
        Uri.parse('https://first.example'),
        instanceId,
        'client',
        store: store,
        lockDirectory: directory,
      );
      final second = PlatformCredentialVault(
        Uri.parse('https://second.example'),
        instanceId,
        'client',
        store: store,
        lockDirectory: directory,
      );
      const credential = RefreshCredential(
        sessionRef: 'first',
        generation: 1,
        secret: 'first-secret',
      );
      expect(await first.replace(null, credential), isTrue);
      expect(await second.read(), isNull);
      expect(
        await second.replace(
          null,
          const RefreshCredential(sessionRef: 'second', generation: 1, secret: 'second-secret'),
        ),
        isTrue,
      );
      expect((await first.read())?.secret, 'first-secret');
      expect((await second.read())?.secret, 'second-secret');
      await store.write(
        'haruka.$instanceId.client.refresh',
        '{"session_ref":"legacy","generation":1,"secret":"legacy-secret"}',
      );
      expect((await first.read())?.secret, 'first-secret');
      expect(await store.read('haruka.$instanceId.client.refresh'), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'two vault objects share an OS lock; stale refresh cannot replace a newer generation',
    () async {
      final directory = await Directory.systemTemp.createTemp('haruka-vault-');
      try {
        final store = _FileSecretStore(directory);
        final first = PlatformCredentialVault(
          Uri.parse('https://first.example'),
          'haruka-test-0123456789abcdef0123456789abcdef',
          'client',
          store: store,
          lockDirectory: directory,
        );
        final second = PlatformCredentialVault(
          Uri.parse('https://first.example'),
          'haruka-test-0123456789abcdef0123456789abcdef',
          'client',
          store: store,
          lockDirectory: directory,
        );
        const initial = RefreshCredential(sessionRef: 'first', generation: 1, secret: 'old');
        const newer = RefreshCredential(sessionRef: 'first', generation: 2, secret: 'new');
        const late = RefreshCredential(sessionRef: 'first', generation: 2, secret: 'late');
        expect(await first.replace(null, initial), isTrue);
        final results = await Future.wait([
          first.replace(initial, newer),
          second.replace(initial, late),
        ]);
        expect(results.where((result) => result), hasLength(1));
        final current = await first.read();
        expect(current?.generation, 2);
        expect(current?.secret, anyOf('new', 'late'));
        await second.clear(sessionRef: 'first');
        expect(await first.replace(initial, newer), isFalse);
        expect(await first.read(), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('same-key queue persists one refresh request ID across competing owners', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-vault-pending-');
    try {
      final store = _FileSecretStore(directory);
      final first = PlatformCredentialVault(
        Uri.parse('https://first.example'),
        'haruka-test-0123456789abcdef0123456789abcdef',
        'client',
        store: store,
        lockDirectory: directory,
      );
      final second = PlatformCredentialVault(
        Uri.parse('https://first.example'),
        'haruka-test-0123456789abcdef0123456789abcdef',
        'client',
        store: store,
        lockDirectory: directory,
      );
      const initial = RefreshCredential(sessionRef: 'first', generation: 1, secret: 'old');
      expect(await first.replace(null, initial), isTrue);
      final at = DateTime.utc(2026, 9, 26);
      final pendingA = RefreshCredential(
        sessionRef: 'first',
        generation: 1,
        secret: 'old',
        pendingRequestId: 'request-a',
        pendingAt: at,
      );
      final pendingB = RefreshCredential(
        sessionRef: 'first',
        generation: 1,
        secret: 'old',
        pendingRequestId: 'request-b',
        pendingAt: at,
      );
      final selected = await Future.wait([
        first.replace(initial, pendingA),
        second.replace(initial, pendingB),
      ]);
      expect(selected.where((success) => success), hasLength(1));
      final stored = await second.read();
      expect(stored?.pendingRequestId, anyOf('request-a', 'request-b'));
      expect(stored?.pendingAt, at);
      expect(
        await first.replace(
          initial,
          const RefreshCredential(sessionRef: 'first', generation: 2, secret: 'late'),
        ),
        isFalse,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('email action links reject wrong origin, purpose and malformed fragments', () {
    const token = 'A1234567890123456789012345678901234567890_-';
    expect(token.length, 43);
    final base = Uri.parse('https://localhost:18443');
    expect(
      tokenFromPastedActionLink(
        pasted: 'https://localhost:18443/verify-email#token=$token',
        trustedBase: base,
        actionPath: '/verify-email',
      ),
      token,
    );
    for (final url in [
      'https://evil.example/verify-email#token=$token',
      'https://localhost:18443/reset-password#token=$token',
      'https://localhost:18443/verify-email#token=$token&token=$token',
      'https://localhost:18443/verify-email#token=%GG',
      'https://localhost:18443/verify-email#token=short',
      'https://localhost:18443/verify-email?token=$token',
    ]) {
      expect(
        tokenFromPastedActionLink(pasted: url, trustedBase: base, actionPath: '/verify-email'),
        isNull,
      );
    }
    expect(validatedEmailActionFragment('token=$token&token=$token'), isNull);
    expect(validatedEmailActionFragment('token=%GG'), isNull);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'credential_vault.dart';

final class PlatformCredentialVault implements CredentialVault {
  PlatformCredentialVault(
    String instanceId,
    String audience, {
    SecretStore? store,
    Directory? lockDirectory,
  }) : assert(RegExp(r'^[a-z0-9-]+$').hasMatch(instanceId)),
       assert(audience == 'client' || audience == 'admin'),
       _key = 'haruka.$instanceId.$audience.refresh',
       _lockName = '$instanceId.$audience.lock',
       _store = store ?? _PluginSecretStore(),
       // Keep the public injection name stable for native concurrency tests.
       // ignore: prefer_initializing_formals
       _lockDirectory = lockDirectory {
    // Authentication storage belongs to the root UI isolate. File locks are
    // advisory per process on Linux/Android and cannot serialize child isolates.
    if (RootIsolateToken.instance == null) {
      throw StateError('Authentication vault must run on the root isolate');
    }
  }

  final String _key;
  final String _lockName;
  final SecretStore _store;
  final Directory? _lockDirectory;
  static final Map<String, Future<void>> _queues = {};

  /// An OS file lock serializes every read/write across vault objects and
  /// Windows processes. The secure-storage plugin itself offers no CAS API.
  Future<T> _withLock<T>(Future<T> Function() action) async {
    final previous = _queues[_key] ?? Future<void>.value();
    final completion = Completer<void>();
    _queues[_key] = completion.future;
    await previous;
    try {
      return await _withProcessLock(action);
    } finally {
      completion.complete();
      if (identical(_queues[_key], completion.future)) {
        unawaited(_queues.remove(_key));
      }
    }
  }

  Future<T> _withProcessLock<T>(Future<T> Function() action) async {
    final base = _lockDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}haruka-auth-locks');
    await directory.create(recursive: true);
    final lockFile = File('${directory.path}${Platform.pathSeparator}$_lockName');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final handle = await lockFile.open(mode: FileMode.append);
      var locked = false;
      try {
        try {
          await handle.lock(FileLock.exclusive);
          locked = true;
        } on FileSystemException {
          if (DateTime.now().isAfter(deadline)) rethrow;
        }
        if (locked) return await action();
      } finally {
        if (locked) await handle.unlock();
        await handle.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<RefreshCredential?> _readNow() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) throw const FormatException();
      final sessionRef = json['session_ref'];
      final generation = json['generation'];
      final secret = json['secret'];
      final requestId = json['pending_request_id'];
      final pendingAtText = json['pending_at'];
      final pendingAt = pendingAtText is String ? DateTime.tryParse(pendingAtText) : null;
      if (sessionRef is! String ||
          sessionRef.isEmpty ||
          generation is! int ||
          generation < 0 ||
          secret is! String ||
          secret.isEmpty ||
          (requestId != null && (requestId is! String || requestId.isEmpty)) ||
          (pendingAtText != null && (pendingAt == null || !pendingAt.isUtc)) ||
          ((requestId == null) != (pendingAtText == null))) {
        throw const FormatException();
      }
      return RefreshCredential(
        sessionRef: sessionRef,
        generation: generation,
        secret: secret,
        pendingRequestId: requestId as String?,
        pendingAt: pendingAt,
      );
    } on FormatException {
      await _store.delete(_key);
      return null;
    }
  }

  @override
  Future<RefreshCredential?> read() => _withLock(_readNow);

  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) => _withLock(() async {
    final current = await _readNow();
    if (prior == null ? current != null : current == null || !prior.sameVersion(current)) {
      return false;
    }
    await _store.write(
      _key,
      jsonEncode({
        'session_ref': next.sessionRef,
        'generation': next.generation,
        'secret': next.secret,
        'pending_request_id': next.pendingRequestId,
        'pending_at': next.pendingAt?.toIso8601String(),
      }),
    );
    return true;
  });

  @override
  Future<void> clear({String? sessionRef}) => _withLock(() async {
    if (sessionRef != null && (await _readNow())?.sessionRef != sessionRef) return;
    await _store.delete(_key);
  });
}

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class _PluginSecretStore implements SecretStore {
  const _PluginSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

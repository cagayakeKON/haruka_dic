import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final class _Remote implements CacheRemote<Map<String, Object?>> {
  final pending = Completer<CachePayload<Map<String, Object?>>>();
  int fetches = 0;
  @override
  Future<CachePayload<Map<String, Object?>>> fetch(CacheResource resource, CancelToken cancel) {
    fetches++;
    return pending.future;
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async => CacheValidation(state: ValidationState.same, version: known);
}

final class _ControlledRemote implements CacheRemote<Map<String, Object?>> {
  _ControlledRemote({required this.fetchResult, this.validation});
  final Future<CachePayload<Map<String, Object?>>> Function(CancelToken) fetchResult;
  final Future<CacheValidation> Function(CacheVersion)? validation;
  int fetches = 0;
  int validations = 0;
  final cancelTokens = <CancelToken>[];

  @override
  Future<CachePayload<Map<String, Object?>>> fetch(CacheResource resource, CancelToken cancel) {
    fetches++;
    cancelTokens.add(cancel);
    return fetchResult(cancel);
  }

  @override
  Future<CacheValidation> validate(CacheResource resource, CacheVersion known, CancelToken cancel) {
    validations++;
    cancelTokens.add(cancel);
    return validation?.call(known) ??
        Future.value(CacheValidation(state: ValidationState.same, version: known));
  }
}

final class _PauseCommittedStorageSnapshot extends QueryInterceptor {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool armed = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed && statement.contains('FROM cache_control c LEFT JOIN cache_invalidations i')) {
      armed = false;
      reached.complete();
      await release.future;
    }
    return rows;
  }
}

final class _PausePendingDeletionRead extends QueryInterceptor {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool armed = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed && statement.contains("SELECT blob_ref FROM local_assets WHERE state = 'deleting'")) {
      armed = false;
      reached.complete();
      await release.future;
    }
    return rows;
  }
}

void main() {
  final version = CacheVersion(resource: '1', representation: 'novel-v1', artifact: 'text-1');
  final resource = CacheResource(
    kind: 'material_content',
    id: 'chapter-1',
    projection: 'novel-reading-v1',
    action: 'material.read',
    sourceBinding: 'material-1:revision-1:chapter-1',
  );
  CacheCoordinator coordinator({
    void Function(String, Map<String, Object?>)? onEvent,
    bool rejectBrokenPayload = false,
    QueryInterceptor? interceptor,
  }) {
    final cache = CacheCoordinator(
      onEvent: onEvent,
      openBackend: (_) async => OpenedCacheBackend(
        executor: interceptor == null
            ? NativeDatabase.memory()
            : NativeDatabase.memory().interceptWith(interceptor),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    cache.register(
      CachePolicy<Map<String, Object?>>(
        kind: 'material_content',
        disposition: CacheDisposition.validatedText,
        decode: (json) {
          if (rejectBrokenPayload && json['text'] == 'broken') {
            throw const FormatException('Invalid cached projection');
          }
          return json;
        },
        encode: (data) => data,
        dependencies: (_) => {'material:1'},
      ),
    );
    return cache;
  }

  CacheScope scope(String user) => CacheScope.confirmed(
    endpoint: Uri.parse('https://haruka.example/api'),
    instanceId: 'instance-1',
    userId: user,
    audience: 'client',
    sessionRef: 'session-$user',
    securityEpoch: 3,
    authzVersion: 5,
    policyVersion: 7,
  );

  CacheGrant grant(CacheScope owner, {DateTime? expiry}) => CacheGrant(
    scopeBinding: owner.binding,
    resourceKey: resource.keyFor(owner),
    version: version,
    expiresAt: expiry ?? DateTime.now().toUtc().add(const Duration(minutes: 5)),
    serverTime: DateTime.now().toUtc(),
    securityEpoch: owner.securityEpoch,
    authzVersion: owner.authzVersion,
    policyVersion: owner.policyVersion,
  );

  _ControlledRemote reply(String text, {CacheGrant? lease, bool saved = true}) => _ControlledRemote(
    fetchResult: (_) async =>
        CachePayload(value: {'text': text}, version: version, grant: lease, serverSaved: saved),
  );

  test('damaged persistent index falls back to memory without changing the old file', () async {
    final folder = await Directory.systemTemp.createTemp('haruka-cache-fallback-');
    final file = File('${folder.path}${Platform.pathSeparator}index.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('CREATE TABLE original_marker (value TEXT NOT NULL)');
    raw.execute("INSERT INTO original_marker (value) VALUES ('keep')");
    raw.execute('PRAGMA user_version = 2');
    raw.close();
    var persistentClosed = 0;
    var memoryOpened = 0;
    final events = <String>[];
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase(file),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {
          persistentClosed++;
        },
      ),
      openMemoryBackend: () async {
        memoryOpened++;
        return OpenedCacheBackend(
          executor: NativeDatabase.memory(),
          mode: CacheStorageMode.memoryOnly,
          degradedReason: 'persistent_schema_unavailable',
          closeOwner: () async {},
        );
      },
      onEvent: (event, _) => events.add(event),
    );
    cache.register(
      CachePolicy<Map<String, Object?>>(
        kind: 'material_content',
        disposition: CacheDisposition.validatedText,
        decode: (json) => json,
        encode: (data) => data,
        dependencies: (_) => {'material:1'},
      ),
    );
    addTearDown(() async {
      await cache.closeScope();
      await folder.delete(recursive: true);
    });

    await cache.attach(scope('alice'));
    expect(cache.accessReady, isTrue);
    expect(cache.storageMode, CacheStorageMode.memoryOnly);
    expect(cache.degradedReason, 'persistent_schema_unavailable');
    expect(cache.audio, isNull);
    expect(persistentClosed, 1);
    expect(memoryOpened, 1);
    expect(events, contains('cache.storage.degraded'));
    expect((await cache.usage()).textEntries, 0);
    final first = await cache.read(
      resource: resource,
      remote: reply('online', lease: grant(scope('alice'))),
    );
    expect(first.data?['text'], 'online');
    expect(first.source, CacheSource.network);
    expect(first.localReady, isFalse);
    final validated = reply('should not refetch');
    final second = await cache.read(resource: resource, remote: validated);
    expect(second.data?['text'], 'online');
    expect(second.source, CacheSource.memory);
    expect(validated.fetches, 0);
    expect(validated.validations, 1);
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: reply('must not fetch')),
      throwsA(isA<CacheBlocked>()),
    );
    cache.completeOnlineRevalidation(scope('alice'));
    await cache.clearTextScope();
    final afterClear = await cache.read(resource: resource, remote: reply('after clear'));
    expect(afterClear.data?['text'], 'after clear');
    expect(afterClear.source, CacheSource.network);
    final after = sqlite.sqlite3.open(file.path);
    try {
      expect(after.select('PRAGMA user_version').single['user_version'], 2);
      expect(after.select('SELECT value FROM original_marker').single['value'], 'keep');
    } finally {
      after.close();
    }
  });

  test('a failed memory fallback keeps the scope blocked after persistent failure', () async {
    var persistentClosed = 0;
    var memoryAttempts = 0;
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(setup: (db) => db.execute('PRAGMA user_version = 2')),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {
          persistentClosed++;
        },
      ),
      openMemoryBackend: () async {
        memoryAttempts++;
        throw StateError('memory unavailable');
      },
    );
    addTearDown(cache.closeScope);
    await expectLater(cache.attach(scope('alice')), throwsA(isA<StateError>()));
    expect(persistentClosed, 1);
    expect(memoryAttempts, 1);
    expect(cache.scope, isNull);
    expect(cache.accessReady, isFalse);
  });

  test('scope closure and attach notify subscribers before old data can render', () async {
    final cache = coordinator();
    final observed = <(bool, int)>[];
    final subscription = cache.changes.listen((_) {
      observed.add((cache.accessReady, cache.scopeGeneration));
    });
    addTearDown(() async {
      await subscription.cancel();
      await cache.closeScope();
    });
    await cache.attach(scope('a'));
    final firstGeneration = cache.scopeGeneration;
    expect(observed.last, (true, firstGeneration));
    final beforeInvalidation = cache.invalidationGeneration;
    await cache.applyCommittedMutation({'material:1'});
    expect(cache.invalidationGeneration, beforeInvalidation + 1);
    expect(cache.lastInvalidatedTags, {'material:1'});
    await cache.closeScope();
    expect(observed.last, (false, firstGeneration + 1));
    await cache.attach(scope('b'));
    expect(observed.last, (true, cache.scopeGeneration));
    expect(cache.scopeGeneration, greaterThan(firstGeneration));
  });

  test('same scope concurrent reads share one fetch and publish a complete response', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final remote = _Remote();
    final first = cache.beginRead(resource: resource, remote: remote);
    final second = cache.beginRead(resource: resource, remote: remote);
    remote.pending.complete(CachePayload(value: {'text': '朝の光'}, version: version));
    final views = await Future.wait([first.future, second.future]);
    expect(remote.fetches, 1);
    expect(views.map((view) => view.data?['text']), everyElement('朝の光'));
    expect(views.map((view) => view.localReady), everyElement(true));
    first.release();
    second.release();
  });

  test('publishing a saved result notifies cache usage observers', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    var changes = 0;
    final subscription = cache.changes.listen((_) => changes++);
    addTearDown(subscription.cancel);

    await cache.read(resource: resource, remote: reply('朝の光'));
    expect(changes, 1);
    expect((await cache.usage()).textEntries, 1);

    await cache.read(resource: resource, remote: reply('unused'));
    expect(changes, 1);
  });

  test('cache events exclude private content and identity', () async {
    const secret = 'private-body-key-token-sentinel';
    final emitted = <String>[];
    final cache = coordinator(onEvent: (name, attributes) => emitted.add('$name $attributes'));
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    await cache.read(resource: resource, remote: reply(secret));
    await cache.read(resource: resource, remote: reply('unused'));
    await cache.applyCommittedMutation({'material:1'});
    expect(emitted, isNotEmpty);
    final rendered = emitted.join('\n');
    expect(rendered, isNot(contains(secret)));
    expect(rendered, isNot(contains('alice')));
    expect(rendered, isNot(contains('session-alice')));
    expect(rendered, isNot(contains('https://haruka.example')));
    expect(emitted.any((line) => line.startsWith('cache.read.miss')), isTrue);
    expect(emitted.any((line) => line.startsWith('cache.invalidated')), isTrue);
  });

  test('committed invalidation discards a late read before publication', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final remote = _Remote();
    final lease = cache.beginRead(resource: resource, remote: remote);
    await Future<void>.delayed(Duration.zero);
    await cache.applyCommittedMutation({'material:1'});
    remote.pending.complete(CachePayload(value: {'text': 'stale'}, version: version));
    await expectLater(lease.future, throwsA(isA<CacheBlocked>()));
    lease.release();
  });

  test('scope changes cannot return the previous account response', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final remote = _Remote();
    final lease = cache.beginRead(resource: resource, remote: remote);
    await Future<void>.delayed(Duration.zero);
    await cache.attach(scope('bob'));
    remote.pending.complete(CachePayload(value: {'text': 'alice private'}, version: version));
    await expectLater(lease.future, throwsA(isA<CacheBlocked>()));
    lease.release();
    expect(cache.scope?.userId, 'bob');
  });

  test('scope partitions account, audience and endpoint; session changes binding', () {
    final alice = scope('alice');
    expect(alice.partition, isNot(scope('bob').partition));
    final admin = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example/api'),
      instanceId: 'instance-1',
      userId: 'alice',
      audience: 'admin',
      sessionRef: 'session-alice',
    );
    expect(alice.partition, isNot(admin.partition));
    final otherSession = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example/api'),
      instanceId: 'instance-1',
      userId: 'alice',
      audience: 'client',
      sessionRef: 'new-session',
    );
    expect(alice.partition, otherSession.partition);
    expect(alice.binding, isNot(otherSession.binding));
    expect(
      () => CacheScope.confirmed(
        endpoint: Uri.parse('http://haruka.example/api'),
        instanceId: 'instance-1',
        userId: 'alice',
        audience: 'client',
        sessionRef: 'session',
      ),
      throwsArgumentError,
    );
  });

  test('policy revision change blocks the old grant and requires reattachment', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    final original = scope('alice');
    await cache.attach(original);
    final revised = CacheScope.confirmed(
      endpoint: Uri.parse('https://haruka.example/api'),
      instanceId: 'instance-1',
      userId: 'alice',
      audience: 'client',
      sessionRef: 'session-alice',
      securityEpoch: original.securityEpoch,
      authzVersion: original.authzVersion,
      policyVersion: original.policyVersion + 1,
    );
    expect(() => cache.completeOnlineRevalidation(revised), throwsA(isA<CacheBlocked>()));
    expect(cache.accessReady, isFalse);
    cache.enterOfflineForUnreachableNetwork();
    expect(
      () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('session and each access version change fail closed before offline reuse', () async {
    final original = scope('alice');
    for (final change in ['session', 'security', 'user', 'policy']) {
      final cache = coordinator();
      await cache.attach(original);
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: grant(original)),
      );
      final revised = CacheScope.confirmed(
        endpoint: Uri.parse('https://haruka.example/api'),
        instanceId: original.instanceId,
        userId: original.userId,
        audience: original.audience,
        sessionRef: change == 'session' ? 'next-session' : original.sessionRef,
        securityEpoch: original.securityEpoch + (change == 'security' ? 1 : 0),
        authzVersion: original.authzVersion + (change == 'user' ? 1 : 0),
        policyVersion: original.policyVersion + (change == 'policy' ? 1 : 0),
      );
      expect(() => cache.completeOnlineRevalidation(revised), throwsA(isA<CacheBlocked>()));
      expect(cache.accessReady, isFalse, reason: change);
      cache.enterOfflineForUnreachableNetwork();
      expect(
        () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
        throwsA(isA<CacheBlocked>()),
        reason: change,
      );
      await cache.closeScope();
    }
  });

  test('persistent policies and projections require a reviewed source/action tuple', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    expect(
      () => cache.register(
        CachePolicy<Map<String, Object?>>(
          kind: 'exam_session',
          disposition: CacheDisposition.validatedText,
          decode: (json) => json,
          encode: (data) => data,
          dependencies: (_) => {'exam:one'},
        ),
      ),
      throwsStateError,
    );
    await cache.attach(scope('alice'));
    for (final projection in ['exam_paper_v1', 'exam_review_v1']) {
      final remote = reply('must not fetch');
      final examProjection = CacheResource(
        kind: resource.kind,
        id: resource.id,
        projection: projection,
        action: resource.action,
        sourceBinding: resource.sourceBinding,
      );
      await expectLater(
        cache.read(resource: examProjection, remote: remote),
        throwsA(isA<CacheBlocked>()),
      );
      expect(remote.fetches, 0);
    }
    expect((await cache.usage()).textEntries, 0);
  });

  test('local usage and quotas stay within the confirmed account scope', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final initial = await cache.usage();
    expect(initial.textBytes, 0);
    expect(initial.audioBytes, 0);
    final changed = await cache.setQuotas(textBytes: 50 * 1000000, audioBytes: 250 * 1000000);
    expect(changed.textQuotaBytes, 50 * 1000000);
    expect(changed.audioQuotaBytes, 250 * 1000000);
    await cache.clearScope();
    expect((await cache.usage()).textQuotaBytes, 50 * 1000000);
    await cache.closeScope();
    await expectLater(cache.usage(), throwsA(isA<CacheBlocked>()));
  });

  test('leaving cancels an unsettled flight and reentry starts a new fetch', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final pending = Completer<CachePayload<Map<String, Object?>>>();
    final remote = _ControlledRemote(
      fetchResult: (_) => pending.isCompleted
          ? Future.value(CachePayload(value: {'text': 'new'}, version: version))
          : pending.future,
    );
    final first = cache.beginRead(resource: resource, remote: remote);
    await Future<void>.delayed(Duration.zero);
    first.release();
    expect(remote.cancelTokens.first.isCancelled, true);
    // Complete the old request after starting a distinct read. The cancelled
    // request must not satisfy or publish the new reader.
    final secondRemote = reply('fresh');
    final second = cache.beginRead(resource: resource, remote: secondRemote);
    expect((await second.future).data?['text'], 'fresh');
    pending.complete(CachePayload(value: {'text': 'late'}, version: version));
    await expectLater(first.future, throwsA(isA<CacheBlocked>()));
    expect(remote.fetches, 1);
    expect(secondRemote.fetches, 1);
    second.release();
  });

  test('offline text requires matching unexpired grant and disk copy', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    await cache.read(
      resource: resource,
      remote: reply('saved', lease: grant(owner)),
    );
    cache.enterOfflineForUnreachableNetwork();
    final offline = await cache.read(resource: resource, remote: reply('network disabled'));
    expect(offline.source, CacheSource.disk);
    expect(offline.freshness, CacheFreshness.offline);
    expect(offline.data?['text'], 'saved');
    await cache.clearTextScope();
    await expectLater(
      cache.read(resource: resource, remote: reply('network disabled')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('offline grant binds session, access versions, source and content version', () async {
    final owner = scope('alice');
    final currentKey = resource.keyFor(owner);
    final now = DateTime.now().toUtc();
    CacheGrant candidate({
      String? binding,
      String? key,
      CacheVersion? grantedVersion,
      int? security,
      int? userVersion,
      int? policy,
    }) => CacheGrant(
      scopeBinding: binding ?? owner.binding,
      resourceKey: key ?? currentKey,
      version: grantedVersion ?? version,
      serverTime: now,
      expiresAt: now.add(const Duration(minutes: 5)),
      securityEpoch: security ?? owner.securityEpoch,
      authzVersion: userVersion ?? owner.authzVersion,
      policyVersion: policy ?? owner.policyVersion,
    );

    final wrongSource = CacheResource(
      kind: resource.kind,
      id: resource.id,
      projection: resource.projection,
      action: resource.action,
      sourceBinding: 'other-material:revision-1:chapter-1',
    );
    final wrongProjection = CacheResource(
      kind: resource.kind,
      id: resource.id,
      projection: 'textbook-reading-v1',
      action: resource.action,
      sourceBinding: resource.sourceBinding,
    );
    final wrongAction = CacheResource(
      kind: resource.kind,
      id: resource.id,
      projection: resource.projection,
      action: 'material.list',
      sourceBinding: resource.sourceBinding,
    );
    final cases = <String, CacheGrant>{
      'session_ref': candidate(binding: '${owner.binding}-previous-session'),
      'security_epoch': candidate(security: owner.securityEpoch + 1),
      'authz_version.user': candidate(userVersion: owner.authzVersion + 1),
      'authz_version.policy': candidate(policy: owner.policyVersion + 1),
      'source_binding': candidate(key: wrongSource.keyFor(owner)),
      'projection': candidate(key: wrongProjection.keyFor(owner)),
      'action': candidate(key: wrongAction.keyFor(owner)),
      'resource_version': candidate(
        grantedVersion: const CacheVersion(
          resource: '2',
          representation: 'novel-v1',
          artifact: 'text-1',
        ),
      ),
      'artifact_version': candidate(
        grantedVersion: const CacheVersion(
          resource: '1',
          representation: 'novel-v1',
          artifact: 'text-2',
        ),
      ),
    };
    for (final entry in cases.entries) {
      final cache = coordinator();
      await cache.attach(owner);
      final online = await cache.read(
        resource: resource,
        remote: reply('saved', lease: entry.value),
      );
      expect(online.localReady, isTrue, reason: entry.key);
      cache.enterOfflineForUnreachableNetwork();
      await expectLater(
        cache.read(resource: resource, remote: reply('network disabled')),
        throwsA(isA<CacheBlocked>()),
        reason: entry.key,
      );
      await cache.closeScope();
    }
  });

  test('invalid cached projection blocks offline and is fetched again online', () async {
    final owner = scope('alice');
    final events = <String>[];
    final cache = coordinator(
      rejectBrokenPayload: true,
      onEvent: (name, attributes) => events.add('$name ${attributes['reason']}'),
    );
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    expect(
      (await cache.read(
        resource: resource,
        remote: reply('broken', lease: grant(owner)),
      )).localReady,
      isTrue,
    );
    cache.enterOfflineForUnreachableNetwork();
    final offlineRemote = reply('must not fetch');
    await expectLater(
      cache.read(resource: resource, remote: offlineRemote),
      throwsA(isA<CacheBlocked>()),
    );
    expect(offlineRemote.fetches, 0);
    cache.requireOnlineRevalidation();
    cache.completeOnlineRevalidation(owner);
    final recovery = reply('recovered');
    final result = await cache.read(resource: resource, remote: recovery);
    expect(result.data?['text'], 'recovered');
    expect(result.localReady, isTrue);
    expect(recovery.fetches, 1);
    expect(recovery.validations, 0);
    expect(events, contains('cache.storage.degraded invalid_payload'));
  });

  test('expired or absent grant never authorizes offline display', () async {
    for (final lease in <CacheGrant?>[
      null,
      grant(scope('alice'), expiry: DateTime.now().toUtc().subtract(const Duration(seconds: 1))),
    ]) {
      final cache = coordinator();
      await cache.attach(scope('alice'));
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: lease),
      );
      cache.enterOfflineForUnreachableNetwork();
      await expectLater(
        cache.read(resource: resource, remote: reply('network disabled')),
        throwsA(isA<CacheBlocked>()),
      );
      await cache.closeScope();
    }
  });

  test('offline grant cannot gain time from a slow network response', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    final serverTime = DateTime.now().toUtc();
    final shortGrant = CacheGrant(
      scopeBinding: owner.binding,
      resourceKey: resource.keyFor(owner),
      version: version,
      serverTime: serverTime,
      expiresAt: serverTime.add(const Duration(milliseconds: 30)),
      securityEpoch: owner.securityEpoch,
      authzVersion: owner.authzVersion,
      policyVersion: owner.policyVersion,
    );
    final slowRemote = _ControlledRemote(
      fetchResult: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 90));
        return CachePayload(value: {'text': 'saved'}, version: version, grant: shortGrant);
      },
    );
    await cache.read(resource: resource, remote: slowRemote);
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: reply('network disabled')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('older server time cannot replace a newer short offline grant', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    final now = DateTime.now().toUtc();
    final shortGrant = CacheGrant(
      scopeBinding: owner.binding,
      resourceKey: resource.keyFor(owner),
      version: version,
      serverTime: now,
      expiresAt: now.add(const Duration(milliseconds: 250)),
      securityEpoch: owner.securityEpoch,
      authzVersion: owner.authzVersion,
      policyVersion: owner.policyVersion,
    );
    final staleGrant = CacheGrant(
      scopeBinding: owner.binding,
      resourceKey: resource.keyFor(owner),
      version: version,
      serverTime: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(hours: 1)),
      securityEpoch: owner.securityEpoch,
      authzVersion: owner.authzVersion,
      policyVersion: owner.policyVersion,
    );
    await cache.read(
      resource: resource,
      remote: reply('saved', lease: shortGrant),
    );
    final validating = _ControlledRemote(
      fetchResult: (_) async => throw StateError('A same version must not refetch'),
      validation: (_) async =>
          CacheValidation(state: ValidationState.same, version: version, grant: staleGrant),
    );
    expect((await cache.read(resource: resource, remote: validating)).data?['text'], 'saved');
    expect(validating.validations, 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: reply('network disabled')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('an older server time on another resource keeps its valid offline grant', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    final newerTime = DateTime.now().toUtc();
    final firstGrant = CacheGrant(
      scopeBinding: owner.binding,
      resourceKey: resource.keyFor(owner),
      version: version,
      serverTime: newerTime,
      expiresAt: newerTime.add(const Duration(minutes: 5)),
      securityEpoch: owner.securityEpoch,
      authzVersion: owner.authzVersion,
      policyVersion: owner.policyVersion,
    );
    await cache.read(
      resource: resource,
      remote: reply('newer', lease: firstGrant),
    );
    const secondResource = CacheResource(
      kind: 'material_content',
      id: 'chapter-2',
      projection: 'novel-reading-v1',
      action: 'material.read',
      sourceBinding: 'material-1:revision-1:chapter-2',
    );
    final olderGrant = CacheGrant(
      scopeBinding: owner.binding,
      resourceKey: secondResource.keyFor(owner),
      version: version,
      serverTime: newerTime.subtract(const Duration(minutes: 1)),
      expiresAt: newerTime.add(const Duration(hours: 1)),
      securityEpoch: owner.securityEpoch,
      authzVersion: owner.authzVersion,
      policyVersion: owner.policyVersion,
    );
    await cache.read(
      resource: secondResource,
      remote: reply('older', lease: olderGrant),
    );
    cache.enterOfflineForUnreachableNetwork();
    expect(
      (await cache.read(resource: secondResource, remote: reply('network disabled'))).data?['text'],
      'older',
    );
    expect(
      (await cache.read(resource: resource, remote: reply('network disabled'))).data?['text'],
      'newer',
    );
  });

  test('an in-flight read stays retired after access revalidation completes', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    final remote = _Remote();
    final pending = cache.beginRead(resource: resource, remote: remote);
    await Future<void>.delayed(Duration.zero);
    cache.requireOnlineRevalidation();
    cache.completeOnlineRevalidation(owner);
    remote.pending.complete(CachePayload(value: {'text': 'before revalidation'}, version: version));
    await expectLater(pending.future, throwsA(isA<CacheBlocked>()));
    pending.release();
    expect((await cache.usage()).textEntries, 0);
    final fresh = await cache.read(resource: resource, remote: reply('after revalidation'));
    expect(fresh.data?['text'], 'after revalidation');
    expect(fresh.localReady, isTrue);
  });

  test('a delayed cross-tab clear hint cannot restore uncertain access', () async {
    for (final blockForFailure in [false, true]) {
      final cache = coordinator();
      await cache.attach(scope('alice'));
      if (!blockForFailure) cache.requireOnlineRevalidation();
      cache.handleExternalCacheHint('clear');
      if (blockForFailure) cache.blockForAuthorizationFailure();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cache.accessReady, isFalse);
      expect(
        () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
        throwsA(isA<CacheBlocked>()),
      );
      await cache.closeScope();
    }
  });

  test('authorization failure and revalidation block stale cache reuse', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    await cache.read(
      resource: resource,
      remote: reply('saved', lease: grant(owner)),
    );
    cache.requireOnlineRevalidation();
    expect(
      () => cache.beginRead(resource: resource, remote: reply('other')),
      throwsA(isA<CacheBlocked>()),
    );
    cache.completeOnlineRevalidation(owner);
    cache.blockForAuthorizationFailure();
    cache.enterOfflineForUnreachableNetwork();
    expect(
      () => cache.beginRead(resource: resource, remote: reply('other')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('401 validation and 403 fetch close grants instead of falling back offline', () async {
    for (final (status, seedDisk) in [(401, true), (403, false)]) {
      final owner = scope('alice');
      final cache = coordinator();
      await cache.attach(owner);
      if (seedDisk) {
        await cache.read(
          resource: resource,
          remote: reply('saved', lease: grant(owner)),
        );
      }
      final options = RequestOptions(path: '/cache/validate');
      final denied = DioException(
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: status),
        type: DioExceptionType.badResponse,
      );
      final failing = _ControlledRemote(
        fetchResult: (_) async => throw denied,
        validation: (_) async => throw denied,
      );
      await expectLater(
        cache.read(resource: resource, remote: failing),
        throwsA(isA<DioException>()),
      );
      expect(cache.accessReady, isFalse, reason: '$status');
      cache.enterOfflineForUnreachableNetwork();
      expect(
        () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
        throwsA(isA<CacheBlocked>()),
      );
      await cache.closeScope();
    }
  });

  test('ApiClient auth and permission failures close a previously valid grant', () async {
    for (final code in [
      'AUTH_REQUIRED',
      'PERMISSION_DENIED',
      'AUTH_SCOPE_CHANGED',
      'SESSION_INVALID',
    ]) {
      final owner = scope('alice');
      final cache = coordinator();
      await cache.attach(owner);
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: grant(owner)),
      );
      final failure = ApiFailure(code: code);
      final remote = _ControlledRemote(
        fetchResult: (_) async => throw failure,
        validation: (_) async => throw failure,
      );
      await expectLater(cache.read(resource: resource, remote: remote), throwsA(same(failure)));
      expect(cache.accessReady, isFalse, reason: code);
      cache.enterOfflineForUnreachableNetwork();
      expect(
        () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
        throwsA(isA<CacheBlocked>()),
        reason: code,
      );
      await cache.closeScope();
    }
  });

  test('HTTP 401 and 403 close grants even with unknown or malformed error bodies', () async {
    for (final (status, code) in [(401, 'UNKNOWN_ERROR'), (403, 'INVALID_RESPONSE')]) {
      final owner = scope('alice');
      final cache = coordinator();
      await cache.attach(owner);
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: grant(owner)),
      );
      final failure = ApiFailure(code: code, statusCode: status);
      final remote = _ControlledRemote(
        fetchResult: (_) async => throw failure,
        validation: (_) async => throw failure,
      );
      await expectLater(cache.read(resource: resource, remote: remote), throwsA(same(failure)));
      expect(cache.accessReady, isFalse, reason: '$status $code');
      cache.enterOfflineForUnreachableNetwork();
      expect(
        () => cache.beginRead(resource: resource, remote: reply('must not fetch')),
        throwsA(isA<CacheBlocked>()),
        reason: '$status $code',
      );
      await cache.closeScope();
    }
  });

  test('ApiClient timeout-like and service errors do not auto-enter offline mode', () async {
    for (final code in ['NETWORK_UNAVAILABLE', 'SERVICE_UNAVAILABLE', 'RATE_LIMITED']) {
      final owner = scope('alice');
      final cache = coordinator();
      await cache.attach(owner);
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: grant(owner)),
      );
      final failure = ApiFailure(code: code);
      final remote = _ControlledRemote(
        fetchResult: (_) async => throw failure,
        validation: (_) async => throw failure,
      );
      await expectLater(cache.read(resource: resource, remote: remote), throwsA(same(failure)));
      final retry = reply('unused');
      expect(
        (await cache.read(resource: resource, remote: retry)).freshness,
        CacheFreshness.validated,
      );
      expect(retry.validations, 1, reason: code);
      await cache.closeScope();
    }
  });

  test('confirmed online access exits a prior offline and authorization block', () async {
    final owner = scope('alice');
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(owner);
    await cache.read(
      resource: resource,
      remote: reply('saved', lease: grant(owner)),
    );
    cache.enterOfflineForUnreachableNetwork();
    cache.blockForAuthorizationFailure();
    cache.completeOnlineRevalidation(owner);
    final remote = reply('unused');
    final refreshed = await cache.read(resource: resource, remote: remote);
    expect(refreshed.freshness, CacheFreshness.validated);
    expect(remote.validations, 1);
  });

  test('timeout, 5xx and 429 never silently serve a saved grant offline', () async {
    final options = RequestOptions(path: '/cache/validate');
    final failures = <DioException>[
      DioException(requestOptions: options, type: DioExceptionType.connectionTimeout),
      DioException(
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: 503),
        type: DioExceptionType.badResponse,
      ),
      DioException(
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: 429),
        type: DioExceptionType.badResponse,
      ),
    ];
    for (final failure in failures) {
      final owner = scope('alice');
      final cache = coordinator();
      await cache.attach(owner);
      await cache.read(
        resource: resource,
        remote: reply('saved', lease: grant(owner)),
      );
      final failing = _ControlledRemote(
        fetchResult: (_) async => throw failure,
        validation: (_) async => throw failure,
      );
      await expectLater(
        cache.read(resource: resource, remote: failing),
        throwsA(isA<DioException>()),
      );
      final retry = reply('unused');
      final verified = await cache.read(resource: resource, remote: retry);
      expect(verified.freshness, CacheFreshness.validated);
      expect(retry.validations, 1, reason: '${failure.type} ${failure.response?.statusCode}');
      await cache.closeScope();
    }
  });

  test('server-uncommitted result stays out of persistent and offline cache', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final result = await cache.read(resource: resource, remote: reply('draft', saved: false));
    expect(result.serverSaved, false);
    expect(result.localReady, false);
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: reply('network disabled')),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('clear prevents background refill until an explicit user read', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    await cache.clearTextScope();
    final background = await cache.read(resource: resource, remote: reply('background'));
    expect(background.localReady, false);
    final explicit = await cache.read(
      resource: resource,
      remote: reply('requested'),
      explicitUserAction: true,
    );
    expect(explicit.localReady, true);
  });

  test('full clear rotates the generation and only a new explicit read can persist', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final before = await cache.read(resource: resource, remote: reply('first'));
    expect(before.localReady, true);
    final generation = cache.accountGeneration;
    final cleared = await cache.clearScope();
    expect(cleared.pendingAudio, 0);
    expect(cache.accountGeneration, greaterThan(generation));
    final background = await cache.read(resource: resource, remote: reply('background'));
    expect(background.localReady, false);
    final explicit = await cache.read(
      resource: resource,
      remote: reply('requested'),
      explicitUserAction: true,
    );
    expect(explicit.localReady, true);
  });

  test('a delayed storage snapshot cannot overwrite a newer local clear', () async {
    final pause = _PauseCommittedStorageSnapshot();
    final cache = coordinator(interceptor: pause);
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    await cache.setQuotas(textBytes: 0);
    final before = cache.storageRevision;
    pause.armed = true;
    final staleSync = cache.synchronizeStorage();
    await pause.reached.future;
    await cache.clearTextScope();
    expect(cache.storageRevision, greaterThan(before));
    final afterClear = cache.storageRevision;
    final fresh = await cache.read(
      resource: resource,
      remote: reply('new local body'),
      explicitUserAction: true,
    );
    expect(fresh.data, {'text': 'new local body'});
    expect(fresh.localReady, isFalse);
    pause.release.complete();
    await expectLater(
      staleSync,
      throwsA(isA<CacheBlocked>().having((error) => error.reason, 'reason', 'scope_changed')),
    );
    expect(cache.storageRevision, afterClear);
    expect(cache.accessReady, isTrue);
    final validated = reply('unexpected duplicate fetch');
    final retained = await cache.read(resource: resource, remote: validated);
    expect(retained.data, fresh.data);
    expect(retained.localReady, isFalse);
    expect(validated.fetches, 0);
  });

  test('full clear completes before a subsequently requested account attach', () async {
    final pause = _PausePendingDeletionRead();
    final cache = coordinator(interceptor: pause);
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    pause.armed = true;
    final clearing = cache.clearScope();
    await pause.reached.future;
    final attaching = cache.attach(scope('bob'));
    expect(cache.scope?.userId, 'alice');
    pause.release.complete();
    expect((await clearing).pendingAudio, 0);
    await attaching;
    expect(cache.scope?.userId, 'bob');
    expect(cache.accessReady, isTrue);
  });

  test('foreground lease transition rejects a late grant without dropping online body', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    final owner = scope('alice');
    await cache.attach(owner);
    await cache.read(
      resource: resource,
      remote: reply('existing', lease: grant(owner)),
    );
    final reached = Completer<void>();
    final released = Completer<CacheValidation>();
    final remote = _ControlledRemote(
      fetchResult: (_) async => CachePayload(value: {'text': 'new'}, version: version),
      validation: (_) {
        reached.complete();
        return released.future;
      },
    );
    final read = cache.read(resource: resource, remote: remote);
    await reached.future;
    cache.setOfflineLeaseForeground(false);
    cache.setOfflineLeaseForeground(true);
    released.complete(
      CacheValidation(state: ValidationState.same, version: version, grant: grant(owner)),
    );
    expect((await read).data, {'text': 'existing'});
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: remote),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'offline_grant_unavailable'),
      ),
    );
    cache.completeOnlineRevalidation(owner);
    final fresh = _ControlledRemote(
      fetchResult: (_) async => CachePayload(value: {'text': 'unused'}, version: version),
      validation: (_) async =>
          CacheValidation(state: ValidationState.same, version: version, grant: grant(owner)),
    );
    await cache.read(resource: resource, remote: fresh);
    cache.enterOfflineForUnreachableNetwork();
    expect((await cache.read(resource: resource, remote: fresh)).freshness, CacheFreshness.offline);
  });

  test('an authorization block during text clear cannot be undone by its completion', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final clearing = cache.clearTextScope();
    cache.blockForAuthorizationFailure();
    await expectLater(clearing, throwsA(isA<CacheBlocked>()));
    expect(cache.accessReady, isFalse);
  });

  test('an authorization block during full clear cannot be undone by its completion', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    final clearing = cache.clearScope();
    cache.blockForAuthorizationFailure();
    await expectLater(clearing, throwsA(isA<CacheBlocked>()));
    expect(cache.accessReady, isFalse);
  });

  test('changed and unavailable validation do not reuse a stale projection', () async {
    final cache = coordinator();
    addTearDown(cache.closeScope);
    await cache.attach(scope('alice'));
    await cache.read(resource: resource, remote: reply('old'));
    final changed = _ControlledRemote(
      fetchResult: (_) async => CachePayload(
        value: {'text': 'new'},
        version: const CacheVersion(resource: '2', representation: 'novel-v1', artifact: 'text-2'),
      ),
      validation: (_) async => const CacheValidation(state: ValidationState.changed),
    );
    expect((await cache.read(resource: resource, remote: changed)).data?['text'], 'new');
    expect(changed.validations, 1);
    expect(changed.fetches, 1);
    final denied = _ControlledRemote(
      fetchResult: (_) async => CachePayload(value: {'text': 'should not fetch'}, version: version),
      validation: (_) async => const CacheValidation(state: ValidationState.unavailable),
    );
    await expectLater(cache.read(resource: resource, remote: denied), throwsA(isA<CacheBlocked>()));
    expect(denied.fetches, 0);
  });
}

import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/cache/audio_blob_backend_native.dart';
import 'package:haruka/core/cache/audio_blob_store.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_database.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_invalidation_hint.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite;

const _version = CacheVersion(resource: '1', representation: 'v1', artifact: 'text-1');
CacheResource _resource(String id, {String projection = 'novel-reading-v1'}) => CacheResource(
  kind: 'material_content',
  id: id,
  projection: projection,
  action: 'material.read',
  sourceBinding: 'material:$id',
);
CacheScope _scope([String user = 'a']) => CacheScope.confirmed(
  endpoint: Uri.parse('https://cache.example/api'),
  instanceId: 'test',
  userId: user,
  audience: 'client',
  sessionRef: 'session-$user',
  securityEpoch: 0,
  authzVersion: 1,
  policyVersion: 1,
);

class _Source implements CacheRemote<Map<String, Object?>> {
  _Source(this.owner);
  final CacheScope owner;
  final fetched = <CacheResource>[];
  int validations = 0;
  Object? error;
  CacheValidation? validationOverride;
  Future<CachePayload<Map<String, Object?>>> Function(CacheResource)? fetchOverride;
  CacheResource? redirect;
  CacheGrant grant(CacheResource resource) => CacheGrant(
    scopeBinding: owner.binding,
    resourceKey: resource.keyFor(owner),
    version: _version,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    serverTime: DateTime.now().toUtc(),
    securityEpoch: 0,
    authzVersion: 1,
    policyVersion: 1,
  );
  @override
  Future<CachePayload<Map<String, Object?>>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    fetched.add(resource);
    if (error != null) throw error!;
    if (fetchOverride != null) return fetchOverride!(resource);
    return CachePayload(value: {'text': resource.id}, version: _version, grant: grant(resource));
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    validations++;
    if (error != null) throw error!;
    if (validationOverride != null) return validationOverride!;
    return CacheValidation(
      state: redirect == null ? ValidationState.same : ValidationState.changed,
      version: known,
      readResource: redirect,
      grant: redirect == null ? grant(resource) : null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late File file;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('haruka-cache-recovery-');
    file = File('${folder.path}/index.sqlite');
  });
  tearDown(() => folder.delete(recursive: true));

  Future<CacheCoordinator> open({List<Duration>? delays}) async {
    final cache = CacheCoordinator(
      retryDelay: (delay) async {
        delays?.add(delay);
      },
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase(file),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    cache.register(
      CachePolicy<Map<String, Object?>>(
        kind: 'material_content',
        disposition: CacheDisposition.validatedText,
        decode: (json) => json,
        encode: (json) => json,
        dependencies: (resource) => {'material:${resource.id}'},
      ),
    );
    await cache.attach(_scope());
    return cache;
  }

  test('failed unavailable deletion cannot revive the old offline grant', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    await cache.read(resource: resource, remote: source);
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_cache_delete BEFORE DELETE ON cache_entries "
      "BEGIN SELECT RAISE(FAIL, 'injected delete failure'); END",
    );
    raw.close();
    source.validationOverride = const CacheValidation(state: ValidationState.unavailable);
    await expectLater(cache.read(resource: resource, remote: source), throwsA(anything));
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(
      cache.read(resource: resource, remote: source),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'offline_grant_unavailable'),
      ),
    );
  });

  test('failed grant revocation also denies exact-version offline reads', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    await cache.read(resource: resource, remote: source);
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_grant_delete BEFORE DELETE ON offline_grants "
      "BEGIN SELECT RAISE(FAIL, 'injected grant failure'); END",
    );
    raw.close();
    source.validationOverride = const CacheValidation(
      state: ValidationState.same,
      version: _version,
      revokeGrant: true,
    );
    final online = await cache.read(resource: resource, remote: source);
    expect(online.data, {'text': 'one'});
    expect(online.localReady, isFalse);
    cache.enterOfflineForUnreachableNetwork();
    for (final knownVersion in <CacheVersion?>[null, _version]) {
      await expectLater(
        cache.read(resource: resource, remote: source, knownVersion: knownVersion),
        throwsA(
          isA<CacheBlocked>().having(
            (error) => error.reason,
            'reason',
            'offline_grant_unavailable',
          ),
        ),
      );
    }
  });

  test('a failed last-access write keeps a server-confirmed same body online', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    await cache.read(resource: resource, remote: source);
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_cache_touch BEFORE UPDATE OF last_access_at ON cache_entries "
      "BEGIN SELECT RAISE(FAIL, 'injected touch failure'); END",
    );
    raw.close();
    final same = await cache.read(resource: resource, remote: source);
    expect(same.data, {'text': 'one'});
    expect(same.localReady, isFalse);
    expect(source.validations, 1);
  });

  test('an unpersisted confirmed body retries publication after insert recovers', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_cache_insert BEFORE INSERT ON cache_entries "
      "BEGIN SELECT RAISE(FAIL, 'injected insert failure'); END",
    );
    final first = await cache.read(resource: resource, remote: source);
    expect(first.data, {'text': 'one'});
    expect(first.localReady, isFalse);
    raw.execute('DROP TRIGGER reject_cache_insert');
    raw.close();

    final same = await cache.read(resource: resource, remote: source);
    expect(same.data, first.data);
    expect(same.localReady, isTrue);
    expect(source.fetched, hasLength(1));
    expect(source.validations, 1);
  });

  test(
    'exact pending version retries against its original head without losing logical memory',
    () async {
      final cache = await open();
      addTearDown(cache.closeScope);
      final resource = _resource('one');
      final source = _Source(_scope());
      expect((await cache.read(resource: resource, remote: source)).localReady, isTrue);
      const newer = CacheVersion(resource: '2', representation: 'v1', artifact: 'text-2');
      final newGrant = CacheGrant(
        scopeBinding: _scope().binding,
        resourceKey: resource.keyFor(_scope()),
        version: newer,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        serverTime: DateTime.now().toUtc(),
        securityEpoch: 0,
        authzVersion: 1,
        policyVersion: 1,
      );
      source.validationOverride = const CacheValidation(state: ValidationState.changed);
      source.fetchOverride = (_) async =>
          CachePayload(value: {'text': 'v2'}, version: newer, grant: newGrant);
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(
        "CREATE TRIGGER reject_new_insert BEFORE INSERT ON cache_entries "
        "BEGIN SELECT RAISE(FAIL, 'injected insert failure'); END",
      );
      final pending = await cache.read(resource: resource, remote: source);
      expect(pending.data, {'text': 'v2'});
      expect(pending.localReady, isFalse);
      raw.execute('DROP TRIGGER reject_new_insert');
      raw.close();

      const missing = CacheVersion(resource: '0', representation: 'v1', artifact: 'text-0');
      final missingViews = <CacheView<Map<String, Object?>>>[];
      await expectLater(
        cache.read(
          resource: resource,
          remote: source,
          knownVersion: missing,
          preserveCurrent: true,
          onView: missingViews.add,
        ),
        throwsA(isA<CacheBlocked>()),
      );
      expect(missingViews.where((view) => view.data != null), isEmpty);
      source.validationOverride = const CacheValidation(
        state: ValidationState.same,
        version: newer,
      );
      final exact = await cache.read(resource: resource, remote: source, knownVersion: newer);
      expect(exact.data, {'text': 'v2'});
      expect(exact.localReady, isTrue);
      expect(source.fetched, hasLength(2));
      final database = CacheDatabase(NativeDatabase(file));
      try {
        final key = resource.keyFor(_scope());
        expect((await database.entry(key))?.version.resource, '2');
        expect((await database.entry(key, version: _version))?.payload['text'], 'one');
        expect((await database.offlineGrant(cacheEntryKey(key, newer)))?.version.resource, '2');
      } finally {
        await database.close();
      }
    },
  );

  test('exact revocation cannot be republished through a pending logical alias', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_cache_insert BEFORE INSERT ON cache_entries "
      "BEGIN SELECT RAISE(FAIL, 'injected insert failure'); END",
    );
    expect((await cache.read(resource: resource, remote: source)).localReady, isFalse);
    source.validationOverride = const CacheValidation(
      state: ValidationState.same,
      version: _version,
      revokeGrant: true,
    );
    expect(
      (await cache.read(resource: resource, remote: source, knownVersion: _version)).localReady,
      isFalse,
    );
    raw.execute('DROP TRIGGER reject_cache_insert');
    raw.close();
    source.validationOverride = const CacheValidation(
      state: ValidationState.same,
      version: _version,
    );
    expect((await cache.read(resource: resource, remote: source)).localReady, isTrue);
    final database = CacheDatabase(NativeDatabase(file));
    try {
      expect(
        await database.offlineGrant(cacheEntryKey(resource.keyFor(_scope()), _version)),
        isNull,
      );
    } finally {
      await database.close();
    }
  });

  test('pending valid grant survives a same response without renewal', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    await cache.read(resource: resource, remote: source);
    source.validationOverride = const CacheValidation(state: ValidationState.unavailable);
    await expectLater(cache.read(resource: resource, remote: source), throwsA(isA<CacheBlocked>()));

    final raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      "CREATE TRIGGER reject_cache_insert BEFORE INSERT ON cache_entries "
      "BEGIN SELECT RAISE(FAIL, 'injected insert failure'); END",
    );
    source.validationOverride = null;
    expect((await cache.read(resource: resource, remote: source)).localReady, isFalse);
    raw.execute('DROP TRIGGER reject_cache_insert');
    raw.close();
    source.validationOverride = const CacheValidation(
      state: ValidationState.same,
      version: _version,
    );
    expect((await cache.read(resource: resource, remote: source)).localReady, isTrue);
    cache.enterOfflineForUnreachableNetwork();
    expect(
      (await cache.read(resource: resource, remote: source)).freshness,
      CacheFreshness.offline,
    );
    expect(source.fetched, hasLength(2));
  });

  test('quota recovery publishes a validated body without a second fetch', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    await cache.setQuotas(textBytes: 0);
    final resource = _resource('one');
    final source = _Source(_scope());
    expect((await cache.read(resource: resource, remote: source)).localReady, isFalse);
    await cache.setQuotas(textBytes: 1024);
    final same = await cache.read(resource: resource, remote: source);
    expect(same.localReady, isTrue);
    expect(source.fetched, hasLength(1));
    expect(source.validations, 1);
  });

  test('a removed durable row does not make ordinary memory a publication candidate', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final resource = _resource('one');
    final source = _Source(_scope());
    expect((await cache.read(resource: resource, remote: source)).localReady, isTrue);
    final other = CacheDatabase(NativeDatabase(file));
    final key = resource.keyFor(_scope());
    final snapshot = await other.snapshot(key, {'material:one'});
    expect(
      await other.deleteEntryIfCurrent(
        expectedStorageEpoch: snapshot.storageEpoch,
        entryKey: key,
        expectedPublicationEpoch: snapshot.entry!.publicationEpoch,
      ),
      isTrue,
    );
    await other.close();
    final refreshed = await cache.read(resource: resource, remote: source);
    expect(refreshed.data, {'text': 'one'});
    expect(source.fetched, hasLength(2));
    expect(source.validations, 0);
  });

  test('late refusal from the old account does not close the new account', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final started = Completer<void>();
    final result = Completer<CachePayload<Map<String, Object?>>>();
    final source = _Source(_scope())
      ..fetchOverride = (_) {
        started.complete();
        return result.future;
      };
    final oldRead = cache.read(resource: _resource('one'), remote: source);
    final rejected = expectLater(oldRead, throwsA(anything));
    await started.future;
    await cache.attach(_scope('b'));
    result.completeError(const ApiFailure(code: 'PERMISSION_DENIED', statusCode: 403));
    await rejected;
    expect(cache.scope?.userId, 'b');
    expect(cache.accessReady, isTrue);
  });

  test('pending cleanup keeps a freshly fetched online body without publishing it', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    await cache.clearTextScope();
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute("UPDATE cache_control SET clear_state = 'pending'");
    raw.close();
    final source = _Source(_scope());
    final view = await cache.read(
      resource: _resource('one'),
      remote: source,
      explicitUserAction: true,
    );
    expect(view.data, {'text': 'one'});
    expect(view.localReady, isFalse);
    expect(source.fetched, hasLength(1));
  });

  test('text clear promptly drains a dead stage and keeps ready audio playable', () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => folder.path);
    final cache = await open();
    try {
      final owner = _scope();
      final text = _resource('one');
      final source = _Source(owner);
      expect((await cache.read(resource: text, remote: source)).localReady, isTrue);
      const speech = CacheResource(
        kind: 'speech_asset',
        id: 'ready-speech',
        projection: 'ordinary-audio-v1',
        action: 'speech.play',
        sourceBinding: 'material:one',
      );
      final sample = <int>[1, 2, 3, 4];
      final ready = await cache.audio!.download(
        resource: speech,
        version: 'v1',
        format: 'audio/mpeg',
        sha256Hex: sha256.convert(sample).toString(),
        expectedBytes: sample.length,
        chunks: Stream.value(sample),
        readAllowedNow: () async => true,
      );
      expect(ready, isNotNull);

      final audioDirectory = Directory(
        path.join(folder.path, 'haruka-cache', owner.partition, 'audio'),
      );
      final referenceStore = AudioBlobStore(owner, NativeAudioByteBackend(audioDirectory));
      final database = CacheDatabase(NativeDatabase(file));
      final oldEpoch = await database.storageEpoch();
      final deadKey = const CacheResource(
        kind: 'speech_asset',
        id: 'dead-stage',
        projection: 'ordinary-audio-v1',
        action: 'speech.play',
        sourceBinding: 'material:one',
      ).keyFor(owner);
      final stageRef = referenceStore.stageReference(oldEpoch, 'dead-owner', deadKey);
      expect(
        await database.beginAudioOperation(
          expectedStorageEpoch: oldEpoch,
          operationId: 'dead-owner',
          assetKey: deadKey,
          reserveBytes: 6,
          stagingReference: stageRef,
        ),
        isTrue,
      );
      await File(path.join(audioDirectory.path, stageRef)).writeAsBytes([9, 8]);
      await database.close();
      await referenceStore.close();

      await cache.clearTextScope();
      expect(await File(path.join(audioDirectory.path, stageRef)).exists(), isFalse);
      final after = CacheDatabase(NativeDatabase(file));
      try {
        expect(await after.audioOperationsForAsset(deadKey), isEmpty);
        expect((await after.usage()).activeDownloads, 0);
        expect((await after.usage()).audioBytes, sample.length);
        expect(await after.clearState(), 'ready');
        expect(await after.entry(text.keyFor(owner)), isNull);
      } finally {
        await after.close();
      }
      final played = await cache.audio!.read<List<int>>(
        resource: speech,
        version: 'v1',
        readAllowedNow: () async => true,
        consume: (chunks) async => [await for (final chunk in chunks) ...chunk],
      );
      expect(played, sample);
      final background = await cache.read(resource: text, remote: source);
      expect(background.localReady, isFalse);
      expect(source.fetched, hasLength(2));
      final unchanged = CacheDatabase(NativeDatabase(file));
      try {
        expect(await unchanged.entry(text.keyFor(owner)), isNull);
      } finally {
        await unchanged.close();
      }
    } finally {
      await cache.closeScope();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('stored grant restores after a hint under a live clock, but never after restart', () async {
    var cache = await open();
    final resource = _resource('one');
    final source = _Source(_scope());
    await cache.read(resource: resource, remote: source);
    final account = cache.accountGeneration;
    cache.handleExternalCacheHint('invalidate');
    expect(cache.accountGeneration, account);
    cache.enterOfflineForUnreachableNetwork();
    final offline = await cache.read(resource: resource, remote: source);
    expect(offline.freshness, CacheFreshness.offline);
    expect(offline.data, {'text': 'one'});
    expect(source.fetched, hasLength(1));
    expect(source.validations, 0);
    await cache.closeScope();

    cache = await open();
    addTearDown(cache.closeScope);
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(cache.read(resource: resource, remote: source), throwsA(isA<CacheBlocked>()));
    cache.completeOnlineRevalidation(_scope());
    await cache.read(resource: resource, remote: source);
    cache.enterOfflineForUnreachableNetwork();
    expect(
      (await cache.read(resource: resource, remote: source)).freshness,
      CacheFreshness.offline,
    );
    cache.requireOnlineRevalidation();
    cache.completeOnlineRevalidation(_scope());
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(cache.read(resource: resource, remote: source), throwsA(isA<CacheBlocked>()));
  });

  test('lost clear broadcast adopts the durable epoch and allows the next online read', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final source = _Source(_scope());
    final resource = _resource('one');
    await cache.read(resource: resource, remote: source);
    final other = CacheDatabase(NativeDatabase(file));
    await other.clearText();
    await other.close();
    final refreshed = await cache.read(resource: resource, remote: source);
    expect(refreshed.data, {'text': 'one'});
    expect(refreshed.localReady, isFalse, reason: 'A clear must not automatically refill disk');
    expect(
      (await cache.read(resource: resource, remote: source, explicitUserAction: true)).localReady,
      isTrue,
    );
  });

  test('changed reads the specified projection and stores it under its own key', () async {
    final cache = await open();
    addTearDown(cache.closeScope);
    final old = _resource('old');
    final next = _resource('new', projection: 'textbook-reading-v1');
    final source = _Source(_scope());
    await cache.read(resource: old, remote: source);
    source.redirect = next;
    final changed = await cache.read(resource: old, remote: source);
    expect(source.fetched.last, same(next));
    expect(changed.data, {'text': 'new'});
    cache.enterOfflineForUnreachableNetwork();
    await expectLater(cache.read(resource: old, remote: source), throwsA(isA<CacheBlocked>()));
    expect((await cache.read(resource: next, remote: source)).data, {'text': 'new'});
  });

  test('text eviction respects another consumer and releases a pin after invalidation', () async {
    final first = await open();
    final second = await open();
    addTearDown(first.closeScope);
    addTearDown(second.closeScope);
    await first.setQuotas(textBytes: 14);
    final source = _Source(_scope());
    final pinned = _resource('one');
    await first.read(resource: pinned, remote: source);
    final pin = await first.pin(pinned);
    final next = _resource('two');
    expect((await second.read(resource: next, remote: source)).localReady, isFalse);
    first.handleExternalCacheHint('invalidate');
    pin.release();
    pin.release();
    expect(
      (await second.read(resource: next, remote: source, forceRefresh: true)).localReady,
      isTrue,
    );
    final disk = CacheDatabase(NativeDatabase(file));
    expect(await disk.entry(pinned.keyFor(_scope())), isNull);
    await disk.close();
  });

  test(
    'read retries are bounded and publish refreshing/stale/error for an existing view',
    () async {
      final delays = <Duration>[];
      final cache = await open(delays: delays);
      addTearDown(cache.closeScope);
      final source = _Source(_scope());
      final resource = _resource('one');
      await cache.read(resource: resource, remote: source);
      source.error = const ApiFailure(code: 'SERVER_ERROR', statusCode: 503);
      final states = <CacheView<Map<String, Object?>>>[];
      await expectLater(
        cache.read(resource: resource, remote: source, preserveCurrent: true, onView: states.add),
        throwsA(isA<ApiFailure>()),
      );
      expect(source.validations, 3);
      expect(delays, hasLength(2));
      expect(delays[0].inMilliseconds, inInclusiveRange(500, 600));
      expect(delays[1].inMilliseconds, inInclusiveRange(1500, 1600));
      expect(states.map((state) => state.freshness), [
        CacheFreshness.refreshing,
        CacheFreshness.stale,
      ]);
      expect(states.last.error, same(source.error));
      expect(cache.isOffline, isFalse);
      source.error = const ApiFailure(code: 'PERMISSION_DENIED', statusCode: 403);
      states.clear();
      await expectLater(
        cache.read(resource: resource, remote: source, preserveCurrent: true, onView: states.add),
        throwsA(isA<ApiFailure>()),
      );
      expect(states.last.freshness, CacheFreshness.blocked);
      expect(states.last.data, isNull);
      expect(delays, hasLength(2));
    },
  );

  test('broadcast payload only includes registered public categories', () {
    final hint = decodeCacheHint(encodeCacheHint('invalidate', {'settings:profile'}))!;
    expect(hint.$1, 'invalidate');
    expect(hint.$2, {'settings:profile'});
    final material = decodeCacheHint(encodeCacheHint('invalidate', {'material:private-id'}))!;
    expect(material.$1, 'invalidate');
    expect(material.$2, {'material:*'});
    final unknown = decodeCacheHint(encodeCacheHint('invalidate', {'unregistered:private-id'}))!;
    expect(unknown.$1, 'invalidate');
    expect(unknown.$2, isNull);
    expect(decodeCacheHint('{"type":"invalidate","tags":["private-id"]}'), isNull);
  });
}

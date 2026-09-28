import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_database.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_partition_lock.dart';
import 'package:sqlite3/sqlite3.dart';

Future<CachePublishStatus> publishAt(
  CacheDatabase database,
  CacheReadSnapshot snapshot,
  String key,
  String text, {
  String tag = 'material:one',
  Set<String> protectedKeys = const {},
  CacheGrant? grant,
  CacheVersion version = const CacheVersion(
    resource: '7',
    representation: 'novel-v1',
    artifact: 'sha-a',
  ),
}) => database.publish(
  expectedStorageEpoch: snapshot.storageEpoch,
  entryKey: key,
  kind: 'material_content',
  sourceBinding: 'material:one:chapter:one',
  projection: 'novel-reading-v1',
  version: version,
  payload: {'text': text},
  expectedInvalidations: {tag: snapshot.invalidations[tag] ?? 0},
  expectedPublicationEpoch: snapshot.entry?.publicationEpoch ?? 0,
  protectedEntryKeys: protectedKeys,
  grant: grant,
);

void main() {
  test('corrupt text is observed without mutation and discarded by locked CAS', () async {
    var corruptions = 0;
    final database = CacheDatabase(NativeDatabase.memory(), onCorruptEntry: () => corruptions++);
    addTearDown(database.close);
    final start = await database.snapshot('chapter', {'material:one'});
    final grant = CacheGrant(
      scopeBinding: 'confirmed-session',
      resourceKey: 'chapter',
      version: const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
      expiresAt: DateTime.utc(2030),
      serverTime: DateTime.utc(2029),
      securityEpoch: 3,
      authzVersion: 4,
    );
    expect(
      await publishAt(database, start, 'chapter', 'saved', grant: grant),
      CachePublishStatus.published,
    );
    await database.customStatement(
      'UPDATE cache_entries SET payload_json = ? WHERE entry_key = ?',
      ['{"text":"sawed"}', cacheEntryKey('chapter', grant.version)],
    );
    expect(await database.entry('chapter'), isNull);
    expect(corruptions, 0);
    expect(await database.customSelect('SELECT * FROM cache_dependencies').get(), isNotEmpty);
    expect(await database.customSelect('SELECT * FROM offline_grants').get(), isNotEmpty);
    final damaged = await database.snapshot('chapter', {'material:one'});
    expect(damaged.entry, isNull);
    expect(damaged.grant, isNull);
    expect(damaged.corruptPublicationEpoch, isNotNull);
    expect(
      await withCachePartitionPublishLock(
        'test-corrupt-text',
        () => database.deleteEntryIfCurrent(
          expectedStorageEpoch: damaged.storageEpoch,
          entryKey: 'chapter',
          expectedPublicationEpoch: damaged.corruptPublicationEpoch!,
          expectedPayloadHash: damaged.corruptPayloadHash,
          expectedPayloadJson: damaged.corruptPayloadJson,
        ),
      ),
      isTrue,
    );
    expect(await database.customSelect('SELECT * FROM cache_dependencies').get(), isEmpty);
    expect(await database.customSelect('SELECT * FROM offline_grants').get(), isEmpty);

    final next = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, next, 'chapter', 'repaired'), CachePublishStatus.published);
    await database.customStatement(
      'UPDATE cache_entries SET version_json = ? WHERE entry_key = ?',
      ['{', cacheEntryKey('chapter', grant.version)],
    );
    expect(await database.entry('chapter'), isNull);
    final invalidVersion = await database.snapshot('chapter', {'material:one'});
    expect(invalidVersion.corruptPublicationEpoch, isNotNull);
    expect(
      await withCachePartitionPublishLock(
        'test-corrupt-text',
        () => database.deleteEntryIfCurrent(
          expectedStorageEpoch: invalidVersion.storageEpoch,
          entryKey: 'chapter',
          expectedPublicationEpoch: invalidVersion.corruptPublicationEpoch!,
          expectedPayloadHash: invalidVersion.corruptPayloadHash,
          expectedPayloadJson: invalidVersion.corruptPayloadJson,
        ),
      ),
      isTrue,
    );
    expect(corruptions, 0);
  });

  for (final schema in [1, 2, 3]) {
    test('schema $schema text and audio remain readable after schema 4 migration', () async {
      final directory = await Directory.systemTemp.createTemp('haruka-cache-migration-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final original = CacheDatabase(NativeDatabase(file));
      final start = await original.snapshot('chapter', {'material:one'});
      expect(await publishAt(original, start, 'chapter', '朝の光'), CachePublishStatus.published);
      if (schema == 3) {
        final broken = await original.snapshot('broken', {'material:bad'});
        expect(
          await publishAt(original, broken, 'broken', 'discard me', tag: 'material:bad'),
          CachePublishStatus.published,
        );
      }
      await original.customStatement(
        '''INSERT INTO local_assets
      (asset_key, version, format, sha256, actual_bytes, state, blob_ref, last_access_at, created_at, updated_at)
      VALUES ('audio', 'v1', 'audio/wav', 'hash', 5, 'ready', 'blob', 'old', 'created', 'updated')''',
      );
      await original.close();

      final legacy = sqlite3.open(file.path);
      final exact = cacheEntryKey(
        'chapter',
        const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
      );
      legacy.execute('UPDATE cache_entries SET entry_key = ? WHERE entry_key = ?', [
        'chapter',
        exact,
      ]);
      legacy.execute('UPDATE cache_dependencies SET entry_key = ? WHERE entry_key = ?', [
        'chapter',
        exact,
      ]);
      legacy.execute('UPDATE offline_grants SET entry_key = ? WHERE entry_key = ?', [
        'chapter',
        exact,
      ]);
      if (schema == 3) {
        final brokenExact = cacheEntryKey(
          'broken',
          const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
        );
        legacy.execute(
          'UPDATE cache_entries SET entry_key = ?, version_json = ? WHERE entry_key = ?',
          ['broken', '{', brokenExact],
        );
        legacy.execute('UPDATE cache_dependencies SET entry_key = ? WHERE entry_key = ?', [
          'broken',
          brokenExact,
        ]);
      }
      legacy.execute('DROP TABLE cache_heads');
      if (schema == 1) legacy.execute('ALTER TABLE cache_entries DROP COLUMN payload_sha256');
      if (schema < 3) legacy.execute('ALTER TABLE local_assets DROP COLUMN last_access_at');
      legacy.execute('UPDATE cache_control SET schema_version = $schema');
      legacy.execute('PRAGMA user_version = $schema');
      legacy.close();

      final migrated = CacheDatabase(NativeDatabase(file));
      addTearDown(migrated.close);
      expect((await migrated.entry('chapter'))?.payload['text'], '朝の光');
      if (schema == 3) {
        expect(await migrated.entry('broken'), isNull);
        expect(
          (await migrated
              .customSelect("SELECT entry_key FROM cache_dependencies WHERE entry_key = 'broken'")
              .get()),
          isEmpty,
        );
      }
      final row =
          (await migrated
                  .customSelect('SELECT schema_version FROM cache_control WHERE id = 1')
                  .get())
              .single;
      expect(row.read<int>('schema_version'), 4);
      final audio =
          (await migrated
                  .customSelect('SELECT last_access_at, actual_bytes FROM local_assets')
                  .get())
              .single;
      expect(audio.read<String>('last_access_at'), schema < 3 ? 'updated' : 'old');
      expect(audio.read<int>('actual_bytes'), 5);
    });
  }

  test('published text is guarded by storage and dependency epochs', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final start = await database.snapshot('entry', {'material:one'});
    expect(start.entry, isNull);
    final version = CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a');
    final first = await database.publish(
      expectedStorageEpoch: start.storageEpoch,
      entryKey: 'entry',
      kind: 'material_content',
      sourceBinding: 'material:one:chapter:one',
      projection: 'novel-reading-v1',
      version: version,
      payload: {'text': '朝の光'},
      expectedInvalidations: start.invalidations,
      expectedPublicationEpoch: 0,
    );
    expect(first, CachePublishStatus.published);
    expect((await database.entry('entry'))?.payload['text'], '朝の光');

    await database.invalidate({'material:one'});
    expect(await database.entry('entry'), isNull);
    final stale = await database.publish(
      expectedStorageEpoch: start.storageEpoch,
      entryKey: 'entry',
      kind: 'material_content',
      sourceBinding: 'material:one:chapter:one',
      projection: 'novel-reading-v1',
      version: version,
      payload: {'text': 'old response'},
      expectedInvalidations: start.invalidations,
      expectedPublicationEpoch: 0,
    );
    expect(stale, CachePublishStatus.stale);
    expect(await database.entry('entry'), isNull);

    final beforeClear = await database.snapshot('entry', {'material:one'});
    final nextEpoch = await database.clearText();
    expect(nextEpoch, isNot(beforeClear.storageEpoch));
    final afterClear = await database.publish(
      expectedStorageEpoch: beforeClear.storageEpoch,
      entryKey: 'entry',
      kind: 'material_content',
      sourceBinding: 'material:one:chapter:one',
      projection: 'novel-reading-v1',
      version: version,
      payload: {'text': 'late response'},
      expectedInvalidations: beforeClear.invalidations,
      expectedPublicationEpoch: 0,
    );
    expect(afterClear, CachePublishStatus.stale);
  });

  test('publication CAS rejects a second writer from the same snapshot', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final snapshot = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, snapshot, 'chapter', 'first'), CachePublishStatus.published);
    expect(await publishAt(database, snapshot, 'chapter', 'second'), CachePublishStatus.stale);
    expect((await database.entry('chapter'))?.payload['text'], 'first');
    final firstPublication = (await database.entry('chapter'))!.publicationEpoch;
    final fresh = await database.snapshot('chapter', {'material:one'});
    expect(
      await publishAt(
        database,
        fresh,
        'chapter',
        'revised',
        version: const CacheVersion(resource: '8', representation: 'novel-v1', artifact: 'sha-b'),
      ),
      CachePublishStatus.published,
    );
    expect((await database.entry('chapter'))?.publicationEpoch, isNot(firstPublication));
    expect(
      (await database.entry(
        'chapter',
        version: const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
      ))?.payload['text'],
      'first',
    );
    expect((await database.entry('chapter'))?.payload['text'], 'revised');
  });

  test('offline grant follows the exact publication and is removed on revocation', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final snapshot = await database.snapshot('chapter', {'material:one'});
    final grant = CacheGrant(
      scopeBinding: 'confirmed-session',
      resourceKey: 'chapter',
      version: const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
      expiresAt: DateTime.utc(2030),
      serverTime: DateTime.utc(2029),
      securityEpoch: 3,
      authzVersion: 4,
    );
    expect(
      await publishAt(database, snapshot, 'chapter', 'saved', grant: grant),
      CachePublishStatus.published,
    );
    final rows = await database.customSelect('SELECT grant_json FROM offline_grants').get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('grant_json'), contains('confirmed-session'));
    final current = await database.snapshot('chapter', {'material:one'});
    expect(
      await database.replaceGrantIfCurrent(
        expectedStorageEpoch: current.storageEpoch,
        entryKey: 'chapter',
        expectedPublicationEpoch: current.entry!.publicationEpoch,
        expectedInvalidations: current.invalidations,
        expectedPayloadHash: current.entry!.payloadHash,
        expectedVersion: current.entry!.version,
        grant: null,
      ),
      isTrue,
    );
    expect(await database.customSelect('SELECT entry_key FROM offline_grants').get(), isEmpty);
  });

  test('stale deletion cannot remove another writer publication or a new epoch', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final initial = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, initial, 'chapter', 'first'), CachePublishStatus.published);
    final old = await database.snapshot('chapter', {'material:one'});
    expect(
      await publishAt(
        database,
        old,
        'chapter',
        'second',
        version: const CacheVersion(resource: '8', representation: 'novel-v1', artifact: 'sha-b'),
      ),
      CachePublishStatus.published,
    );
    expect(
      await database.deleteEntryIfCurrent(
        expectedStorageEpoch: old.storageEpoch,
        entryKey: 'chapter',
        expectedPublicationEpoch: old.entry!.publicationEpoch,
      ),
      isFalse,
    );
    expect((await database.entry('chapter'))?.payload['text'], 'second');
    final current = await database.snapshot('chapter', {'material:one'});
    await database.clearText();
    expect(
      await database.deleteEntryIfCurrent(
        expectedStorageEpoch: current.storageEpoch,
        entryKey: 'chapter',
        expectedPublicationEpoch: current.entry!.publicationEpoch,
      ),
      isFalse,
    );
  });

  test('quota failure leaves existing publication intact and never reports ready', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.setQuotas(textBytes: 30);
    final first = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, first, 'chapter', 'ok'), CachePublishStatus.published);
    final before = await database.snapshot('chapter', {'material:one'});
    expect(
      await publishAt(
        database,
        before,
        'chapter',
        'a much longer replacement than the quota',
        version: const CacheVersion(resource: '8', representation: 'novel-v1', artifact: 'sha-b'),
      ),
      CachePublishStatus.quotaExceeded,
    );
    expect((await database.entry('chapter'))?.payload['text'], 'ok');
    expect((await database.entry('chapter'))?.publicationEpoch, before.entry!.publicationEpoch);
    expect(() => database.setQuotas(textBytes: -1), throwsArgumentError);
  });

  test('text LRU evicts a free copy but preserves a pinned copy and its dependencies', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.setQuotas(textBytes: 25);
    final first = await database.snapshot('first', {'material:one'});
    expect(await publishAt(database, first, 'first', 'saved'), CachePublishStatus.published);
    final second = await database.snapshot('second', {'material:two'});
    expect(
      await publishAt(
        database,
        second,
        'second',
        'newer',
        tag: 'material:two',
        protectedKeys: {'first'},
      ),
      CachePublishStatus.quotaExceeded,
    );
    expect((await database.entry('first'))?.payload['text'], 'saved');
    expect(await database.entry('second'), isNull);
    expect(
      await publishAt(database, second, 'second', 'newer', tag: 'material:two'),
      CachePublishStatus.published,
    );
    expect(await database.entry('first'), isNull);
    expect((await database.entry('second'))?.payload['text'], 'newer');
    final dependency = await database
        .customSelect('SELECT entry_key FROM cache_dependencies')
        .get();
    expect(
      dependency.where(
        (row) =>
            row.read<String>('entry_key') ==
            cacheEntryKey(
              'first',
              const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
            ),
      ),
      isEmpty,
    );
  });

  test('invalidation removes only entries depending on the changed source', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final chapter = await database.snapshot('chapter', {'material:one'});
    final other = await database.snapshot('other', {'material:two'});
    expect(await publishAt(database, chapter, 'chapter', 'one'), CachePublishStatus.published);
    expect(
      await publishAt(database, other, 'other', 'two', tag: 'material:two'),
      CachePublishStatus.published,
    );
    await database.invalidate({'material:one'});
    expect(await database.entry('chapter'), isNull);
    expect((await database.entry('other'))?.payload['text'], 'two');
    expect((await database.invalidationEpochs({'material:one'}))['material:one'], 1);
  });

  test('pinned invalidation revokes the head and grant before deferred byte removal', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final initial = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, initial, 'chapter', 'saved'), CachePublishStatus.published);
    final exact =
        initial.entry?.entryKey ??
        cacheEntryKey(
          'chapter',
          const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
        );
    await database.invalidate({'material:one'}, acquireEviction: (_, _) async => null);
    expect(await database.entry('chapter'), isNull);
    expect((await database.snapshot('chapter', {'material:one'})).entry, isNull);
    expect(
      (await database.customSelect('SELECT entry_key FROM cache_entries').get()).single
          .read<String>('entry_key'),
      exact,
    );
    await database.pruneRetiredEntries(acquireEviction: (_, _) async => () {});
    expect(await database.customSelect('SELECT entry_key FROM cache_entries').get(), isEmpty);
  });

  test('a new required dependency can retire an old head and publish online', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final initial = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, initial, 'chapter', 'saved'), CachePublishStatus.published);
    final incomplete = await database.snapshot('chapter', {'material:one', 'material:two'});
    expect(incomplete.dependenciesCurrent, isFalse);
    expect(incomplete.entry, isNull);
    expect(incomplete.grant, isNull);
    expect(
      await database.publish(
        expectedStorageEpoch: incomplete.storageEpoch,
        entryKey: 'chapter',
        kind: 'material_content',
        sourceBinding: 'material:one:chapter:one',
        projection: 'novel-reading-v1',
        version: const CacheVersion(resource: '7', representation: 'novel-v1', artifact: 'sha-a'),
        payload: {'text': 'saved'},
        expectedInvalidations: incomplete.invalidations,
        expectedPublicationEpoch: 0,
      ),
      CachePublishStatus.published,
    );
    expect((await database.snapshot('chapter', {'material:one', 'material:two'})).entry, isNotNull);
  });

  test('a valid version JSON cannot impersonate another exact entry key', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final initial = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, initial, 'chapter', 'saved'), CachePublishStatus.published);
    const altered = CacheVersion(resource: 'other', representation: 'novel-v1', artifact: 'sha-a');
    await database.customStatement('UPDATE cache_entries SET version_json = ?', [
      jsonEncode(altered.toJson()),
    ]);
    expect(await database.entry('chapter'), isNull);
    final damaged = await database.snapshot('chapter', {'material:one'});
    expect(damaged.entry, isNull);
    expect(damaged.corruptPublicationEpoch, isNotNull);
  });

  test('clear changes epoch and removes entries without resetting source invalidation', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final initial = await database.snapshot('chapter', {'material:one'});
    expect(await publishAt(database, initial, 'chapter', 'saved'), CachePublishStatus.published);
    await database.invalidate({'material:one'});
    final beforeClear = await database.snapshot('chapter', {'material:one'});
    final nextEpoch = await database.clearText();
    expect(nextEpoch, isNot(beforeClear.storageEpoch));
    expect(await database.entry('chapter'), isNull);
    expect((await database.invalidationEpochs({'material:one'}))['material:one'], 1);
    expect(await publishAt(database, beforeClear, 'chapter', 'late'), CachePublishStatus.stale);
  });

  test('audio reservations share two slots and quota; stale epoch cannot publish', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.setQuotas(audioBytes: 10);
    final epoch = await database.storageEpoch();
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'one',
        assetKey: 'asset-one',
        reserveBytes: 6,
      ),
      isTrue,
    );
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'too-large',
        assetKey: 'asset-two',
        reserveBytes: 5,
      ),
      isFalse,
    );
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'two',
        assetKey: 'asset-two',
        reserveBytes: 0,
      ),
      isTrue,
    );
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'three',
        assetKey: 'asset-three',
        reserveBytes: 0,
      ),
      isFalse,
    );
    expect(
      await database.reserveAudioChunk(
        expectedStorageEpoch: epoch,
        operationId: 'two',
        additionalBytes: 4,
      ),
      isTrue,
    );
    expect(
      await database.reserveAudioChunk(
        expectedStorageEpoch: epoch,
        operationId: 'two',
        additionalBytes: 1,
      ),
      isFalse,
    );
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const reference = 'ready-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect(
      await database.publishAudioReady(
        expectedStorageEpoch: epoch,
        operationId: 'one',
        assetKey: 'asset-one',
        version: 'v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        actualBytes: 6,
        readyReference: reference,
      ),
      isTrue,
    );
    expect((await database.audioAsset('asset-one'))?.bytes, 6);
    await database.clearText();
    expect(
      await database.publishAudioReady(
        expectedStorageEpoch: epoch,
        operationId: 'two',
        assetKey: 'asset-two',
        version: 'v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        actualBytes: 4,
        readyReference: reference,
      ),
      isFalse,
    );
  });

  test('text clear retires old download reservations but preserves ready audio', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.setQuotas(audioBytes: 10);
    final oldEpoch = await database.storageEpoch();
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const readyRef = 'ready-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: 'ready-owner',
        assetKey: 'ready-speech',
        reserveBytes: 2,
        stagingReference: 'stage-ready',
      ),
      isTrue,
    );
    expect(
      await database.publishAudioReady(
        expectedStorageEpoch: oldEpoch,
        operationId: 'ready-owner',
        assetKey: 'ready-speech',
        version: 'v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        actualBytes: 2,
        readyReference: readyRef,
      ),
      isTrue,
    );
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-stage',
        assetKey: 'pending-speech',
        reserveBytes: 6,
        stagingReference: 'stage-old',
      ),
      isTrue,
    );
    final nextEpoch = await database.clearText();
    expect(await database.clearState(), 'pending');
    expect((await database.audioAsset('ready-speech'))?.isReady, isTrue);
    expect((await database.usage()).audioBytes, 8);
    expect((await database.usage()).activeDownloads, 0);
    final retired = (await database.audioOperationsForAsset('pending-speech')).single;
    expect(retired.isDeleting, isTrue);
    expect(retired.reference, 'stage-old');
    expect(await database.isAudioOperationCurrent(oldEpoch, 'old-stage'), isFalse);
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: nextEpoch,
        operationId: 'same-key',
        assetKey: 'pending-speech',
        reserveBytes: 1,
        allowDuringPending: true,
      ),
      isFalse,
    );
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: nextEpoch,
        operationId: 'other-key',
        assetKey: 'other-speech',
        reserveBytes: 2,
        allowDuringPending: true,
        stagingReference: 'stage-other',
      ),
      isTrue,
    );
    expect(
      await database.isAudioOperationCurrent(nextEpoch, 'other-key', allowDuringPending: true),
      isTrue,
    );
    expect(
      await database.completeAudioOperationDeletion(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-stage',
        expectedReference: 'wrong-stage',
      ),
      isFalse,
    );
    expect(
      await database.reconcileRetiredAudioOperation(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-stage',
        expectedReference: 'stage-old',
        remainingReference: 'ready-retired',
        actualBytes: 2,
      ),
      isTrue,
    );
    expect((await database.usage()).audioBytes, 6);
    expect(
      await database.completeAudioOperationDeletion(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-stage',
        expectedReference: 'stage-old',
      ),
      isFalse,
    );
    expect(
      await database.completeAudioOperationDeletion(
        expectedStorageEpoch: oldEpoch,
        operationId: 'old-stage',
        expectedReference: 'ready-retired',
      ),
      isTrue,
    );
    expect(await database.finishClearAll(expectedStorageEpoch: nextEpoch), 0);
    expect(await database.clearState(), 'ready');
    expect((await database.usage()).audioBytes, 4);
  });

  test('same audio asset cannot reserve two concurrent operation rows', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final epoch = await database.storageEpoch();
    final admitted = await Future.wait([
      database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'first',
        assetKey: 'same-asset',
        reserveBytes: 1,
      ),
      database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'second',
        assetKey: 'same-asset',
        reserveBytes: 1,
      ),
    ]);
    expect(admitted.where((accepted) => accepted), hasLength(1));
    expect(await database.hasPendingAudioForAsset('same-asset'), isTrue);
    expect(await database.audioOperationsForAsset('same-asset'), hasLength(1));
  });

  test('a stale text-clear finisher cannot rewrite a newer clear state', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final oldEpoch = await database.clearText();
    final newEpoch = await database.beginClearAll();
    expect(newEpoch, isNot(oldEpoch));
    expect(await database.clearState(), 'clearing');
    await expectLater(
      database.finishClearAll(expectedStorageEpoch: oldEpoch),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'storage_epoch_changed'),
      ),
    );
    expect(await database.finishPendingCleanup(expectedStorageEpoch: oldEpoch), isFalse);
    expect(await database.finishPendingCleanup(expectedStorageEpoch: newEpoch), isFalse);
    expect(await database.clearState(), 'clearing');
  });

  test('full clear fences publications and retains failed audio deletion for retry', () async {
    final database = CacheDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final epoch = await database.storageEpoch();
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const reference = 'ready-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: epoch,
        operationId: 'download',
        assetKey: 'speech',
        reserveBytes: 4,
      ),
      isTrue,
    );
    expect(
      await database.publishAudioReady(
        expectedStorageEpoch: epoch,
        operationId: 'download',
        assetKey: 'speech',
        version: 'v1',
        format: 'audio/mpeg',
        sha256Hex: digest,
        actualBytes: 4,
        readyReference: reference,
      ),
      isTrue,
    );
    final next = await database.beginClearAll();
    expect(next, isNot(epoch));
    expect(await database.audioAsset('speech'), isNull);
    expect(await database.pendingAudioDeletions(), [reference]);
    expect(await database.finishClearAll(expectedStorageEpoch: next), 1);
    expect(await database.clearState(), 'pending');
    expect(
      await database.beginAudioOperation(
        expectedStorageEpoch: next,
        operationId: 'new-download',
        assetKey: 'new-speech',
        reserveBytes: 1,
      ),
      isFalse,
    );
    await database.completeAudioDeletion(reference);
    expect(await database.finishClearAll(expectedStorageEpoch: next), 0);
    expect(await database.clearState(), 'ready');
  });
}

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'cache_models.dart';

String _epoch() {
  final random = Random.secure();
  return List<int>.generate(
    24,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

int _publicationId() {
  final random = Random.secure();
  return random.nextInt(1 << 26) * (1 << 26) + random.nextInt(1 << 26) + 1;
}

final class StoredCacheEntry {
  const StoredCacheEntry({
    required this.entryKey,
    required this.kind,
    required this.payload,
    required this.version,
    required this.sourceBinding,
    required this.projection,
    required this.verifiedAt,
    required this.publicationEpoch,
    required this.sizeBytes,
    required this.payloadHash,
  });
  final String entryKey;
  final String kind;
  final Map<String, Object?> payload;
  final CacheVersion version;
  final String sourceBinding;
  final String projection;
  final DateTime verifiedAt;
  final int publicationEpoch;
  final int sizeBytes;
  final String payloadHash;
}

final class CacheReadSnapshot {
  const CacheReadSnapshot(
    this.storageEpoch,
    this.entry,
    this.invalidations, {
    this.grant,
    this.resolvedEntryKey,
    this.corruptEntryKey,
    this.corruptPublicationEpoch,
    this.corruptPayloadHash,
    this.corruptPayloadJson,
    this.dependenciesCurrent = true,
  });
  final String storageEpoch;
  final StoredCacheEntry? entry;
  final Map<String, int> invalidations;
  final CacheGrant? grant;
  final String? resolvedEntryKey;
  final String? corruptEntryKey;
  final int? corruptPublicationEpoch;
  final String? corruptPayloadHash;
  final String? corruptPayloadJson;
  final bool dependenciesCurrent;
}

final class CacheSchemaTooNew implements Exception {
  const CacheSchemaTooNew();

  // Drift's Web worker serializes remote exceptions as strings.
  @override
  String toString() => 'HARUKA_CACHE_SCHEMA_TOO_NEW';
}

enum CachePublishStatus { published, quotaExceeded, stale, deferred }

final class StoredAudioAsset {
  const StoredAudioAsset({
    required this.assetKey,
    required this.version,
    required this.format,
    required this.sha256,
    required this.bytes,
    required this.reference,
    this.isReady = true,
    this.isDeleting = false,
  });

  final String assetKey;
  final String version;
  final String format;
  final String sha256;
  final int bytes;
  final String reference;
  final bool isReady;
  final bool isDeleting;
}

final class StoredAudioOperation {
  const StoredAudioOperation(
    this.operationId,
    this.storageEpoch,
    this.reference, {
    this.assetKey = '',
    this.state = 'staging',
  });
  final String operationId;
  final String storageEpoch;
  final String reference;
  final String assetKey;
  final String state;
  bool get isDeleting => state == 'deleting';
}

final class CacheUsage {
  const CacheUsage({
    required this.textBytes,
    required this.audioBytes,
    required this.textQuotaBytes,
    required this.audioQuotaBytes,
    required this.textEntries,
    required this.audioAssets,
    required this.activeDownloads,
  });
  final int textBytes;
  final int audioBytes;
  final int textQuotaBytes;
  final int audioQuotaBytes;
  final int textEntries;
  final int audioAssets;
  final int activeDownloads;
}

/// Scope-local Drift index. A separate file/database is opened per account partition.
/// No physical foreign keys are used; all related changes share a transaction.
final class CacheDatabase extends GeneratedDatabase {
  CacheDatabase(super.executor, {this.onCorruptEntry, this.onMigration, this.onEvicted});

  final void Function()? onCorruptEntry;
  final void Function()? onMigration;
  final void Function()? onEvicted;

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Drift only invokes onUpgrade when the stored version is lower. A
      // newer index must be refused before any normal cache query or write.
      if ((details.versionBefore ?? 0) > schemaVersion) {
        throw const CacheSchemaTooNew();
      }
    },
    onCreate: (m) async {
      await customStatement('''
        CREATE TABLE cache_control (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          storage_epoch TEXT NOT NULL,
          schema_version INTEGER NOT NULL,
          clear_state TEXT NOT NULL,
          text_quota_bytes INTEGER NOT NULL,
          audio_quota_bytes INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE cache_entries (
          entry_key TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          source_binding TEXT NOT NULL,
          projection TEXT NOT NULL,
          version_json TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          payload_sha256 TEXT NOT NULL,
          size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
          publication_epoch INTEGER NOT NULL,
          verified_at TEXT NOT NULL,
          last_access_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE cache_heads (
          logical_key TEXT PRIMARY KEY,
          entry_key TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE cache_invalidations (
          tag TEXT PRIMARY KEY,
          epoch INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE cache_dependencies (
          entry_key TEXT NOT NULL,
          tag TEXT NOT NULL,
          invalidation_epoch INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(entry_key, tag)
        )
      ''');
      await customStatement('''
        CREATE TABLE offline_grants (
          entry_key TEXT PRIMARY KEY,
          grant_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE local_assets (
          asset_key TEXT PRIMARY KEY,
          version TEXT NOT NULL,
          format TEXT NOT NULL,
          sha256 TEXT NOT NULL,
          expected_bytes INTEGER,
          actual_bytes INTEGER NOT NULL DEFAULT 0,
          state TEXT NOT NULL,
          blob_ref TEXT NOT NULL,
          last_access_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE local_operations (
          operation_id TEXT PRIMARY KEY,
          storage_epoch TEXT NOT NULL,
          asset_key TEXT NOT NULL,
          state TEXT NOT NULL,
          reserved_bytes INTEGER NOT NULL DEFAULT 0,
          actual_bytes INTEGER NOT NULL DEFAULT 0,
          blob_ref TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await customStatement(
        'CREATE INDEX cache_entries_last_access ON cache_entries(last_access_at)',
      );
      await customStatement('CREATE INDEX cache_dependencies_tag ON cache_dependencies(tag)');
      final now = DateTime.now().toUtc().toIso8601String();
      await customStatement(
        'INSERT INTO cache_control VALUES (1, ?, 4, ?, 100000000, 500000000, ?, ?)',
        [_epoch(), 'ready', now, now],
      );
    },
    onUpgrade: (m, from, to) async {
      if (from > schemaVersion) throw const CacheSchemaTooNew();
      if (from < 1 || to != 4) {
        throw StateError('Unsupported cache schema migration $from -> $to');
      }
      await transaction(() async {
        if (from == 1) {
          await customStatement(
            "ALTER TABLE cache_entries ADD COLUMN payload_sha256 TEXT NOT NULL DEFAULT ''",
          );
          final rows = await customSelect('SELECT entry_key, payload_json FROM cache_entries')
              .get();
          for (final row in rows) {
            final payload = row.read<String>('payload_json');
            await customStatement(
              'UPDATE cache_entries SET payload_sha256 = ? WHERE entry_key = ?',
              [sha256.convert(utf8.encode(payload)).toString(), row.read<String>('entry_key')],
            );
          }
        }
        if (from < 3) {
          await customStatement(
            "ALTER TABLE local_assets ADD COLUMN last_access_at TEXT NOT NULL DEFAULT ''",
          );
          await customStatement('UPDATE local_assets SET last_access_at = updated_at');
        }
        await customStatement('''
          CREATE TABLE cache_heads (
            logical_key TEXT PRIMARY KEY,
            entry_key TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        final legacy = await customSelect('SELECT entry_key, version_json FROM cache_entries')
            .get();
        for (final row in legacy) {
          final logical = row.read<String>('entry_key');
          late final CacheVersion version;
          try {
            version = CacheVersion.fromJson(
              (jsonDecode(row.read<String>('version_json')) as Map).cast<String, Object?>(),
            );
          } on Object {
            await customStatement('DELETE FROM cache_entries WHERE entry_key = ?', [logical]);
            await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [logical]);
            await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [logical]);
            try {
              onCorruptEntry?.call();
            } on Object {
              /* Telemetry must not abort migration. */
            }
            continue;
          }
          final exact = cacheEntryKey(logical, version);
          await customStatement('UPDATE cache_entries SET entry_key = ? WHERE entry_key = ?', [
            exact,
            logical,
          ]);
          await customStatement('UPDATE cache_dependencies SET entry_key = ? WHERE entry_key = ?', [
            exact,
            logical,
          ]);
          await customStatement('UPDATE offline_grants SET entry_key = ? WHERE entry_key = ?', [
            exact,
            logical,
          ]);
          await customStatement(
            'INSERT INTO cache_heads(logical_key, entry_key, updated_at) VALUES (?, ?, ?)',
            [logical, exact, DateTime.now().toUtc().toIso8601String()],
          );
        }
        await customStatement(
          'UPDATE cache_control SET schema_version = 4, updated_at = ? WHERE id = 1',
          [DateTime.now().toUtc().toIso8601String()],
        );
      });
      onMigration?.call();
    },
  );

  Future<String> storageEpoch() async {
    final rows = await customSelect(
      'SELECT storage_epoch, schema_version FROM cache_control WHERE id = 1',
    ).get();
    if (rows.length != 1) throw StateError('Cache control is missing');
    if (rows.single.read<int>('schema_version') > schemaVersion) throw const CacheSchemaTooNew();
    return rows.single.read<String>('storage_epoch');
  }

  Future<String?> headEntryKey(String logicalKey, {Set<String>? requiredTags}) async {
    final exact = await _headEntryKeyRaw(logicalKey);
    if (exact == null) return null;
    return await _storedDependenciesCurrent(exact, requiredTags: requiredTags) ? exact : null;
  }

  Future<String?> _headEntryKeyRaw(String logicalKey) async {
    final rows = await customSelect(
      'SELECT entry_key FROM cache_heads WHERE logical_key = ?',
      variables: [Variable.withString(logicalKey)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.single.read<String>('entry_key');
  }

  Future<bool> _storedDependenciesCurrent(String exactKey, {Set<String>? requiredTags}) async {
    final rows = await customSelect(
      'SELECT d.tag, d.invalidation_epoch, COALESCE(i.epoch, 0) AS current_epoch '
      'FROM cache_dependencies d LEFT JOIN cache_invalidations i ON i.tag = d.tag '
      'WHERE d.entry_key = ?',
      variables: [Variable.withString(exactKey)],
    ).get();
    if (requiredTags != null &&
        (rows.length != requiredTags.length ||
            rows.any((row) => !requiredTags.contains(row.read<String>('tag'))))) {
      return false;
    }
    return rows.every(
      (row) => row.read<int>('invalidation_epoch') == row.read<int>('current_epoch'),
    );
  }

  Future<StoredCacheEntry?> entry(String logicalKey, {CacheVersion? version}) async {
    final key = version == null
        ? await headEntryKey(logicalKey)
        : cacheEntryKey(logicalKey, version);
    if (key == null) return null;
    return _entryExact(key, logicalKey: logicalKey);
  }

  Future<StoredCacheEntry?> _entryExact(String key, {required String logicalKey}) async {
    final rows = await customSelect(
      'SELECT * FROM cache_entries WHERE entry_key = ?',
      variables: [Variable.withString(key)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    final payloadJson = row.read<String>('payload_json');
    final payloadHash = row.read<String>('payload_sha256');
    final sizeBytes = row.read<int>('size_bytes');
    Map<String, Object?> payload;
    CacheVersion version;
    DateTime verifiedAt;
    try {
      if (utf8.encode(payloadJson).length != sizeBytes ||
          sha256.convert(utf8.encode(payloadJson)).toString() != payloadHash) {
        throw const FormatException('Cache payload integrity check failed');
      }
      payload = (jsonDecode(payloadJson) as Map).cast<String, Object?>();
      version = CacheVersion.fromJson(
        (jsonDecode(row.read<String>('version_json')) as Map).cast<String, Object?>(),
      );
      if (cacheEntryKey(logicalKey, version) != key) {
        throw const FormatException('Cache version does not match entry identity');
      }
      verifiedAt = DateTime.parse(row.read<String>('verified_at'));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    return StoredCacheEntry(
      entryKey: key,
      kind: row.read<String>('kind'),
      payload: payload,
      version: version,
      sourceBinding: row.read<String>('source_binding'),
      projection: row.read<String>('projection'),
      verifiedAt: verifiedAt,
      publicationEpoch: row.read<int>('publication_epoch'),
      sizeBytes: sizeBytes,
      payloadHash: payloadHash,
    );
  }

  Future<Map<String, int>> invalidationEpochs(Set<String> tags) async {
    final epochs = <String, int>{};
    for (final tag in tags) {
      final rows = await customSelect(
        'SELECT epoch FROM cache_invalidations WHERE tag = ?',
        variables: [Variable.withString(tag)],
      ).get();
      epochs[tag] = rows.isEmpty ? 0 : rows.single.read<int>('epoch');
    }
    return epochs;
  }

  Future<Map<String, int>> allInvalidationEpochs() async {
    final rows = await customSelect('SELECT tag, epoch FROM cache_invalidations').get();
    return {for (final row in rows) row.read<String>('tag'): row.read<int>('epoch')};
  }

  /// One SELECT gives an atomic control/dependency snapshot without acquiring
  /// SQLite's write-intent transaction lock on every foreground read.
  Future<(String, Map<String, int>)> storageState() async {
    final rows = await customSelect(
      'SELECT c.storage_epoch, c.schema_version, i.tag, i.epoch '
      'FROM cache_control c LEFT JOIN cache_invalidations i ON 1 = 1 '
      'WHERE c.id = 1',
    ).get();
    if (rows.isEmpty) throw StateError('Cache control is missing');
    if (rows.first.read<int>('schema_version') > schemaVersion) {
      throw const CacheSchemaTooNew();
    }
    final invalidations = <String, int>{};
    for (final row in rows) {
      final tag = row.readNullable<String>('tag');
      if (tag != null) invalidations[tag] = row.read<int>('epoch');
    }
    return (rows.first.read<String>('storage_epoch'), invalidations);
  }

  Future<CacheReadSnapshot> snapshot(
    String logicalKey,
    Set<String> tags, {
    CacheVersion? version,
  }) => transaction(() async {
    final epoch = await storageEpoch();
    final rawHead = version == null ? await _headEntryKeyRaw(logicalKey) : null;
    final entryKey = version == null
        ? rawHead != null && await _storedDependenciesCurrent(rawHead, requiredTags: tags)
              ? rawHead
              : null
        : cacheEntryKey(logicalKey, version);
    final stored = entryKey == null ? null : await _entryExact(entryKey, logicalKey: logicalKey);
    final invalidations = await invalidationEpochs(tags);
    final dependenciesCurrent =
        !(version == null && rawHead != null && entryKey == null) &&
        (stored == null || await _dependenciesMatch(entryKey!, invalidations));
    int? corruptPublicationEpoch;
    String? corruptPayloadHash;
    String? corruptPayloadJson;
    if (stored == null && entryKey != null) {
      final rows = await customSelect(
        'SELECT publication_epoch, payload_sha256, payload_json FROM cache_entries WHERE entry_key = ?',
        variables: [Variable.withString(entryKey)],
      ).get();
      if (rows.isNotEmpty) {
        corruptPublicationEpoch = rows.single.read<int>('publication_epoch');
        corruptPayloadHash = rows.single.read<String>('payload_sha256');
        corruptPayloadJson = rows.single.read<String>('payload_json');
      }
    }
    return CacheReadSnapshot(
      epoch,
      dependenciesCurrent ? stored : null,
      invalidations,
      grant: dependenciesCurrent && corruptPublicationEpoch == null && entryKey != null
          ? await offlineGrant(entryKey)
          : null,
      resolvedEntryKey: entryKey,
      corruptEntryKey: corruptPublicationEpoch == null ? null : entryKey,
      corruptPublicationEpoch: corruptPublicationEpoch,
      corruptPayloadHash: corruptPayloadHash,
      corruptPayloadJson: corruptPayloadJson,
      dependenciesCurrent: dependenciesCurrent,
    );
  });

  Future<bool> _dependenciesMatch(String exactKey, Map<String, int> expected) async {
    final rows = await customSelect(
      'SELECT tag, invalidation_epoch FROM cache_dependencies WHERE entry_key = ?',
      variables: [Variable.withString(exactKey)],
    ).get();
    if (rows.length != expected.length) return false;
    return rows.every(
      (row) => expected[row.read<String>('tag')] == row.read<int>('invalidation_epoch'),
    );
  }

  Future<bool> _acceptedBodyMatches(
    String exactKey,
    int publication,
    String expectedHash,
    CacheVersion expectedVersion,
  ) async {
    final rows = await customSelect(
      'SELECT publication_epoch, payload_sha256, payload_json, size_bytes, version_json '
      'FROM cache_entries WHERE entry_key = ?',
      variables: [Variable.withString(exactKey)],
    ).get();
    if (rows.isEmpty) return false;
    final row = rows.single;
    final payload = row.read<String>('payload_json');
    if (row.read<int>('publication_epoch') != publication ||
        row.read<String>('payload_sha256') != expectedHash ||
        utf8.encode(payload).length != row.read<int>('size_bytes') ||
        sha256.convert(utf8.encode(payload)).toString() != expectedHash) {
      return false;
    }
    try {
      final version = CacheVersion.fromJson(
        (jsonDecode(row.read<String>('version_json')) as Map).cast<String, Object?>(),
      );
      return jsonEncode(version.toJson()) == jsonEncode(expectedVersion.toJson());
    } on Object {
      return false;
    }
  }

  Future<bool> touchEntryIfCurrent({
    required String expectedStorageEpoch,
    required String entryKey,
    String? exactEntryKey,
    bool requireHead = true,
    required int expectedPublicationEpoch,
    required Map<String, int> expectedInvalidations,
    required String expectedPayloadHash,
    required CacheVersion expectedVersion,
  }) => transaction(() async {
    if (await storageEpoch() != expectedStorageEpoch) return false;
    final epochs = await invalidationEpochs(expectedInvalidations.keys.toSet());
    if (expectedInvalidations.keys.any((tag) => epochs[tag] != expectedInvalidations[tag])) {
      return false;
    }
    final selectedKey = exactEntryKey ?? await headEntryKey(entryKey);
    if (selectedKey == null) return false;
    if (requireHead && await headEntryKey(entryKey) != selectedKey) return false;
    if (!await _dependenciesMatch(selectedKey, epochs) ||
        !await _acceptedBodyMatches(
          selectedKey,
          expectedPublicationEpoch,
          expectedPayloadHash,
          expectedVersion,
        )) {
      return false;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    return await customUpdate(
          'UPDATE cache_entries SET last_access_at = ?, updated_at = ? '
          'WHERE entry_key = ? AND publication_epoch = ?',
          variables: [
            Variable.withString(now),
            Variable.withString(now),
            Variable.withString(selectedKey),
            Variable.withInt(expectedPublicationEpoch),
          ],
        ) ==
        1;
  });

  Future<CacheGrant?> offlineGrant(String entryKey) async {
    final rows = await customSelect(
      'SELECT grant_json FROM offline_grants WHERE entry_key = ?',
      variables: [Variable.withString(entryKey)],
    ).get();
    if (rows.isEmpty) return null;
    try {
      return CacheGrant.fromJson(
        (jsonDecode(rows.single.read<String>('grant_json')) as Map).cast<String, Object?>(),
      );
    } on Object {
      // Malformed local permissions can never authorize display.
      return null;
    }
  }

  Future<void> clearOfflineGrants() => customStatement('DELETE FROM offline_grants');

  Future<bool> deleteEntryIfCurrent({
    required String expectedStorageEpoch,
    required String entryKey,
    String? exactEntryKey,
    bool requireHead = true,
    required int expectedPublicationEpoch,
    String? expectedPayloadHash,
    String? expectedPayloadJson,
  }) => transaction(() async {
    if (await storageEpoch() != expectedStorageEpoch) return false;
    final selectedKey = exactEntryKey ?? await headEntryKey(entryKey);
    if (selectedKey == null) return false;
    if (requireHead && await headEntryKey(entryKey) != selectedKey) return false;
    final rows = await customSelect(
      'SELECT publication_epoch, payload_sha256, payload_json FROM cache_entries WHERE entry_key = ?',
      variables: [Variable.withString(selectedKey)],
    ).get();
    if (rows.isEmpty || rows.single.read<int>('publication_epoch') != expectedPublicationEpoch) {
      return false;
    }
    if ((expectedPayloadHash != null &&
            rows.single.read<String>('payload_sha256') != expectedPayloadHash) ||
        (expectedPayloadJson != null &&
            rows.single.read<String>('payload_json') != expectedPayloadJson)) {
      return false;
    }
    await customStatement('DELETE FROM cache_entries WHERE entry_key = ?', [selectedKey]);
    await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [selectedKey]);
    await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [selectedKey]);
    await customStatement('DELETE FROM cache_heads WHERE logical_key = ? AND entry_key = ?', [
      entryKey,
      selectedKey,
    ]);
    return true;
  });

  Future<CachePublishStatus> publish({
    required String expectedStorageEpoch,
    required String entryKey,
    required String kind,
    required String sourceBinding,
    required String projection,
    required CacheVersion version,
    required Map<String, Object?> payload,
    required Map<String, int> expectedInvalidations,
    required int expectedPublicationEpoch,
    Set<String> protectedEntryKeys = const {},
    Future<void Function()?> Function(String, String?)? acquireEviction,
    CacheGrant? grant,
  }) async {
    final releases = <void Function()>[];
    var evicted = false;
    final exactKey = cacheEntryKey(entryKey, version);
    try {
      final result = await transaction(() async {
        if (await storageEpoch() != expectedStorageEpoch) return CachePublishStatus.stale;
        final epochs = await invalidationEpochs(expectedInvalidations.keys.toSet());
        for (final tag in expectedInvalidations.keys) {
          if (epochs[tag] != expectedInvalidations[tag]) return CachePublishStatus.stale;
        }
        final priorCandidate = await headEntryKey(
          entryKey,
          requiredTags: expectedInvalidations.keys.toSet(),
        );
        final priorKey = priorCandidate != null && await _dependenciesMatch(priorCandidate, epochs)
            ? priorCandidate
            : null;
        final prior = priorKey == null
            ? null
            : (await customSelect(
                'SELECT publication_epoch FROM cache_entries WHERE entry_key = ?',
                variables: [Variable.withString(priorKey)],
              ).get()).firstOrNull;
        if ((prior?.read<int>('publication_epoch') ?? 0) != expectedPublicationEpoch) {
          return CachePublishStatus.stale;
        }
        final now = DateTime.now().toUtc().toIso8601String();
        final payloadJson = jsonEncode(payload);
        final payloadHash = sha256.convert(utf8.encode(payloadJson)).toString();
        final bytes = utf8.encode(payloadJson).length;
        final sameVersionRows = await customSelect(
          'SELECT payload_sha256, payload_json FROM cache_entries WHERE entry_key = ?',
          variables: [Variable.withString(exactKey)],
        ).get();
        if (sameVersionRows.isNotEmpty &&
            (sameVersionRows.single.read<String>('payload_sha256') != payloadHash ||
                sameVersionRows.single.read<String>('payload_json') != payloadJson)) {
          return CachePublishStatus.stale;
        }
        if (await clearState() != 'ready') return CachePublishStatus.deferred;
        if (sameVersionRows.isNotEmpty && priorKey != exactKey && acquireEviction != null) {
          final release = await acquireEviction(exactKey, null);
          if (release == null) return CachePublishStatus.deferred;
          releases.add(release);
        }
        final quota = (await customSelect(
          'SELECT text_quota_bytes FROM cache_control WHERE id = 1',
        ).get()).single.read<int>('text_quota_bytes');
        var used = (await customSelect(
          'SELECT COALESCE(SUM(size_bytes), 0) AS used FROM cache_entries WHERE entry_key != ?',
          variables: [Variable.withString(exactKey)],
        ).get()).single.read<int>('used');
        if (bytes > quota) return CachePublishStatus.quotaExceeded;
        if (used + bytes > quota) {
          final candidates = await customSelect(
            'SELECT entry_key, size_bytes FROM cache_entries WHERE entry_key != ? '
            'ORDER BY last_access_at ASC, entry_key ASC',
            variables: [Variable.withString(exactKey)],
          ).get();
          final evictions = <String>[];
          for (final candidate in candidates) {
            final candidateKey = candidate.read<String>('entry_key');
            if (protectedEntryKeys.contains(candidateKey)) continue;
            final headOwner = await customSelect(
              'SELECT logical_key FROM cache_heads WHERE entry_key = ?',
              variables: [Variable.withString(candidateKey)],
            ).get();
            if (headOwner.isNotEmpty &&
                protectedEntryKeys.contains(headOwner.single.read<String>('logical_key'))) {
              continue;
            }
            if (acquireEviction != null) {
              final release = await acquireEviction(
                candidateKey,
                headOwner.isEmpty ? null : headOwner.single.read<String>('logical_key'),
              );
              if (release == null) continue;
              releases.add(release);
            }
            evictions.add(candidateKey);
            used -= candidate.read<int>('size_bytes');
            if (used + bytes <= quota) break;
          }
          if (used + bytes > quota) return CachePublishStatus.quotaExceeded;
          for (final candidateKey in evictions) {
            await customStatement('DELETE FROM cache_entries WHERE entry_key = ?', [candidateKey]);
            await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [
              candidateKey,
            ]);
            await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [candidateKey]);
            await customStatement('DELETE FROM cache_heads WHERE entry_key = ?', [candidateKey]);
          }
          evicted = evictions.isNotEmpty;
        }
        await customStatement(
          '''
        INSERT INTO cache_entries (
          entry_key, kind, source_binding, projection, version_json, payload_json,
          payload_sha256, size_bytes, publication_epoch, verified_at,
          last_access_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(entry_key) DO UPDATE SET
          publication_epoch = excluded.publication_epoch,
          verified_at = excluded.verified_at, last_access_at = excluded.last_access_at,
          updated_at = excluded.updated_at
      ''',
          [
            exactKey,
            kind,
            sourceBinding,
            projection,
            jsonEncode(version.toJson()),
            payloadJson,
            payloadHash,
            bytes,
            _publicationId(),
            now,
            now,
            now,
            now,
          ],
        );
        await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [exactKey]);
        for (final entry in expectedInvalidations.entries) {
          await customStatement(
            '''
          INSERT INTO cache_dependencies
          (entry_key, tag, invalidation_epoch, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
        ''',
            [exactKey, entry.key, entry.value, now, now],
          );
        }
        await _writeGrant(exactKey, entryKey, grant, now);
        await customStatement(
          '''
          INSERT INTO cache_heads(logical_key, entry_key, updated_at) VALUES (?, ?, ?)
          ON CONFLICT(logical_key) DO UPDATE SET entry_key = excluded.entry_key,
            updated_at = excluded.updated_at
        ''',
          [entryKey, exactKey, now],
        );
        return CachePublishStatus.published;
      });
      if (result == CachePublishStatus.published && evicted) onEvicted?.call();
      return result;
    } finally {
      for (final release in releases) {
        release();
      }
    }
  }

  Future<bool> replaceGrantIfCurrent({
    required String expectedStorageEpoch,
    required String entryKey,
    String? exactEntryKey,
    bool requireHead = true,
    required int expectedPublicationEpoch,
    required Map<String, int> expectedInvalidations,
    required String expectedPayloadHash,
    required CacheVersion expectedVersion,
    required CacheGrant? grant,
  }) => transaction(() async {
    if (await storageEpoch() != expectedStorageEpoch || await clearState() != 'ready') return false;
    final exactKey = exactEntryKey ?? await headEntryKey(entryKey);
    if (exactKey == null) return false;
    if (requireHead && await headEntryKey(entryKey) != exactKey) return false;
    if (!await _acceptedBodyMatches(
      exactKey,
      expectedPublicationEpoch,
      expectedPayloadHash,
      expectedVersion,
    )) {
      return false;
    }
    final epochs = await invalidationEpochs(expectedInvalidations.keys.toSet());
    if (expectedInvalidations.keys.any((tag) => epochs[tag] != expectedInvalidations[tag])) {
      return false;
    }
    if (!await _dependenciesMatch(exactKey, epochs)) return false;
    await _writeGrant(exactKey, entryKey, grant, DateTime.now().toUtc().toIso8601String());
    return true;
  });

  Future<void> _writeGrant(
    String entryKey,
    String logicalKey,
    CacheGrant? grant,
    String now,
  ) async {
    await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [entryKey]);
    if (grant == null || grant.resourceKey != logicalKey) return;
    await customStatement(
      'INSERT INTO offline_grants(entry_key, grant_json, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [entryKey, jsonEncode(grant.toJson()), now, now],
    );
  }

  Future<Map<String, int>> invalidate(
    Set<String> tags, {
    Future<void Function()?> Function(String, String?)? acquireEviction,
  }) async {
    final releases = <void Function()>[];
    try {
      return await transaction(() async {
        final now = DateTime.now().toUtc().toIso8601String();
        final committed = <String, int>{};
        final affected = <String>{};
        for (final tag in tags) {
          await customStatement(
            '''
        INSERT INTO cache_invalidations(tag, epoch, created_at, updated_at)
        VALUES (?, 1, ?, ?)
        ON CONFLICT(tag) DO UPDATE SET epoch = epoch + 1, updated_at = excluded.updated_at
      ''',
            [tag, now, now],
          );
          committed[tag] = (await customSelect(
            'SELECT epoch FROM cache_invalidations WHERE tag = ?',
            variables: [Variable.withString(tag)],
          ).get()).single.read<int>('epoch');
          final rows = await customSelect(
            'SELECT entry_key FROM cache_dependencies WHERE tag = ?',
            variables: [Variable.withString(tag)],
          ).get();
          affected.addAll(rows.map((row) => row.read<String>('entry_key')));
        }
        for (final exactKey in affected) {
          // Revoke authorization and the current pointer in the same transaction.
          // A visible reader may keep immutable bytes until its shared pin ends.
          final head = await customSelect(
            'SELECT logical_key FROM cache_heads WHERE entry_key = ?',
            variables: [Variable.withString(exactKey)],
          ).get();
          final logical = head.isEmpty ? null : head.single.read<String>('logical_key');
          await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [exactKey]);
          if (acquireEviction != null) {
            final release = await acquireEviction(exactKey, logical);
            if (release == null) continue;
            releases.add(release);
          }
          await customStatement('DELETE FROM cache_entries WHERE entry_key = ?', [exactKey]);
          await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [exactKey]);
          await customStatement('DELETE FROM cache_heads WHERE entry_key = ?', [exactKey]);
        }
        return committed;
      });
    } finally {
      for (final release in releases) {
        release();
      }
    }
  }

  /// Reclaim invalidated rows whose visible readers have released their locks.
  Future<void> pruneRetiredEntries({
    required Future<void Function()?> Function(String, String?) acquireEviction,
  }) async {
    final releases = <void Function()>[];
    try {
      await transaction(() async {
        final rows = await customSelect(
          'SELECT DISTINCT e.entry_key FROM cache_entries e '
          'JOIN cache_dependencies d ON d.entry_key = e.entry_key '
          'LEFT JOIN cache_invalidations i ON i.tag = d.tag '
          'WHERE d.invalidation_epoch != COALESCE(i.epoch, 0)',
        ).get();
        for (final row in rows) {
          final exactKey = row.read<String>('entry_key');
          final owner = await customSelect(
            'SELECT logical_key FROM cache_heads WHERE entry_key = ?',
            variables: [Variable.withString(exactKey)],
          ).get();
          final release = await acquireEviction(
            exactKey,
            owner.isEmpty ? null : owner.single.read<String>('logical_key'),
          );
          if (release == null) continue;
          releases.add(release);
          await customStatement('DELETE FROM cache_entries WHERE entry_key = ?', [exactKey]);
          await customStatement('DELETE FROM cache_dependencies WHERE entry_key = ?', [exactKey]);
          await customStatement('DELETE FROM offline_grants WHERE entry_key = ?', [exactKey]);
          await customStatement('DELETE FROM cache_heads WHERE entry_key = ?', [exactKey]);
        }
      });
    } finally {
      for (final release in releases) {
        release();
      }
    }
  }

  Future<String> clearText() => transaction(() async {
    final next = _epoch();
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      'UPDATE cache_control SET storage_epoch = ?, clear_state = ?, updated_at = ? WHERE id = 1',
      [next, 'clearing', now],
    );
    await customStatement('DELETE FROM cache_entries');
    await customStatement('DELETE FROM cache_heads');
    await customStatement('DELETE FROM cache_dependencies');
    await customStatement('DELETE FROM offline_grants');
    // The new epoch invalidates active download owners too. Keep their byte
    // references and reservations until the byte store confirms deletion.
    await customStatement(
      "UPDATE local_operations SET state = 'deleting', updated_at = ? WHERE state = 'staging'",
      [now],
    );
    final pending = (await customSelect(
      "SELECT (SELECT COUNT(*) FROM local_assets WHERE state = 'deleting') + "
      "(SELECT COUNT(*) FROM local_operations WHERE state = 'deleting') AS count",
    ).get()).single.read<int>('count');
    await customStatement('UPDATE cache_control SET clear_state = ?, updated_at = ? WHERE id = 1', [
      pending == 0 ? 'ready' : 'pending',
      now,
    ]);
    return next;
  });

  Future<void> setQuotas({int? textBytes, int? audioBytes}) async {
    if (textBytes != null && textBytes < 0 || audioBytes != null && audioBytes < 0) {
      throw ArgumentError('Quota cannot be negative');
    }
    await customStatement(
      '''
      UPDATE cache_control SET
        text_quota_bytes = COALESCE(?, text_quota_bytes),
        audio_quota_bytes = COALESCE(?, audio_quota_bytes),
        updated_at = ? WHERE id = 1
    ''',
      [textBytes, audioBytes, DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<bool> beginAudioOperation({
    required String expectedStorageEpoch,
    required String operationId,
    required String assetKey,
    required int reserveBytes,
    String stagingReference = '',
    bool allowDuringPending = false,
  }) => transaction(() async {
    if (reserveBytes < 0 || await storageEpoch() != expectedStorageEpoch) return false;
    final clear = await clearState();
    if (clear != 'ready' && !(allowDuringPending && clear == 'pending')) return false;
    final active = (await customSelect(
      "SELECT COUNT(*) AS count FROM local_operations WHERE state = 'staging'",
    ).get()).single.read<int>('count');
    if (active >= 2) return false;
    final used = await _audioUsedBytes();
    final quota = await _audioQuotaBytes();
    if (used + reserveBytes > quota) return false;
    final existing = await customSelect(
      'SELECT asset_key FROM local_assets WHERE asset_key = ?',
      variables: [Variable.withString(assetKey)],
    ).get();
    if (existing.isNotEmpty) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    final inserted = await customUpdate(
      '''INSERT INTO local_operations
      (operation_id, storage_epoch, asset_key, state, reserved_bytes, actual_bytes,
       blob_ref, created_at, updated_at)
       SELECT ?, ?, ?, 'staging', ?, 0, ?, ?, ?
       WHERE NOT EXISTS (
         SELECT 1 FROM local_operations
         WHERE asset_key = ? AND state IN ('staging', 'deleting')
       )''',
      variables: [
        Variable.withString(operationId),
        Variable.withString(expectedStorageEpoch),
        Variable.withString(assetKey),
        Variable.withInt(reserveBytes),
        Variable.withString(stagingReference),
        Variable.withString(now),
        Variable.withString(now),
        Variable.withString(assetKey),
      ],
    );
    return inserted == 1;
  });

  Future<bool> reserveAudioChunk({
    required String expectedStorageEpoch,
    required String operationId,
    required int additionalBytes,
  }) => transaction(() async {
    if (additionalBytes <= 0 || await storageEpoch() != expectedStorageEpoch) return false;
    final rows = await customSelect(
      "SELECT reserved_bytes FROM local_operations WHERE operation_id = ? AND storage_epoch = ? AND state = 'staging'",
      variables: [Variable.withString(operationId), Variable.withString(expectedStorageEpoch)],
    ).get();
    if (rows.isEmpty) return false;
    if (await _audioUsedBytes() + additionalBytes > await _audioQuotaBytes()) return false;
    await customStatement(
      'UPDATE local_operations SET reserved_bytes = reserved_bytes + ?, updated_at = ? WHERE operation_id = ?',
      [additionalBytes, DateTime.now().toUtc().toIso8601String(), operationId],
    );
    return true;
  });

  Future<bool> publishAudioReady({
    required String expectedStorageEpoch,
    required String operationId,
    required String assetKey,
    required String version,
    required String format,
    required String sha256Hex,
    required int actualBytes,
    required String readyReference,
  }) => transaction(() async {
    if (actualBytes < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex) ||
        !RegExp(r'^ready-[a-f0-9]{64}$').hasMatch(readyReference) ||
        version.isEmpty ||
        format.isEmpty ||
        await storageEpoch() != expectedStorageEpoch) {
      return false;
    }
    final rows = await customSelect(
      "SELECT asset_key, reserved_bytes FROM local_operations WHERE operation_id = ? AND storage_epoch = ? AND state = 'staging'",
      variables: [Variable.withString(operationId), Variable.withString(expectedStorageEpoch)],
    ).get();
    if (rows.isEmpty || rows.single.read<String>('asset_key') != assetKey) return false;
    if (actualBytes > rows.single.read<int>('reserved_bytes')) return false;
    if (await _audioUsedBytes() - rows.single.read<int>('reserved_bytes') + actualBytes >
        await _audioQuotaBytes()) {
      return false;
    }
    final existing = await customSelect(
      'SELECT asset_key FROM local_assets WHERE asset_key = ?',
      variables: [Variable.withString(assetKey)],
    ).get();
    if (existing.isNotEmpty) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      '''INSERT INTO local_assets
      (asset_key, version, format, sha256, expected_bytes, actual_bytes, state,
       blob_ref, last_access_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'ready', ?, ?, ?, ?)''',
      [
        assetKey,
        version,
        format,
        sha256Hex,
        actualBytes,
        actualBytes,
        readyReference,
        now,
        now,
        now,
      ],
    );
    await customStatement('DELETE FROM local_operations WHERE operation_id = ?', [operationId]);
    return true;
  });

  Future<void> abandonAudioOperation(String expectedStorageEpoch, String operationId) =>
      customStatement('DELETE FROM local_operations WHERE storage_epoch = ? AND operation_id = ?', [
        expectedStorageEpoch,
        operationId,
      ]);

  Future<bool> isAudioOperationCurrent(
    String expectedStorageEpoch,
    String operationId, {
    bool allowDuringPending = false,
  }) => transaction(() async {
    final rows = await customSelect(
      'SELECT o.state AS operation_state, o.storage_epoch AS operation_epoch, '
      'c.storage_epoch AS current_epoch, c.clear_state '
      'FROM local_operations o CROSS JOIN cache_control c '
      'WHERE o.operation_id = ? AND c.id = 1',
      variables: [Variable.withString(operationId)],
    ).get();
    if (rows.length != 1) return false;
    final row = rows.single;
    final clear = row.read<String>('clear_state');
    return row.read<String>('operation_state') == 'staging' &&
        row.read<String>('operation_epoch') == expectedStorageEpoch &&
        row.read<String>('current_epoch') == expectedStorageEpoch &&
        (clear == 'ready' || allowDuringPending && clear == 'pending');
  });

  Future<bool> completeAudioOperationDeletion({
    required String expectedStorageEpoch,
    required String operationId,
    required String expectedReference,
  }) async =>
      await customUpdate(
        "DELETE FROM local_operations WHERE state = 'deleting' AND "
        'storage_epoch = ? AND operation_id = ? AND blob_ref = ?',
        variables: [
          Variable.withString(expectedStorageEpoch),
          Variable.withString(operationId),
          Variable.withString(expectedReference),
        ],
      ) ==
      1;

  /// Once the retired owner lock is held, its reservation can no longer grow.
  /// Reconcile only the same deleting publication to the bytes still present.
  Future<bool> reconcileRetiredAudioOperation({
    required String expectedStorageEpoch,
    required String operationId,
    required String expectedReference,
    required String remainingReference,
    required int actualBytes,
  }) async {
    if (actualBytes < 0 || remainingReference.isEmpty) {
      throw ArgumentError('Invalid retired audio remainder');
    }
    return await customUpdate(
          "UPDATE local_operations SET reserved_bytes = ?, actual_bytes = ?, blob_ref = ?, "
          "updated_at = ? WHERE state = 'deleting' AND storage_epoch = ? "
          'AND operation_id = ? AND blob_ref = ?',
          variables: [
            Variable.withInt(actualBytes),
            Variable.withInt(actualBytes),
            Variable.withString(remainingReference),
            Variable.withString(DateTime.now().toUtc().toIso8601String()),
            Variable.withString(expectedStorageEpoch),
            Variable.withString(operationId),
            Variable.withString(expectedReference),
          ],
        ) ==
        1;
  }

  /// Retain a failed deletion as accounted work until the byte backend confirms
  /// the reference is gone. A failed stage must never release its reservation.
  Future<void> markAudioOperationDeleting({
    required String expectedStorageEpoch,
    required String operationId,
    required String reference,
    required int actualBytes,
  }) async {
    if (actualBytes < 0 || reference.isEmpty) throw ArgumentError('Invalid audio deletion');
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      "UPDATE local_operations SET state = 'deleting', "
      'reserved_bytes = MAX(reserved_bytes, ?), actual_bytes = MAX(actual_bytes, ?), '
      'blob_ref = ?, updated_at = ? WHERE storage_epoch = ? AND operation_id = ?',
      [actualBytes, actualBytes, reference, now, expectedStorageEpoch, operationId],
    );
  }

  /// Recovery may find a byte reference whose stage record was lost. Record it
  /// once so quota accounting and later clear attempts continue to include it.
  Future<void> recordAudioOrphanForDeletion({
    required String reference,
    required int actualBytes,
  }) => transaction(() async {
    if (actualBytes < 0 || reference.isEmpty) throw ArgumentError('Invalid orphan audio');
    final existing = await customSelect(
      'SELECT operation_id FROM local_operations WHERE blob_ref = ?',
      variables: [Variable.withString(reference)],
    ).get();
    if (existing.isNotEmpty) return;
    final id = 'orphan-${sha256.convert(utf8.encode(reference))}';
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      "INSERT OR IGNORE INTO local_operations "
      '(operation_id, storage_epoch, asset_key, state, reserved_bytes, actual_bytes, '
      "blob_ref, created_at, updated_at) VALUES (?, ?, ?, 'deleting', ?, ?, ?, ?, ?)",
      [id, await storageEpoch(), id, actualBytes, actualBytes, reference, now, now],
    );
  });

  Future<StoredAudioAsset?> audioAsset(
    String assetKey, {
    bool includeBroken = false,
    bool includeDeleting = false,
  }) async {
    final rows = await customSelect(
      'SELECT version, format, sha256, actual_bytes, blob_ref, state FROM local_assets WHERE asset_key = ? AND '
      "${includeDeleting
          ? "state IN ('ready', 'broken', 'deleting')"
          : includeBroken
          ? "state IN ('ready', 'broken')"
          : "state = 'ready'"}",
      variables: [Variable.withString(assetKey)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return StoredAudioAsset(
      assetKey: assetKey,
      version: row.read<String>('version'),
      format: row.read<String>('format'),
      sha256: row.read<String>('sha256'),
      bytes: row.read<int>('actual_bytes'),
      reference: row.read<String>('blob_ref'),
      isReady: row.read<String>('state') == 'ready',
      isDeleting: row.read<String>('state') == 'deleting',
    );
  }

  Future<bool> forgetAudioAssetIfCurrent(String assetKey, String reference) =>
      transaction(() async {
        final rows = await customSelect(
          'SELECT blob_ref FROM local_assets WHERE asset_key = ?',
          variables: [Variable.withString(assetKey)],
        ).get();
        if (rows.isEmpty || rows.single.read<String>('blob_ref') != reference) return false;
        await customStatement('DELETE FROM local_assets WHERE asset_key = ?', [assetKey]);
        return true;
      });

  Future<void> markAudioBroken(
    String assetKey,
    String reference, {
    required String expectedStorageEpoch,
    bool missing = false,
  }) async {
    await customStatement(
      "UPDATE local_assets SET state = 'broken', actual_bytes = CASE WHEN ? THEN 0 ELSE actual_bytes END, "
      "updated_at = ? WHERE asset_key = ? AND blob_ref = ? AND state IN ('ready', 'broken') "
      'AND EXISTS (SELECT 1 FROM cache_control WHERE id = 1 AND storage_epoch = ?)',
      [
        missing ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
        assetKey,
        reference,
        expectedStorageEpoch,
      ],
    );
  }

  Future<bool> touchAudioIfCurrent(
    String assetKey,
    String reference,
    String expectedStorageEpoch,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return await customUpdate(
          "UPDATE local_assets SET last_access_at = ?, updated_at = ? WHERE asset_key = ? AND blob_ref = ? AND state = 'ready' "
          "AND EXISTS (SELECT 1 FROM cache_control WHERE id = 1 AND storage_epoch = ?)",
          variables: [
            Variable.withString(now),
            Variable.withString(now),
            Variable.withString(assetKey),
            Variable.withString(reference),
            Variable.withString(expectedStorageEpoch),
          ],
        ) ==
        1;
  }

  Future<List<StoredAudioAsset>> readyAudioAssets({bool includeBroken = false}) async {
    final rows = await customSelect(
      "SELECT asset_key, version, format, sha256, actual_bytes, blob_ref FROM local_assets WHERE "
      "${includeBroken ? "state IN ('ready', 'broken')" : "state = 'ready'"} ORDER BY last_access_at, asset_key",
    ).get();
    return [
      for (final row in rows)
        StoredAudioAsset(
          assetKey: row.read<String>('asset_key'),
          version: row.read<String>('version'),
          format: row.read<String>('format'),
          sha256: row.read<String>('sha256'),
          bytes: row.read<int>('actual_bytes'),
          reference: row.read<String>('blob_ref'),
        ),
    ];
  }

  Future<List<StoredAudioOperation>> audioOperations() async {
    final rows = await customSelect(
      "SELECT operation_id, storage_epoch, asset_key, state, blob_ref FROM local_operations WHERE state IN ('staging', 'deleting')",
    ).get();
    return [
      for (final row in rows)
        StoredAudioOperation(
          row.read<String>('operation_id'),
          row.read<String>('storage_epoch'),
          row.read<String>('blob_ref'),
          assetKey: row.read<String>('asset_key'),
          state: row.read<String>('state'),
        ),
    ];
  }

  Future<List<StoredAudioOperation>> audioOperationsForAsset(String assetKey) async {
    final rows = await customSelect(
      "SELECT operation_id, storage_epoch, asset_key, state, blob_ref FROM local_operations "
      "WHERE asset_key = ? AND state IN ('staging', 'deleting')",
      variables: [Variable.withString(assetKey)],
    ).get();
    return [
      for (final row in rows)
        StoredAudioOperation(
          row.read<String>('operation_id'),
          row.read<String>('storage_epoch'),
          row.read<String>('blob_ref'),
          assetKey: row.read<String>('asset_key'),
          state: row.read<String>('state'),
        ),
    ];
  }

  Future<bool> hasPendingAudioForAsset(String assetKey) async =>
      (await audioOperationsForAsset(assetKey)).isNotEmpty;

  Future<int> _audioUsedBytes() async {
    final assets = (await customSelect(
      "SELECT COALESCE(SUM(actual_bytes), 0) AS used FROM local_assets WHERE state IN ('ready', 'deleting', 'broken')",
    ).get()).single.read<int>('used');
    final operations = (await customSelect(
      "SELECT COALESCE(SUM(CASE WHEN reserved_bytes > actual_bytes THEN reserved_bytes ELSE actual_bytes END), 0) AS used FROM local_operations WHERE state IN ('staging', 'deleting')",
    ).get()).single.read<int>('used');
    return assets + operations;
  }

  Future<int> _audioQuotaBytes() async => (await customSelect(
    'SELECT audio_quota_bytes FROM cache_control WHERE id = 1',
  ).get()).single.read<int>('audio_quota_bytes');

  Future<CacheUsage> usage() => transaction(() async {
    final control = (await customSelect(
      'SELECT text_quota_bytes, audio_quota_bytes FROM cache_control WHERE id = 1',
    ).get()).single;
    final text = (await customSelect(
      'SELECT COUNT(*) AS count, COALESCE(SUM(size_bytes), 0) AS used FROM cache_entries',
    ).get()).single;
    final assets = (await customSelect(
      "SELECT COUNT(*) AS count FROM local_assets WHERE state = 'ready'",
    ).get()).single;
    final operations = (await customSelect(
      "SELECT COUNT(*) AS count FROM local_operations WHERE state = 'staging'",
    ).get()).single;
    return CacheUsage(
      textBytes: text.read<int>('used'),
      audioBytes: await _audioUsedBytes(),
      textQuotaBytes: control.read<int>('text_quota_bytes'),
      audioQuotaBytes: control.read<int>('audio_quota_bytes'),
      textEntries: text.read<int>('count'),
      audioAssets: assets.read<int>('count'),
      activeDownloads: operations.read<int>('count'),
    );
  });

  Future<String> beginClearAll() => transaction(() async {
    final next = _epoch();
    final now = DateTime.now().toUtc().toIso8601String();
    await customStatement(
      "UPDATE cache_control SET storage_epoch = ?, clear_state = 'clearing', updated_at = ? WHERE id = 1",
      [next, now],
    );
    await customStatement('DELETE FROM cache_entries');
    await customStatement('DELETE FROM cache_heads');
    await customStatement('DELETE FROM cache_dependencies');
    await customStatement('DELETE FROM offline_grants');
    await customStatement("UPDATE local_assets SET state = 'deleting', updated_at = ?", [now]);
    await customStatement("UPDATE local_operations SET state = 'deleting', updated_at = ?", [now]);
    return next;
  });

  Future<List<String>> pendingAudioDeletions() async {
    final assets = await customSelect("SELECT blob_ref FROM local_assets WHERE state = 'deleting'")
        .get();
    final operations = await customSelect(
      "SELECT blob_ref FROM local_operations WHERE state = 'deleting' AND blob_ref != ''",
    ).get();
    return {
      for (final row in [...assets, ...operations]) row.read<String>('blob_ref'),
    }.toList();
  }

  Future<void> completeAudioDeletion(String reference) => transaction(() async {
    await customStatement("DELETE FROM local_assets WHERE state = 'deleting' AND blob_ref = ?", [
      reference,
    ]);
    await customStatement(
      "DELETE FROM local_operations WHERE state = 'deleting' AND blob_ref = ?",
      [reference],
    );
  });

  Future<int> finishClearAll({required String expectedStorageEpoch}) => transaction(() async {
    if (await storageEpoch() != expectedStorageEpoch) {
      throw const CacheBlocked('storage_epoch_changed');
    }
    return _finishClearRows();
  });

  /// A late owner may finish the current pending journal without taking over
  /// a newer clear that is still rotating its storage epoch.
  Future<bool> finishPendingCleanup({required String expectedStorageEpoch}) =>
      transaction(() async {
        if (await storageEpoch() != expectedStorageEpoch || await clearState() != 'pending') {
          return false;
        }
        await _finishClearRows();
        return true;
      });

  Future<int> _finishClearRows() async {
    await customStatement(
      "DELETE FROM local_operations WHERE state = 'deleting' AND blob_ref = ''",
    );
    final pending = (await customSelect(
      "SELECT (SELECT COUNT(*) FROM local_assets WHERE state = 'deleting') + "
      "(SELECT COUNT(*) FROM local_operations WHERE state = 'deleting') AS count",
    ).get()).single.read<int>('count');
    await customStatement('UPDATE cache_control SET clear_state = ?, updated_at = ? WHERE id = 1', [
      pending == 0 ? 'ready' : 'pending',
      DateTime.now().toUtc().toIso8601String(),
    ]);
    return pending;
  }

  Future<String> clearState() async => (await customSelect(
    'SELECT clear_state FROM cache_control WHERE id = 1',
  ).get()).single.read<String>('clear_state');
}

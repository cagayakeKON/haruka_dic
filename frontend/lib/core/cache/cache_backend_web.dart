import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import 'cache_backend.dart';
import 'cache_models.dart';
import 'cache_web_lock.dart';

Future<OpenedCacheBackend> openCacheBackend(String partition) async {
  const wasmAsset = 'sqlite3.wasm';
  const workerAsset = 'drift_worker.dart.js';
  final hasLocks = web.window.navigator.hasProperty('locks'.toJS).toDart;
  if (!hasLocks) return _openMemoryOnly(wasmAsset);
  try {
    final lock = await WebCacheLock.acquire('haruka-cache:$partition:capability', 'exclusive');
    if (lock == null) throw StateError('Web Locks unavailable');
    await lock.release();
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse(wasmAsset),
      driftWorkerUri: Uri.parse(workerAsset),
      databaseName: 'haruka_$partition',
    );
    if (probe.availableStorages.any(_safeStorage)) {
      final result = await WasmDatabase.open(
        databaseName: 'haruka_$partition',
        sqlite3Uri: Uri.parse(wasmAsset),
        driftWorkerUri: Uri.parse(workerAsset),
      );
      if (_safeStorage(result.chosenImplementation)) {
        return OpenedCacheBackend(
          executor: result.resolvedExecutor,
          mode: CacheStorageMode.persistent,
          closeOwner: () async {},
        );
      }
      await result.resolvedExecutor.close();
    }
  } on Object {
    // A denied storage API or a blocked worker must not prevent online use.
    // The memory executor never opens an unsafe shared persistent database.
  }
  return _openMemoryOnly(wasmAsset);
}

/// Used when an existing persistent index cannot be opened or migrated.
/// Keeping the old database untouched lets a later compatible app retry it.
Future<OpenedCacheBackend> openMemoryCacheBackend() =>
    _openMemoryOnly('sqlite3.wasm', degradedReason: 'persistent_schema_unavailable');

bool _safeStorage(WasmStorageImplementation mode) =>
    mode == WasmStorageImplementation.opfsShared ||
    mode == WasmStorageImplementation.opfsLocks ||
    mode == WasmStorageImplementation.sharedIndexedDb;

Future<OpenedCacheBackend> _openMemoryOnly(
  String wasmAsset, {
  String degradedReason = 'unsafe_browser_storage',
}) async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(wasmAsset));
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return OpenedCacheBackend(
    executor: WasmDatabase.inMemory(sqlite),
    mode: CacheStorageMode.memoryOnly,
    degradedReason: degradedReason,
    closeOwner: () async {},
  );
}

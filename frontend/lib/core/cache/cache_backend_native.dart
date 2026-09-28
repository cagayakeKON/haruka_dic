import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'cache_backend.dart';
import 'cache_database.dart';
import 'cache_models.dart';

Future<OpenedCacheBackend> openCacheBackend(String partition) async {
  final support = await getApplicationSupportDirectory();
  final folder = Directory(path.join(support.path, 'haruka-cache', partition));
  await folder.create(recursive: true);
  final owner = await File(path.join(folder.path, 'writer.lock')).open(mode: FileMode.append);
  try {
    await owner.lock(FileLock.exclusive);
    final index = File(path.join(folder.path, 'index.sqlite'));
    if (await index.exists()) {
      final probe = sqlite3.sqlite3.open(index.path, mode: sqlite3.OpenMode.readOnly);
      try {
        if (probe.select('PRAGMA user_version').single.values.single as int > 4) {
          throw const CacheSchemaTooNew();
        }
      } finally {
        probe.close();
      }
    }
    return OpenedCacheBackend(
      executor: NativeDatabase.createInBackground(index),
      mode: CacheStorageMode.persistent,
      closeOwner: () async {
        await owner.unlock();
        await owner.close();
      },
    );
  } on FileSystemException {
    await owner.close();
    throw const CacheBlocked('cache_writer_unavailable');
  } on sqlite3.SqliteException {
    // A damaged existing index is preserved for repair. The separate volatile
    // backend keeps authorized online reads available in this run.
    await owner.close();
    return openMemoryCacheBackend();
  } on Object {
    await owner.close();
    rethrow;
  }
}

/// Keeps a failed persistent index untouched while online reads remain usable.
Future<OpenedCacheBackend> openMemoryCacheBackend() async => OpenedCacheBackend(
  executor: NativeDatabase.memory(),
  mode: CacheStorageMode.memoryOnly,
  degradedReason: 'persistent_schema_unavailable',
  closeOwner: () async {},
);

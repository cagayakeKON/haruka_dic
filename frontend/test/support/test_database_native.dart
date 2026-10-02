import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> initializeTestDatabase() async {}

QueryExecutor memoryTestDatabase({void Function(CommonDatabase)? setup}) =>
    NativeDatabase.memory(setup: setup);

/// Native tests retain their real temporary file and close/reopen behavior.
final class TestDatabaseFile {
  TestDatabaseFile._(this._directory, this._file);
  final Directory _directory;
  final File _file;

  static Future<TestDatabaseFile> create(String prefix) async {
    final directory = await Directory.systemTemp.createTemp(prefix);
    return TestDatabaseFile._(directory, File('${directory.path}/index.sqlite'));
  }

  QueryExecutor executor() => NativeDatabase(_file);
  CommonDatabase openRaw() => sqlite3.open(_file.path);
  Future<void> close() async => _directory.delete(recursive: true);
}

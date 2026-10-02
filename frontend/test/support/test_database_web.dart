import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

WasmSqlite3? _sqlite;
Future<void>? _initialization;
final _files = InMemoryFileSystem();
var _nextFile = 0;

// Call from async setUpAll, before a widget test enters its fake async zone.
Future<void> initializeTestDatabase() => _initialization ??= _initialize();

Future<void> _initialize() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('/support/assets/sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(_files, makeDefault: true);
  _sqlite = sqlite;
}

WasmSqlite3 _loadedSqlite() =>
    _sqlite ?? (throw StateError('SQLite Wasm must be initialized in setUpAll'));

QueryExecutor memoryTestDatabase({void Function(CommonDatabase)? setup}) =>
    WasmDatabase.inMemory(_loadedSqlite(), setup: setup);

/// Browser migration/fallback tests reopen a named test VFS file.
/// This exercises real SQLite SQL; it does not claim host filesystem persistence.
final class TestDatabaseFile {
  TestDatabaseFile._(this._path);
  final String _path;

  static Future<TestDatabaseFile> create(String prefix) async {
    await initializeTestDatabase();
    return TestDatabaseFile._('/$prefix${_nextFile++}.sqlite');
  }

  QueryExecutor executor() => WasmDatabase(sqlite3: _loadedSqlite(), path: _path);
  CommonDatabase openRaw() => _loadedSqlite().open(_path);
  Future<void> close() async {
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      _files.xDelete('$_path$suffix', 0);
    }
  }
}

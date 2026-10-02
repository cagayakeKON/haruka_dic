// Test executors run the same cache SQL on native SQLite or SQLite Wasm.
export 'test_database_native.dart' if (dart.library.js_interop) 'test_database_web.dart';

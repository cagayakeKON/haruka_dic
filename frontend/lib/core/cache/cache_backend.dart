import 'package:drift/drift.dart';

import 'cache_models.dart';

export 'cache_backend_native.dart'
    if (dart.library.js_interop) 'cache_backend_web.dart'
    show openCacheBackend, openMemoryCacheBackend;

final class OpenedCacheBackend {
  const OpenedCacheBackend({
    required this.executor,
    required this.mode,
    required this.closeOwner,
    this.degradedReason,
  });

  final QueryExecutor executor;
  final CacheStorageMode mode;
  final Future<void> Function() closeOwner;
  final String? degradedReason;
}

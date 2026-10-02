import '../../support/test_database.dart';

import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_collection_remote.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';

final class CollectionCatalogTestHarness {
  CollectionCatalogTestHarness._(this.cache, this.catalog);

  final CacheCoordinator cache;
  final CachedCollectionCatalog catalog;

  static Future<CollectionCatalogTestHarness> create(
    PreviewFixtureStore store, {
    bool Function(String action)? permits,
    CollectionSource? source,
  }) async {
    await initializeTestDatabase();
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: memoryTestDatabase(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-test'),
        instanceId: 'collection-test',
        userId: 'test-user',
        audience: 'client',
        sessionRef: 'test-session',
      ),
    );
    return CollectionCatalogTestHarness._(
      cache,
      CachedCollectionCatalog(
        cache: cache,
        source: source ?? FixtureCollectionSource(store, permits: permits),
      ),
    );
  }

  Future<void> close() async {
    catalog.dispose();
    await cache.closeScope();
  }
}

import 'dart:async';

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/library/data/cached_material_catalog.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/dev/preview/fixture_material_remote.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'cached_material_catalog_test.mocks.dart';

@GenerateNiceMocks([MockSpec<CacheRemote<List<MaterialSummary>>>(as: #MockMaterialRemote)])
void main() {
  test('mutable catalog uses memory-only cache path and refreshes after import', () async {
    final remote = MockMaterialRemote();
    final first = MaterialSummary(
      id: 'novel-1',
      type: LearningMaterialType.novel,
      title: '夏の手紙',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '小说',
      cover: '夏',
    );
    final second = MaterialSummary(
      id: 'novel-2',
      type: LearningMaterialType.novel,
      title: '雨上がり',
      language: 'ja',
      status: 'processing',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27),
      description: '解析中',
      cover: '雨',
    );
    var items = <MaterialSummary>[first];
    var revision = 'one';
    provideDummy<CachePayload<List<MaterialSummary>>>(
      const CachePayload(
        value: <MaterialSummary>[],
        version: CacheVersion(resource: '', representation: '', artifact: ''),
      ),
    );
    provideDummy<CacheValidation>(const CacheValidation(state: ValidationState.changed));
    when(remote.fetch(any, any)).thenAnswer(
      (_) async => CachePayload(
        value: List<MaterialSummary>.of(items),
        version: CacheVersion(resource: revision, representation: 'summary-v1', artifact: revision),
      ),
    );
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final catalog = CachedMaterialCatalog(
      cache: cache,
      remote: remote,
      importSource: (type, title, language) async {
        items = [first, second];
        revision = 'two';
      },
      deleteSource: (id) async {},
    );
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
    });
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'preview-catalog-test',
        userId: 'preview-user',
        audience: 'client',
        sessionRef: 'preview-session',
      ),
    );

    await catalog.refresh();
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), hasLength(1));
    expect((await cache.usage()).textBytes, 0);
    verify(remote.fetch(any, any)).called(1);

    await catalog.refresh();
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), hasLength(1));
    verify(remote.fetch(any, any)).called(1);
    verifyNever(remote.validate(any, any, any));

    await catalog.importMaterial(LearningMaterialType.novel, second.title, 'ja');
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), hasLength(2));
    expect(
      catalog.filterMaterials(
        const MaterialCatalogQuery(type: LearningMaterialType.novel, search: '雨上がり'),
      ),
      [second],
    );
    verify(remote.fetch(any, any)).called(1);
    expect((await cache.usage()).textBytes, 0);

    clearInteractions(remote);
    const narrowed = MaterialCatalogQuery(type: LearningMaterialType.novel, search: '雨');
    await catalog.refresh(query: narrowed, force: true);
    final fetchedResource = verify(remote.fetch(captureAny, any)).captured.single as CacheResource;
    expect(fetchedResource.action, 'material.list');
    expect(fetchedResource.queryKey, narrowed.key);

    final pendingRefresh = Completer<CachePayload<List<MaterialSummary>>>();
    when(remote.fetch(any, any)).thenAnswer((_) => pendingRefresh.future);
    final refreshing = catalog.refresh(query: narrowed, force: true, preserveCurrent: true);
    expect(catalog.status, MaterialCatalogStatus.ready);
    expect(catalog.filterMaterials(narrowed), [second]);
    pendingRefresh.complete(
      CachePayload(
        value: [second],
        version: const CacheVersion(resource: 'two', representation: 'summary-v1', artifact: 'two'),
      ),
    );
    await refreshing;

    await cache.closeScope();
    expect(catalog.status, MaterialCatalogStatus.blocked);
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), isEmpty);
    expect(catalog.findById(first.id), isNull);
    when(remote.fetch(any, any)).thenAnswer(
      (_) async => CachePayload(
        value: [second],
        version: const CacheVersion(
          resource: 'another-user-list',
          representation: 'summary-v1',
          artifact: 'another-user-list',
        ),
      ),
    );
    final newAccountReady = Completer<void>();
    catalog.addListener(() {
      if (catalog.status == MaterialCatalogStatus.ready &&
          catalog.findById(second.id) != null &&
          !newAccountReady.isCompleted) {
        newAccountReady.complete();
      }
    });
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'preview-catalog-test',
        userId: 'another-user',
        audience: 'client',
        sessionRef: 'another-session',
      ),
    );
    expect(catalog.findById(first.id), isNull);
    await newAccountReady.future.timeout(const Duration(seconds: 2));
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), [second]);

    when(remote.fetch(any, any)).thenThrow(const CacheBlocked('resource_unavailable'));
    await catalog.refresh(force: true);
    expect(catalog.status, MaterialCatalogStatus.blocked);
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), isEmpty);
    expect(catalog.findById(first.id), isNull);
  });

  test('query identity carries list permission and preview source filters rows', () async {
    final query = MaterialCatalogQuery(type: LearningMaterialType.novel, search: '雨');
    final resource = materialCatalogResourceFor(query);
    expect(resource.action, 'material.list');
    expect(resource.queryKey, query.key);
    expect(MaterialCatalogQuery.fromKey(resource.queryKey).type, LearningMaterialType.novel);

    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureMaterialRemote(store);
    final payload = await remote.fetch(resource, CancelToken());
    expect(payload.value.map((item) => item.title), ['雨上がり']);
    final all = await remote.fetch(
      materialCatalogResourceFor(const MaterialCatalogQuery()),
      CancelToken(),
    );
    expect(all.value, hasLength(4));
  });

  test('late import completion cannot invalidate a new account catalog', () async {
    final remote = MockMaterialRemote();
    final mutation = Completer<void>();
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final catalog = CachedMaterialCatalog(
      cache: cache,
      remote: remote,
      importSource: (type, title, language) => mutation.future,
      deleteSource: (id) async {},
    );
    addTearDown(() async {
      catalog.dispose();
      await cache.closeScope();
    });
    Future<void> attach(String account) => cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'preview-catalog-test',
        userId: account,
        audience: 'client',
        sessionRef: 'session-$account',
      ),
    );
    await attach('a');
    final pending = catalog.importMaterial(LearningMaterialType.novel, '夏の手紙', 'ja');
    await cache.closeScope();
    await attach('b');
    mutation.complete();
    await expectLater(
      pending,
      throwsA(isA<CacheBlocked>().having((error) => error.reason, 'reason', 'scope_changed')),
    );
    verifyNever(remote.fetch(any, any));
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), isEmpty);
  });

  test(
    'external relevant invalidation refreshes, while a lost hint converges on reentry',
    () async {
      final remote = MockMaterialRemote();
      var title = 'Before';
      var fetches = 0;
      provideDummy<CachePayload<List<MaterialSummary>>>(
        const CachePayload(
          value: <MaterialSummary>[],
          version: CacheVersion(resource: '', representation: '', artifact: ''),
        ),
      );
      when(remote.fetch(any, any)).thenAnswer((_) async {
        fetches++;
        return CachePayload(
          value: [
            MaterialSummary(
              id: 'material-1',
              type: LearningMaterialType.novel,
              title: title,
              language: 'ja',
              status: 'readable',
              revision: fetches,
              updatedAt: DateTime.utc(2026, 9, 27),
              description: '',
              cover: '本',
            ),
          ],
          version: CacheVersion(
            resource: '$fetches',
            representation: 'summary-v1',
            artifact: '$fetches',
          ),
        );
      });
      final cache = CacheCoordinator(
        openBackend: (_) async => OpenedCacheBackend(
          executor: NativeDatabase.memory(),
          mode: CacheStorageMode.memoryOnly,
          closeOwner: () async {},
        ),
      );
      final catalog = CachedMaterialCatalog(
        cache: cache,
        remote: remote,
        importSource: (type, title, language) async {},
        deleteSource: (id) async {},
      );
      addTearDown(() async {
        catalog.dispose();
        await cache.closeScope();
      });
      await cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'preview-catalog-test',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      );
      await catalog.refresh();
      expect(catalog.findById('material-1')?.title, 'Before');
      expect(fetches, 1);

      title = 'Unrelated';
      await cache.applyCommittedMutation({'notification:list'});
      await Future<void>.delayed(Duration.zero);
      expect(fetches, 1);
      expect(catalog.findById('material-1')?.title, 'Before');

      final changed = Completer<void>();
      catalog.addListener(() {
        if (catalog.findById('material-1')?.title == 'Other device' && !changed.isCompleted) {
          changed.complete();
        }
      });
      title = 'Other device';
      await cache.applyCommittedMutation({materialCatalogDependency});
      await changed.future.timeout(const Duration(seconds: 2));
      expect(fetches, 2);

      // A dropped push/broadcast leaves no local hint. Foreground return or the
      // visible-list timer issues this forced read and discovers the new value.
      title = 'Missed hint';
      await Future<void>.delayed(Duration.zero);
      expect(catalog.findById('material-1')?.title, 'Other device');
      await catalog.refresh(force: true, preserveCurrent: true);
      expect(catalog.findById('material-1')?.title, 'Missed hint');
      expect(fetches, 3);

      final revalidated = Completer<void>();
      catalog.addListener(() {
        if (catalog.findById('material-1')?.title == 'After revalidation' &&
            !revalidated.isCompleted) {
          revalidated.complete();
        }
      });
      title = 'After revalidation';
      cache.requireOnlineRevalidation();
      expect(catalog.status, MaterialCatalogStatus.blocked);
      cache.completeOnlineRevalidation(cache.scope!);
      await revalidated.future.timeout(const Duration(seconds: 2));
      expect(fetches, 4);
      expect((await cache.usage()).textBytes, 0);
    },
  );
}

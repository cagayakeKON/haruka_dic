import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_access.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:mockito/mockito.dart';

import 'cached_collection_catalog_test.mocks.dart';

CachePayload<List<CollectionEntry>> _collectionPayload(
  List<CollectionEntry> rows,
  String version,
) => CachePayload(
  value: rows,
  version: CacheVersion(
    resource: version,
    representation: 'collection-summary-v1',
    artifact: version,
  ),
);

CachePayload<NotebookListSnapshot> _notebookPayload() => CachePayload(
  value: NotebookListSnapshot(notebooks: const [], counts: const {}),
  version: const CacheVersion(
    resource: 'notebooks',
    representation: 'notebook-summary-v1',
    artifact: 'notebooks',
  ),
);

Future<GoRouter> _pumpCatalogPage(WidgetTester tester, CollectionSource source) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final cache = CacheCoordinator(
    openBackend: (_) async => OpenedCacheBackend(
      executor: NativeDatabase.memory(),
      mode: CacheStorageMode.memoryOnly,
      closeOwner: () async {},
    ),
  );
  await tester.runAsync(
    () => cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/collection-visibility-test'),
        instanceId: 'collection-test',
        userId: 'test-user',
        audience: 'client',
        sessionRef: 'test-session',
      ),
    ),
  );
  final catalog = CachedCollectionCatalog(cache: cache, source: source);
  final router = GoRouter(
    observers: [PageRouteActivityObserver()],
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('collection dialog')),
                ),
                child: const Text('open collection dialog'),
              ),
              Expanded(
                child: CollectionCatalogAccess(
                  builder: (context, catalog) => Text('entries:${catalog.collections.length}'),
                ),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/covered',
        builder: (context, state) => const Scaffold(body: Text('covered')),
      ),
    ],
  );
  addTearDown(() async {
    router.dispose();
    catalog.dispose();
    await tester.runAsync(cache.closeScope);
  });
  await tester.pumpWidget(
    CollectionCatalogScope(
      catalog: catalog,
      child: MaterialApp.router(
        theme: HarukaTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('collection dialog preserves the authorized row and skips a redundant read', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final source = MockCollectionSource();
    final payload = _collectionPayload([store.collections.first], 'initial');
    provideDummy<CachePayload<List<CollectionEntry>>>(payload);
    provideDummy<CachePayload<NotebookListSnapshot>>(_notebookPayload());
    when(source.fetchCollections(any, any)).thenAnswer((_) async => payload);
    when(source.fetchNotebooks(any, any)).thenAnswer((_) async => _notebookPayload());

    await _pumpCatalogPage(tester, source);
    final row = tester.element(find.text('entries:1'));
    clearInteractions(source);
    await tester.tap(find.text('open collection dialog'));
    await tester.pump();
    expect(tester.element(find.text('entries:1')), same(row));
    verifyNever(source.fetchCollections(any, any));
    verifyNever(source.fetchNotebooks(any, any));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('entries:1')), same(row));
    verifyNever(source.fetchCollections(any, any));
    verifyNever(source.fetchNotebooks(any, any));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection list converges after a lost hint, route return and app resume', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final source = MockCollectionSource();
    var rows = [store.collections.first];
    final initial = _collectionPayload(rows, 'initial');
    provideDummy<CachePayload<List<CollectionEntry>>>(initial);
    provideDummy<CachePayload<NotebookListSnapshot>>(_notebookPayload());
    when(source.fetchCollections(any, any))
        .thenAnswer((_) async => _collectionPayload(rows, '${rows.length}'));
    when(source.fetchNotebooks(any, any)).thenAnswer((_) async => _notebookPayload());

    final router = await _pumpCatalogPage(tester, source);
    expect(find.text('entries:1'), findsOneWidget);
    verify(source.fetchCollections(any, any)).called(1);

    rows = store.collections.take(2).toList();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.text('entries:2'), findsOneWidget);
    verify(source.fetchCollections(any, any)).called(1);

    unawaited(router.push<void>('/covered'));
    await tester.pumpAndSettle();
    rows = store.collections.take(3).toList();
    await tester.pump(const Duration(seconds: 30));
    verifyNever(source.fetchCollections(any, any));

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('entries:3'), findsOneWidget);
    verify(source.fetchCollections(any, any)).called(1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    rows = store.collections.take(4).toList();
    await tester.pump(const Duration(seconds: 30));
    verifyNever(source.fetchCollections(any, any));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('entries:4'), findsOneWidget);
    verify(source.fetchCollections(any, any)).called(1);
  });

  testWidgets('slow list refresh queues one recheck after a hidden route returns', (tester) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final source = MockCollectionSource();
    final initial = _collectionPayload([store.collections.first], 'initial');
    final updated = _collectionPayload(store.collections, 'updated');
    provideDummy<CachePayload<List<CollectionEntry>>>(initial);
    provideDummy<CachePayload<NotebookListSnapshot>>(_notebookPayload());
    final slow = Completer<CachePayload<List<CollectionEntry>>>();
    var reads = 0;
    when(source.fetchCollections(any, any)).thenAnswer((_) {
      reads++;
      if (reads == 2) return slow.future;
      return Future.value(reads == 1 ? initial : updated);
    });
    when(source.fetchNotebooks(any, any)).thenAnswer((_) async => _notebookPayload());

    final router = await _pumpCatalogPage(tester, source);
    expect(find.text('entries:1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);

    unawaited(router.push<void>('/covered'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pump(const Duration(milliseconds: 500));
    expect(reads, 2);
    expect(find.text('entries:1'), findsNothing);

    slow.complete(initial);
    await tester.pumpAndSettle();
    expect(reads, 3);
    await tester.pump();
    expect(find.text('entries:${store.collections.length}'), findsOneWidget);
  });
}

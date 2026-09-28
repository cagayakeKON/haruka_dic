import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_access.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/presentation/material_catalog_access.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

class _MaterialReads extends ChangeNotifier implements MaterialCatalog {
  MaterialCatalogStatus current = MaterialCatalogStatus.ready;
  int requests = 0;

  @override
  MaterialCatalogStatus get status => current;
  @override
  Future<void> refresh({
    MaterialCatalogQuery query = const MaterialCatalogQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    requests++;
  }

  void block() {
    current = MaterialCatalogStatus.blocked;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CollectionReads extends ChangeNotifier implements CollectionCatalog {
  CollectionCatalogStatus current = CollectionCatalogStatus.ready;
  int requests = 0;

  @override
  CollectionCatalogStatus get collectionStatus => current;
  @override
  CollectionCatalogStatus get notebookStatus => current;
  @override
  Future<void> refreshCollections({
    CollectionListQuery query = const CollectionListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    requests++;
  }

  @override
  Future<void> refreshNotebooks({bool force = false, bool preserveCurrent = false}) async {
    requests++;
  }

  void block() {
    current = CollectionCatalogStatus.blocked;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('browser focus changes keep a visible page foreground', () {
    expect(
      foregroundAfterLifecycle(AppLifecycleState.inactive, wasForeground: true, web: true),
      isTrue,
    );
    expect(
      foregroundAfterLifecycle(AppLifecycleState.resumed, wasForeground: true, web: true),
      isTrue,
    );
    expect(
      foregroundAfterLifecycle(AppLifecycleState.hidden, wasForeground: true, web: true),
      isFalse,
    );
    expect(
      foregroundAfterLifecycle(AppLifecycleState.resumed, wasForeground: false, web: true),
      isTrue,
    );
  });

  testWidgets('background return keeps rows mounted without reads; blocked scopes hide them', (
    tester,
  ) async {
    final materials = _MaterialReads();
    final collections = _CollectionReads();
    addTearDown(materials.dispose);
    addTearDown(collections.dispose);
    await tester.pumpWidget(
      MaterialCatalogScope(
        catalog: materials,
        child: CollectionCatalogScope(
          catalog: collections,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: MaterialCatalogAccess(
                      builder: (context, catalog) => const Text('material row'),
                    ),
                  ),
                  Expanded(
                    child: CollectionCatalogAccess(
                      builder: (context, catalog) => const Text('collection row'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final materialRow = tester.element(find.text('material row'));
    final collectionRow = tester.element(find.text('collection row'));
    final materialRequests = materials.requests;
    final collectionRequests = collections.requests;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.element(find.text('material row')), same(materialRow));
    expect(tester.element(find.text('collection row')), same(collectionRow));
    expect(materials.requests, materialRequests);
    expect(collections.requests, collectionRequests);

    materials.block();
    collections.block();
    await tester.pump();
    expect(find.text('material row'), findsNothing);
    expect(find.text('collection row'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import '../data/collection_catalog.dart';
import '../domain/collection_entry.dart';

/// Uses the already authorized row when a detail overlay opens. A missing row
/// or notebook snapshot is loaded independently; opening an existing overlay
/// never refreshes the visible collection list.
Future<CollectionEntry?> readCollectionForOverlay(CollectionCatalog catalog, String itemId) async {
  try {
    final ready =
        catalog.collectionStatus == CollectionCatalogStatus.ready ||
        catalog.allCollectionStatus == CollectionCatalogStatus.ready;
    if (!ready || catalog.findCollection(itemId) == null) {
      await catalog.refreshAllCollections(preserveCurrent: true);
    }
    if (catalog.notebookStatus != CollectionCatalogStatus.ready) {
      await catalog.refreshNotebooks(preserveCurrent: true);
    }
  } on Object {
    return null;
  }
  if (catalog.notebookStatus != CollectionCatalogStatus.ready ||
      (catalog.collectionStatus != CollectionCatalogStatus.ready &&
          catalog.allCollectionStatus != CollectionCatalogStatus.ready)) {
    return null;
  }
  return catalog.findCollection(itemId);
}

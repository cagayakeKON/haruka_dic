import 'package:flutter/widgets.dart';

import '../data/collection_catalog.dart';

class CollectionCatalogScope extends InheritedNotifier<CollectionCatalog> {
  const CollectionCatalogScope({
    required CollectionCatalog catalog,
    required super.child,
    super.key,
  }) : super(notifier: catalog);

  static CollectionCatalog of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CollectionCatalogScope>();
    assert(scope != null, 'CollectionCatalogScope is missing');
    return scope!.notifier!;
  }

  static CollectionCatalog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CollectionCatalogScope>()?.notifier;
}

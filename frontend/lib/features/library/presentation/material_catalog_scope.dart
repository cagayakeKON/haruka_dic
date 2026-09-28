import 'package:flutter/widgets.dart';

import '../data/material_catalog.dart';

class MaterialCatalogScope extends InheritedNotifier<MaterialCatalog> {
  const MaterialCatalogScope({required MaterialCatalog catalog, required super.child, super.key})
    : super(notifier: catalog);

  static MaterialCatalog of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MaterialCatalogScope>();
    assert(scope != null, 'MaterialCatalogScope is missing');
    return scope!.notifier!;
  }
}

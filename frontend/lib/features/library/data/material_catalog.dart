import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/material_summary.dart';

enum MaterialCatalogStatus { initial, loading, ready, stale, blocked, failed }

/// First-page list identity. When the API adds paging, its cursor and page
/// size must become part of this key and the result must carry nextCursor.
final class MaterialCatalogQuery {
  const MaterialCatalogQuery({this.type, this.search = ''});

  final LearningMaterialType? type;
  final String search;

  String get normalizedSearch => search.trim().toLowerCase();

  String get key => jsonEncode([type?.name, normalizedSearch]);

  factory MaterialCatalogQuery.fromKey(String key) {
    final parts = jsonDecode(key);
    if (parts is! List || parts.length != 2 || parts[1] is! String) {
      throw const FormatException('Invalid material catalog query');
    }
    final typeName = parts[0];
    if (typeName != null && typeName is! String) {
      throw const FormatException('Invalid material catalog type');
    }
    return MaterialCatalogQuery(
      type: typeName == null ? null : LearningMaterialType.values.byName(typeName as String),
      search: parts[1] as String,
    );
  }
}

/// The material list boundary used by both compact and expanded views.
abstract interface class MaterialCatalog implements Listenable {
  MaterialCatalogStatus get status;

  List<MaterialSummary> filterMaterials(MaterialCatalogQuery query);

  MaterialSummary? findById(String id);

  /// Rechecks the current list on entry, filter changes and foreground return.
  Future<void> refresh({
    MaterialCatalogQuery query = const MaterialCatalogQuery(),
    bool force = false,
    bool preserveCurrent = false,
  });

  Future<void> importMaterial(LearningMaterialType type, String title, String language);

  Future<void> deleteMaterial(String id);
}

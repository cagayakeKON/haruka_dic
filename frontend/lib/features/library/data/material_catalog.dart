import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/material_summary.dart';

enum MaterialCatalogStatus { initial, loading, ready, stale, blocked, failed }

/// Query identity shared by compact and wide layouts. The HTTP cache appends
/// its opaque page cursor; preview catalogs keep the compatible two-part key.
final class MaterialCatalogQuery {
  const MaterialCatalogQuery({this.type, this.search = '', this.language});

  final LearningMaterialType? type;
  final String search;
  final String? language;

  String get normalizedSearch => search.trim().toLowerCase();

  String get key => jsonEncode([type?.name, normalizedSearch, if (language != null) language]);

  factory MaterialCatalogQuery.fromKey(String key) {
    final parts = jsonDecode(key);
    if (parts is! List || (parts.length != 2 && parts.length != 3) || parts[1] is! String) {
      throw const FormatException('Invalid material catalog query');
    }
    final typeName = parts[0];
    if (typeName != null && typeName is! String) {
      throw const FormatException('Invalid material catalog type');
    }
    return MaterialCatalogQuery(
      type: typeName == null ? null : LearningMaterialType.values.byName(typeName as String),
      search: parts[1] as String,
      language: parts.length == 3 ? parts[2] as String : null,
    );
  }
}

/// The material list boundary used by both compact and expanded views.
abstract interface class MaterialCatalog implements Listenable {
  MaterialCatalogStatus get status;

  List<MaterialSummary> filterMaterials(MaterialCatalogQuery query);

  MaterialSummary? findById(String id);

  /// Reads missing/query-changed data; force is reserved for explicit refresh
  /// or a committed mutation. Route and foreground return do not force reads.
  Future<void> refresh({
    MaterialCatalogQuery query = const MaterialCatalogQuery(),
    bool force = false,
    bool preserveCurrent = false,
  });

  Future<void> importMaterial(LearningMaterialType type, String title, String language);

  Future<void> deleteMaterial(String id);
}

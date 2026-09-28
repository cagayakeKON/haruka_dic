import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/cache/cache_coordinator.dart';
import '../../core/cache/cache_models.dart';
import '../../features/library/domain/material_summary.dart';
import '../../features/library/data/material_catalog.dart';
import 'fixture_store.dart';

/// Development transport. The UI still enters through the cached catalog.
final class FixtureMaterialRemote implements CacheRemote<List<MaterialSummary>> {
  const FixtureMaterialRemote(this.store);

  final PreviewFixtureStore store;

  List<MaterialSummary> _items(CacheResource resource) {
    final query = MaterialCatalogQuery.fromKey(resource.queryKey);
    final term = query.normalizedSearch;
    return [
      for (final item in store.materials)
        if (store.canReadMaterial(item.id) &&
            (query.type == null || item.type == query.type) &&
            (term.isEmpty ||
                item.title.toLowerCase().contains(term) ||
                item.language.toLowerCase().contains(term)))
          item,
    ];
  }

  CacheVersion _version(List<MaterialSummary> items) {
    final digest = sha256
        .convert(utf8.encode(jsonEncode([for (final item in items) item.toJson()])))
        .toString();
    return CacheVersion(resource: digest, representation: 'material-summary-v1', artifact: digest);
  }

  @override
  Future<CachePayload<List<MaterialSummary>>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final items = _items(resource);
    return CachePayload(value: List.unmodifiable(items), version: _version(items));
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final version = _version(_items(resource));
    return CacheValidation(
      state: known.resource == version.resource ? ValidationState.same : ValidationState.changed,
      version: version,
    );
  }
}

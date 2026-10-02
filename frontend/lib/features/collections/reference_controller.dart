import 'package:flutter/foundation.dart';

import '../../core/api/learning_models.dart';
import '../../core/api/responses.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/telemetry/telemetry.dart';
import 'reference_repository.dart';
import 'reference_selection.dart';

String referenceScope(AuthController auth, String page) {
  final access = auth.access;
  return [
    page,
    auth.boundInstanceId,
    access?.userId ?? '',
    access?.audience ?? '',
    access?.sessionRef ?? '',
    access?.authzVersion.user ?? 0,
    access?.authzVersion.policy ?? 0,
  ].join(':');
}

/// Reference flow. All reads and writes pass the current account use case;
/// a disposed scope never publishes a late result into another account.
final class ReferenceController extends ChangeNotifier {
  ReferenceController(this.auth, this.repository, {this.telemetry})
    : _openingScope = referenceScope(auth, 'reference');

  final AuthController auth;
  final String _openingScope;
  final ReferenceRepository repository;
  final Telemetry? telemetry;
  bool _disposed = false;
  bool get _active =>
      !_disposed && auth.isAuthenticated && referenceScope(auth, 'reference') == _openingScope;
  bool materialsLoading = false;
  Future<void>? _materialsRequest;
  bool collectionsLoading = false;
  bool get loading => materialsLoading || collectionsLoading;
  bool busy = false;
  ApiFailure? error;
  ApiFailure? materialError;
  ApiFailure? collectionError;
  final List<MaterialSummary> materials = [];
  final Set<String> _retiredMaterials = {};
  bool materialsLoaded = false;
  String? materialCursor;
  MaterialSummary? material;
  NovelChapter? chapter;
  ReferenceSelection? selectedSelection;
  NovelBlock? get selectedBlock => selectedSelection?.block;
  ResolvedCard? resolved;
  CollectionRead? saved;
  String? _saveKey;
  final List<CollectionRead> collections = [];
  final Map<String, (int, CollectionRead)> _confirmedCollections = {};
  int _collectionMutationSerial = 0;
  bool collectionsLoaded = false;
  String? collectionCursor;
  int _selectionGeneration = 0;

  bool get canResolve =>
      _active &&
      auth.access?.allows('client.ai.explain') == true &&
      auth.access?.allows('client.material.read') == true;
  bool get canSave =>
      _active &&
      auth.access?.allows('client.collection.create') == true &&
      auth.access?.allows('client.material.read') == true;
  bool get canListCollections => _active && auth.access?.allows('client.collection.read') == true;

  void _publish() {
    if (_active) notifyListeners();
  }

  void _failure(Object failure) {
    error = failure is ApiFailure ? failure : const ApiFailure(code: 'INVALID_RESPONSE');
    _publish();
  }

  Future<void> ensureMaterials() async {
    if (_active && !materialsLoaded) await loadMaterials();
  }

  /// A committed tombstone retires only this source. Historic collection
  /// associations remain subject to their own current source authorization.
  void retireMaterial(String id) {
    if (!_active) return;
    materials.removeWhere((row) => row.id == id);
    _retiredMaterials.add(id);
    if (material?.id == id) {
      _selectionGeneration++;
      material = null;
      chapter = null;
      selectedSelection = null;
      resolved = null;
      saved = null;
      _saveKey = null;
      busy = false;
    }
    _publish();
  }

  /// A source link is an explicit navigation request. Find its published
  /// summary in the authorized list without turning every detail open into a
  /// full-library refresh.
  Future<MaterialSummary?> ensureMaterial(String id, {MaterialSummary? available}) async {
    if (!_active ||
        auth.access?.allows('client.material.list') != true ||
        auth.access?.allows('client.material.read') != true) {
      if (_active) _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return null;
    }
    if (_retiredMaterials.contains(id)) return null;
    if (available != null && available.id == id) {
      final index = materials.indexWhere((row) => row.id == id);
      if (index == -1) {
        materials.add(available);
      } else {
        materials[index] = available;
      }
      return available;
    }
    final retryingError = materialError != null;
    if (_materialsRequest != null) await _materialsRequest;
    if (retryingError) {
      await loadMaterials(more: materialsLoaded && materialCursor != null);
    } else {
      await ensureMaterials();
    }
    final seenCursors = <String>{};
    while (_active && materialError == null) {
      final found = materials
          .where((item) => item.id == id && !_retiredMaterials.contains(item.id))
          .firstOrNull;
      if (found != null) return found;
      final cursor = materialCursor;
      if (cursor == null || !seenCursors.add(cursor)) break;
      await loadMaterials(more: true);
    }
    return null;
  }

  Future<void> ensureCollections() async {
    if (_active && !collectionsLoaded) await loadCollections();
  }

  Future<void> loadMaterials({bool more = false}) {
    if (!_active) return Future<void>.value();
    final inFlight = _materialsRequest;
    if (inFlight != null) return inFlight;
    final request = _loadMaterials(more: more);
    _materialsRequest = request;
    return request.whenComplete(() {
      if (identical(_materialsRequest, request)) _materialsRequest = null;
    });
  }

  Future<void> _loadMaterials({required bool more}) async {
    if (!auth.access!.allows('client.material.list')) {
      materialError = const ApiFailure(code: 'PERMISSION_DENIED');
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    if (more && materialCursor == null) return;
    materialsLoading = true;
    error = null;
    materialError = null;
    _publish();
    try {
      final page = await auth.authorizedRead(
        (headers) => repository.materials(headers, cursor: more ? materialCursor : null),
      );
      if (!_active) return;
      if (!more) {
        materials
          ..clear()
          ..addAll(page.data.where((row) => !_retiredMaterials.contains(row.id)));
      } else {
        final seen = materials.map((item) => item.id).toSet();
        materials.addAll(
          page.data.where((item) => !_retiredMaterials.contains(item.id) && seen.add(item.id)),
        );
      }
      materialCursor = page.nextCursor;
      materialsLoaded = true;
    } on Object catch (failure) {
      materialError = failure is ApiFailure ? failure : const ApiFailure(code: 'INVALID_RESPONSE');
      _failure(failure);
    } finally {
      materialsLoading = false;
      _publish();
    }
  }

  Future<void> openMaterial(MaterialSummary next) async {
    if (!_active || _retiredMaterials.contains(next.id)) return;
    if (material?.id == next.id && material?.revisionId == next.revisionId && chapter != null) {
      return;
    }
    if (busy || auth.access?.allows('client.material.read') != true) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    final generation = ++_selectionGeneration;
    busy = true;
    error = null;
    material = next;
    chapter = null;
    selectedSelection = null;
    resolved = null;
    saved = null;
    _saveKey = null;
    _publish();
    try {
      final result = await auth.authorizedRead((headers) => repository.chapter(next, headers));
      if (!_active || generation != _selectionGeneration) return;
      chapter = result;
      telemetry?.track('reading.chapter.opened', attributes: {'material_type': 'novel'});
    } on Object catch (failure) {
      if (_active && generation == _selectionGeneration) _failure(failure);
    } finally {
      if (_active && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  /// The range comes from a real text selection; the service revalidates it
  /// against the published source and current account permissions.
  void select(ReferenceSelection? selection) {
    if (!_active) return;
    final previous = selectedSelection;
    if (previous?.block.id == selection?.block.id &&
        previous?.locator.span.start == selection?.locator.span.start &&
        previous?.locator.span.end == selection?.locator.span.end) {
      return;
    }
    ++_selectionGeneration;
    busy = false;
    selectedSelection = selection;
    resolved = null;
    saved = null;
    _saveKey = null;
    error = null;
    _publish();
  }

  Future<void> resolve() async {
    if (!_active) return;
    final selection = selectedSelection;
    final source = material;
    if (busy || selection == null || source == null) return;
    final locator = selection.locator;
    if (locator.instanceId != auth.boundInstanceId ||
        locator.materialId != source.id ||
        locator.materialRevisionId != source.revisionId ||
        locator.span.blockId != selection.block.id) {
      _failure(const ApiFailure(code: 'INVALID_RESPONSE'));
      return;
    }
    if (!canResolve) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    final generation = _selectionGeneration;
    telemetry?.track('explanation.requested', attributes: {'target_kind': 'material_content'});
    busy = true;
    error = null;
    resolved = null;
    _publish();
    try {
      final result = await auth.authorizedRead(
        (headers) => repository.resolve(locator, source.language, headers),
      );
      if (!_active || generation != _selectionGeneration) return;
      resolved = result;
    } on Object catch (failure) {
      if (_active && generation == _selectionGeneration) _failure(failure);
    } finally {
      if (_active && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  Future<void> save() async {
    if (!_active) return;
    final card = resolved?.card;
    if (busy || card == null) return;
    if (!canSave) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    final generation = _selectionGeneration;
    // A lost response has an unknown result. Explicit retry keeps this key.
    final key = _saveKey ??= AuthRepository.newRequestId();
    busy = true;
    error = null;
    _publish();
    try {
      final result = await auth.authorizedWrite((headers) => repository.create(card, key, headers));
      if (!_active || generation != _selectionGeneration) return;
      saved = result;
      _saveKey = null;
      _confirmedCollections[result.id] = (++_collectionMutationSerial, result);
      collections.removeWhere((item) => item.id == result.id);
      collections.insert(0, result);
      telemetry?.track(
        'collection.saved',
        attributes: {'card_type': 'word', 'result': 'success'},
        operationId: key,
      );
    } on Object catch (failure) {
      if (_active && generation == _selectionGeneration) {
        telemetry?.track(
          'collection.saved',
          attributes: {'card_type': 'word', 'result': 'failure'},
          operationId: key,
        );
        _failure(failure);
      }
    } finally {
      if (_active && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  Future<void> loadCollections({bool more = false}) async {
    if (collectionsLoading || !_active) return;
    if (!auth.access!.allows('client.collection.read')) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    if (more && collectionCursor == null) return;
    collectionsLoading = true;
    final readStartedAtMutation = _collectionMutationSerial;
    error = null;
    collectionError = null;
    _publish();
    try {
      final page = await auth.authorizedRead(
        (headers) => repository.collections(headers, cursor: more ? collectionCursor : null),
      );
      if (!_active) return;
      if (!more) {
        final newerWrites = [
          for (final entry in _confirmedCollections.values)
            if (entry.$1 > readStartedAtMutation) entry.$2,
        ];
        final newerIds = newerWrites.map((item) => item.id).toSet();
        collections
          ..clear()
          ..addAll(newerWrites)
          ..addAll(page.data.where((item) => !newerIds.contains(item.id)));
        _confirmedCollections.removeWhere((_, entry) => entry.$1 <= readStartedAtMutation);
      } else {
        final seen = collections.map((item) => item.id).toSet();
        collections.addAll(page.data.where((item) => seen.add(item.id)));
      }
      collectionCursor = page.nextCursor;
      collectionsLoaded = true;
    } on Object catch (failure) {
      collectionError = failure is ApiFailure
          ? failure
          : const ApiFailure(code: 'INVALID_RESPONSE');
      _failure(failure);
    } finally {
      collectionsLoading = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_selectionGeneration;
    super.dispose();
  }
}

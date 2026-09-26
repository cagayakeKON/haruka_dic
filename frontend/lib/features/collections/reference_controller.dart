import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/learning_models.dart';
import '../../core/api/responses.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/telemetry/telemetry.dart';
import 'reference_repository.dart';
import 'reference_selection.dart';

final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => throw StateError('Reference repository missing'),
);

final referenceControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ReferenceController, String>(
      (ref, scope) => ReferenceController(
        ref.read(authControllerProvider),
        ref.read(referenceRepositoryProvider),
        telemetry: ref.read(telemetryProvider),
      ),
    );

String referenceScope(AuthController auth, String page) {
  final access = auth.access;
  return [
    page,
    auth.config.instanceId,
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
  ReferenceController(this.auth, this.repository, {this.telemetry});

  final AuthController auth;
  final ReferenceRepository repository;
  final Telemetry? telemetry;
  bool _disposed = false;
  bool loading = false;
  bool busy = false;
  ApiFailure? error;
  final List<MaterialSummary> materials = [];
  String? materialCursor;
  MaterialSummary? material;
  NovelChapter? chapter;
  ReferenceSelection? selectedSelection;
  NovelBlock? get selectedBlock => selectedSelection?.block;
  ResolvedCard? resolved;
  CollectionRead? saved;
  String? _saveKey;
  final List<CollectionRead> collections = [];
  bool collectionsLoaded = false;
  String? collectionCursor;
  int _selectionGeneration = 0;

  bool get canResolve =>
      auth.access?.allows('client.ai.explain') == true &&
      auth.access?.allows('client.material.read') == true;
  bool get canSave =>
      auth.access?.allows('client.collection.create') == true &&
      auth.access?.allows('client.material.read') == true;
  bool get canListCollections => auth.access?.allows('client.collection.read') == true;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void _failure(Object failure) {
    error = failure is ApiFailure ? failure : const ApiFailure(code: 'INVALID_RESPONSE');
    _publish();
  }

  Future<void> loadMaterials({bool more = false}) async {
    if (loading || !auth.isAuthenticated) return;
    if (!auth.access!.allows('client.material.list')) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    if (more && materialCursor == null) return;
    loading = true;
    error = null;
    if (!more) {
      materials.clear();
      materialCursor = null;
    }
    _publish();
    try {
      final page = await auth.authorizedRead(
        (headers) => repository.materials(headers, cursor: more ? materialCursor : null),
      );
      if (_disposed) return;
      materials.addAll(page.data);
      materialCursor = page.nextCursor;
    } on Object catch (failure) {
      _failure(failure);
    } finally {
      loading = false;
      _publish();
    }
  }

  Future<void> openMaterial(MaterialSummary next) async {
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
      if (_disposed || generation != _selectionGeneration) return;
      chapter = result;
      telemetry?.track('reading.chapter.opened', attributes: {'material_type': 'novel'});
    } on Object catch (failure) {
      if (!_disposed && generation == _selectionGeneration) _failure(failure);
    } finally {
      if (!_disposed && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  /// The range comes from a real text selection; the service revalidates it
  /// against the published source and current account permissions.
  void select(ReferenceSelection? selection) {
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
    final selection = selectedSelection;
    final source = material;
    if (busy || selection == null || source == null) return;
    final locator = selection.locator;
    if (locator.instanceId != auth.config.instanceId ||
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
      if (_disposed || generation != _selectionGeneration) return;
      resolved = result;
    } on Object catch (failure) {
      if (!_disposed && generation == _selectionGeneration) _failure(failure);
    } finally {
      if (!_disposed && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  Future<void> save() async {
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
      if (_disposed || generation != _selectionGeneration) return;
      saved = result;
      _saveKey = null;
      telemetry?.track(
        'collection.saved',
        attributes: {'card_type': 'word', 'result': 'success'},
        operationId: key,
      );
    } on Object catch (failure) {
      if (!_disposed && generation == _selectionGeneration) {
        telemetry?.track(
          'collection.saved',
          attributes: {'card_type': 'word', 'result': 'failure'},
          operationId: key,
        );
        _failure(failure);
      }
    } finally {
      if (!_disposed && generation == _selectionGeneration) {
        busy = false;
        _publish();
      }
    }
  }

  Future<void> loadCollections({bool more = false}) async {
    if (loading || !auth.isAuthenticated) return;
    if (!auth.access!.allows('client.collection.read')) {
      _failure(const ApiFailure(code: 'PERMISSION_DENIED'));
      return;
    }
    if (more && collectionCursor == null) return;
    loading = true;
    error = null;
    if (!more) {
      collections.clear();
      collectionCursor = null;
      collectionsLoaded = false;
    }
    _publish();
    try {
      final page = await auth.authorizedRead(
        (headers) => repository.collections(headers, cursor: more ? collectionCursor : null),
      );
      if (_disposed) return;
      collections.addAll(page.data);
      collectionCursor = page.nextCursor;
      collectionsLoaded = true;
    } on Object catch (failure) {
      _failure(failure);
    } finally {
      loading = false;
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

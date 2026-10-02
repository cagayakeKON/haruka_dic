import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../domain/material_import.dart';
import '../domain/material_summary.dart';
import 'staging_upload_native.dart'
    if (dart.library.js_interop) 'staging_upload_web.dart'
    as staging;

abstract interface class MaterialImportRepository {
  Future<MaterialImportCapabilities> capabilities();
  Future<MaterialImport> create({
    required XFile file,
    required LearningMaterialType type,
    required String language,
    required String title,
    required String idempotencyKey,
  });
  Future<MaterialImport> uploadAndComplete(MaterialImport intent, XFile file);
  Future<MaterialImport> find(String id);
  Future<MaterialImport> reimportExisting({
    required String sourceId,
    required LearningMaterialType targetType,
    required String language,
    required String title,
    required String idempotencyKey,
  });
  Future<void> cancel(MaterialImport intent);
}

/// Upload transport intentionally has no account headers, cookies, telemetry
/// interceptor or redirects. Only the server-issued staging grant is used.
final class HttpMaterialImportRepository implements MaterialImportRepository {
  HttpMaterialImportRepository(this.auth, {Dio? uploads})
    : _uploads =
          uploads ??
          Dio(
            BaseOptions(
              followRedirects: false,
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(minutes: 2),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    auth.addListener(_scopeChanged);
  }
  final AuthController auth;
  final Dio _uploads;
  final Map<String, _ImportSnapshot> _snapshots = {};
  static const _snapshotBudgetBytes = 80 * 1024 * 1024;
  int _readingBytes = 0;
  ApiClient get _api => auth.repository.api;

  @override
  Future<MaterialImportCapabilities> capabilities() {
    _purgeExpired();
    return auth.authorizedRead(
      (headers) async => (await _api.getJson(
        '/api/v1/material-import-capabilities',
        MaterialImportCapabilities.fromJson,
        headers: headers,
      )).data,
    );
  }

  @override
  Future<MaterialImport> create({
    required XFile file,
    required LearningMaterialType type,
    required String language,
    required String title,
    required String idempotencyKey,
  }) async {
    final binding = _capture();
    final limits = await capabilities();
    _requireCurrent(binding);
    final capability = limits.forType(type);
    final format = sourceFormat(file.name);
    final size = await file.length();
    if (capability == null ||
        !capability.formats.contains(format) ||
        !capability.languages.contains(language) ||
        size < 1 ||
        size > capability.maxSizeBytes ||
        size > limits.availableBytes) {
      throw const ApiFailure(code: 'INPUT_INVALID');
    }
    // Bound every chunk before copying it, even if the selected native file
    // changes while it is being read. This snapshot is also the upload body.
    if (size > _snapshotBudgetBytes) {
      throw const ApiFailure(code: 'INPUT_INVALID');
    }
    _purgeExpired();
    final retained = _snapshots.values.fold<int>(0, (sum, snapshot) => sum + snapshot.bytes.length);
    if (_readingBytes + retained + size > _snapshotBudgetBytes) {
      // The UI asks the user to finish/cancel their existing import. This local
      // budget never silently cancels a server reservation.
      throw const ApiFailure(code: 'STATE_CONFLICT');
    }
    _readingBytes += size;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (builder.length + chunk.length > size) {
          throw const ApiFailure(code: 'INPUT_INVALID');
        }
        builder.add(chunk);
      }
      final Uint8List bytes = builder.takeBytes();
      _requireCurrent(binding);
      if (bytes.length != size) {
        throw const ApiFailure(code: 'INPUT_INVALID');
      }
      return await auth.authorizedWrite((headers) async {
        _requireCurrent(binding);
        final response = await _api.postJson(
          '/api/v1/material-imports',
          {
            'schema_version': 1,
            'material_type': type.name,
            'language': language,
            'title': title.trim().isEmpty ? null : title.trim(),
            'file': {
              'filename': file.name,
              'format': format,
              'size_bytes': size,
              'sha256': sha256.convert(bytes).toString(),
            },
            'requested_stages': {'extract': true, 'analyze': false},
          },
          MaterialImport.fromJson,
          expectedStatus: 201,
          headers: {...headers, 'Idempotency-Key': idempotencyKey},
        );
        _requireCurrent(binding);
        if (response.data.type != type || response.data.language != language) {
          throw const ApiFailure(code: 'INVALID_RESPONSE');
        }
        if (response.data.status == 'awaiting_upload') {
          if (response.data.upload == null) {
            throw const ApiFailure(code: 'INVALID_RESPONSE');
          }
          final uploadExpiry = response.data.upload!.expiresAt;
          final expiry = response.data.expiresAt.isBefore(uploadExpiry)
              ? response.data.expiresAt
              : uploadExpiry;
          _snapshots[response.data.id] = _ImportSnapshot(
            binding,
            _api.endpoint,
            file.name,
            bytes,
            expiry,
          );
        }
        return response.data;
      });
    } finally {
      _readingBytes -= size;
    }
  }

  @override
  Future<MaterialImport> reimportExisting({
    required String sourceId,
    required LearningMaterialType targetType,
    required String language,
    required String title,
    required String idempotencyKey,
  }) async {
    final binding = _capture();
    final source = wireUuid(sourceId);
    final limits = await capabilities();
    _requireCurrent(binding);
    if (limits.forType(targetType)?.languages.contains(language) != true) {
      throw const ApiFailure(code: 'INPUT_INVALID');
    }
    return auth.authorizedWrite((headers) async {
      _requireCurrent(binding);
      final response = await _api.postJson(
        '/api/v1/material-imports',
        {
          'schema_version': 1,
          'material_type': targetType.name,
          'language': language,
          'title': title.trim().isEmpty ? null : title.trim(),
          'source_material_id': source,
          'requested_stages': {'extract': true, 'analyze': false},
        },
        MaterialImport.fromJson,
        expectedStatus: 201,
        headers: {...headers, 'Idempotency-Key': idempotencyKey},
      );
      _requireCurrent(binding);
      if (response.data.type != targetType ||
          response.data.language != language ||
          response.data.upload != null) {
        throw const ApiFailure(code: 'INVALID_RESPONSE');
      }
      return response.data;
    });
  }

  @override
  Future<MaterialImport> uploadAndComplete(MaterialImport intent, XFile file) async {
    final binding = _capture();
    final upload = intent.upload;
    final snapshot = _snapshots[intent.id];
    if (intent.status != 'awaiting_upload' ||
        upload == null ||
        !intent.expiresAt.isAfter(DateTime.now().toUtc()) ||
        !upload.expiresAt.isAfter(DateTime.now().toUtc())) {
      _snapshots.remove(intent.id);
      throw const ApiFailure(code: 'RESOURCE_EXPIRED');
    }
    if (snapshot == null ||
        !identical(snapshot.binding, binding) ||
        snapshot.filename != file.name ||
        snapshot.endpoint != _api.endpoint) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    final target = snapshot.endpoint.resolveUri(upload.url);
    if (target.origin != snapshot.endpoint.origin ||
        target.path != '/api/v1/uploads/${upload.id}/content' ||
        target.hasQuery ||
        target.userInfo.isNotEmpty ||
        target.hasFragment ||
        upload.headers.keys.any(
          (key) =>
              const {'authorization', 'cookie', 'proxy-authorization'}.contains(key.toLowerCase()),
        )) {
      throw const ApiFailure(code: 'INVALID_RESPONSE');
    }
    final bytes = snapshot.bytes;
    _requireCurrent(binding);
    try {
      await staging.uploadStaging(target, upload.headers, bytes, _uploads);
    } on Object {
      throw const ApiFailure(code: 'NETWORK_ERROR');
    }
    _requireCurrent(binding);
    return auth.authorizedWrite((headers) async {
      _requireCurrent(binding);
      final response = await _api.postJson(
        '/api/v1/uploads/${upload.id}/complete',
        {'expected_revision': intent.revision},
        MaterialImport.fromJson,
        expectedStatus: 202,
        headers: {...headers, 'Idempotency-Key': intent.id},
      );
      _requireCurrent(binding);
      if (response.data.id != intent.id ||
          response.data.type != intent.type ||
          response.data.language != intent.language) {
        throw const ApiFailure(code: 'INVALID_RESPONSE');
      }
      if (response.data.accepted) {
        _snapshots.remove(intent.id);
      }
      return response.data;
    });
  }

  @override
  Future<MaterialImport> find(String id) {
    _purgeExpired();
    return auth.authorizedRead((headers) async {
      final intent = (await _api.getJson(
        '/api/v1/material-imports/${wireUuid(id)}',
        MaterialImport.fromJson,
        headers: headers,
      )).data;
      if (intent.id != id) {
        throw const ApiFailure(code: 'INVALID_RESPONSE');
      }
      if (const {'accepted', 'cancelled', 'expired', 'rejected'}.contains(intent.status)) {
        _snapshots.remove(id);
      }
      return intent;
    });
  }

  @override
  Future<void> cancel(MaterialImport intent) async {
    await auth.authorizedWrite(
      (headers) => _api.deleteEmpty(
        '/api/v1/material-imports/${intent.id}?expected_revision=${intent.revision}',
        headers: headers,
      ),
    );
    _snapshots.remove(intent.id);
  }

  ApiSessionBinding _capture() {
    _purgeExpired();
    final binding = _api.sessionBinding;
    if (!auth.isAuthenticated || binding == null || binding.audience != 'client') {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
    _snapshots.removeWhere((_, snapshot) => !identical(snapshot.binding, binding));
    return binding;
  }

  void _requireCurrent(ApiSessionBinding binding) {
    if (!auth.isAuthenticated || !identical(binding, _api.sessionBinding)) {
      throw const ApiFailure(code: 'SESSION_INVALID');
    }
  }

  void dispose() {
    auth.removeListener(_scopeChanged);
    _snapshots.clear();
    _uploads.close(force: true);
  }

  void _scopeChanged() {
    _purgeExpired();
    if (!auth.isAuthenticated) {
      _snapshots.clear();
    } else {
      _snapshots.removeWhere((_, snapshot) => !identical(snapshot.binding, _api.sessionBinding));
    }
  }

  void _purgeExpired() {
    final now = DateTime.now().toUtc();
    _snapshots.removeWhere((_, snapshot) => !snapshot.expiresAt.isAfter(now));
  }
}

final class _ImportSnapshot {
  const _ImportSnapshot(this.binding, this.endpoint, this.filename, this.bytes, this.expiresAt);
  final ApiSessionBinding binding;
  final Uri endpoint;
  final String filename;
  final Uint8List bytes;
  final DateTime expiresAt;
}

String sourceFormat(String filename) {
  final suffix = filename.split('.').last.toLowerCase();
  return suffix == 'jpg' ? 'jpeg' : suffix;
}

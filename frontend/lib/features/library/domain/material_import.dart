import '../../../core/api/wire.dart';
import 'material_summary.dart';

/// Consumer of backend/app/schemas/material_imports.py.
final class MaterialImportCapability {
  const MaterialImportCapability({
    required this.type,
    required this.formats,
    required this.languages,
    required this.maxSizeBytes,
    this.formatMaxSizeBytes = const {},
  });
  final LearningMaterialType type;
  final List<String> formats;
  final List<String> languages;
  final int maxSizeBytes;
  final Map<String, int> formatMaxSizeBytes;
  int limitFor(String format) {
    final limit = formatMaxSizeBytes[format];
    return limit != null && limit < maxSizeBytes ? limit : maxSizeBytes;
  }

  factory MaterialImportCapability.fromJson(Object? value) {
    final json = wireObject(value);
    final formats = _strings(json['formats']);
    final languages = _strings(json['languages']);
    if (formats.any(
          (format) => !const {'md', 'epub', 'pdf', 'png', 'jpeg', 'webp'}.contains(format),
        ) ||
        languages.any((language) => !const {'ja', 'en'}.contains(language))) {
      throw const FormatException('Invalid import capabilities');
    }
    return MaterialImportCapability(
      type: _type(json['material_type']),
      formats: formats,
      languages: languages,
      maxSizeBytes: _integer(json['max_size_bytes'], minimum: 1),
      formatMaxSizeBytes: json['format_max_size_bytes'] == null
          ? const {}
          : Map.unmodifiable(
              wireObject(json['format_max_size_bytes'])
                  .map((format, limit) => MapEntry(format, _integer(limit, minimum: 1))),
            ),
    );
  }
}

final class MaterialImportCapabilities {
  const MaterialImportCapabilities({
    required this.capabilities,
    required this.quotaBytes,
    required this.usedBytes,
    required this.reservedBytes,
  });
  final List<MaterialImportCapability> capabilities;
  final int quotaBytes;
  final int usedBytes;
  final int reservedBytes;
  int get availableBytes => (quotaBytes - usedBytes - reservedBytes).clamp(0, quotaBytes);

  factory MaterialImportCapabilities.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['schema_version'] != 1 || json['capabilities'] is! List) {
      throw const FormatException('Invalid import capabilities');
    }
    return MaterialImportCapabilities(
      capabilities: List.unmodifiable(
        (json['capabilities'] as List).map(MaterialImportCapability.fromJson),
      ),
      quotaBytes: _integer(json['quota_bytes']),
      usedBytes: _integer(json['used_bytes']),
      reservedBytes: _integer(json['reserved_bytes']),
    );
  }

  MaterialImportCapability? forType(LearningMaterialType type) {
    for (final capability in capabilities) {
      if (capability.type == type) return capability;
    }
    return null;
  }
}

final class StagingUpload {
  const StagingUpload({
    required this.id,
    required this.url,
    required this.headers,
    required this.expiresAt,
  });
  final String id;
  final Uri url;
  final Map<String, String> headers;
  final DateTime expiresAt;

  factory StagingUpload.fromJson(Object? value) {
    final json = wireObject(value);
    if (json['method'] != 'PUT') throw const FormatException('Invalid upload method');
    final headers = wireObject(json['headers']);
    final url = Uri.tryParse(wireString(json['url']));
    if (url == null || url.userInfo.isNotEmpty || url.hasFragment) {
      throw const FormatException('Invalid upload target');
    }
    return StagingUpload(
      id: wireUuid(json['id']),
      url: url,
      headers: Map.unmodifiable(headers.map((key, value) => MapEntry(key, wireString(value)))),
      expiresAt: wireUtc(json['expires_at']),
    );
  }
}

final class MaterialImport {
  const MaterialImport({
    required this.id,
    required this.revision,
    required this.type,
    required this.language,
    required this.status,
    required this.expiresAt,
    this.upload,
    this.materialId,
    this.jobId,
    this.errorCode,
  });
  final String id;
  final int revision;
  final LearningMaterialType type;
  final String language;
  final String status;
  final DateTime expiresAt;
  final StagingUpload? upload;
  final String? materialId;
  final String? jobId;
  final String? errorCode;
  bool get accepted => status == 'accepted' && materialId != null && jobId != null;

  factory MaterialImport.fromJson(Object? value) {
    final json = wireObject(value);
    final status = wireString(json['status']);
    final language = wireString(json['language']);
    if (!const {
          'awaiting_upload',
          'verifying',
          'accepted',
          'cancelled',
          'rejected',
          'expired',
        }.contains(status) ||
        !const {'ja', 'en'}.contains(language)) {
      throw const FormatException('Invalid import state');
    }
    final materialId = json['material_id'] == null ? null : wireUuid(json['material_id']);
    final jobId = json['job_id'] == null ? null : wireUuid(json['job_id']);
    final upload = json['upload'] == null ? null : StagingUpload.fromJson(json['upload']);
    if ((status == 'accepted') != (materialId != null && jobId != null) ||
        (status != 'accepted' && (materialId != null || jobId != null)) ||
        (upload != null && status != 'awaiting_upload')) {
      throw const FormatException('Inconsistent import state');
    }
    return MaterialImport(
      id: wireUuid(json['id']),
      revision: _integer(json['revision'], minimum: 1),
      type: _type(json['material_type']),
      language: language,
      status: status,
      expiresAt: wireUtc(json['expires_at']),
      upload: upload,
      materialId: materialId,
      jobId: jobId,
      errorCode: json['error_code'] == null ? null : wireString(json['error_code']),
    );
  }
}

int _integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum) throw const FormatException('Invalid import count');
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List) throw const FormatException('Invalid import choices');
  return List.unmodifiable(value.map(wireString));
}

LearningMaterialType _type(Object? value) {
  if (!LearningMaterialType.values.any((type) => type.name == value)) {
    throw const FormatException('Invalid material type');
  }
  return LearningMaterialType.values.byName(value as String);
}

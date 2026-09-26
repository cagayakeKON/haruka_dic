import '../../generated/api_catalog.dart';
import 'wire.dart';

/// Reviewed handwritten transition; schema fingerprints guard drift.
final class ResponseMeta {
  const ResponseMeta(this.requestId);
  factory ResponseMeta.fromJson(Object? value) =>
      ResponseMeta(wireUuid(wireObject(value)['request_id']));
  final String requestId;
}

final class SuccessResponse<T> {
  const SuccessResponse({required this.data, required this.meta});
  factory SuccessResponse.fromJson(Object? value, T Function(Object?) decode) {
    final json = wireObject(value);
    return SuccessResponse(data: decode(json['data']), meta: ResponseMeta.fromJson(json['meta']));
  }
  final T data;
  final ResponseMeta meta;
}

final class PageResponse<T> {
  const PageResponse({required this.data, required this.meta, required this.nextCursor});
  factory PageResponse.fromJson(Object? value, T Function(Object?) decode) {
    final json = wireObject(value);
    final meta = wireObject(json['meta']);
    final items = json['data'];
    final hasMore = meta['has_more'];
    final cursor = meta['next_cursor'];
    if (items is! List<Object?> ||
        hasMore is! bool ||
        !meta.containsKey('next_cursor') ||
        (hasMore && (cursor is! String || cursor.isEmpty)) ||
        (!hasMore && cursor != null)) {
      throw const FormatException('Invalid page envelope');
    }
    return PageResponse(
      data: List<T>.unmodifiable(items.map(decode)),
      meta: ResponseMeta.fromJson(meta),
      nextCursor: cursor as String?,
    );
  }
  final List<T> data;
  final ResponseMeta meta;
  final String? nextCursor;
  bool get hasMore => nextCursor != null;
}

final class FieldFailure {
  const FieldFailure({required this.code, required this.source, required this.path});
  factory FieldFailure.fromJson(Object? value) {
    final json = wireObject(value);
    final path = json['path'];
    final source = wireString(json['source']);
    if (path is! List<Object?> ||
        path.any((part) => part is! String && (part is! int || part < 0)) ||
        !const {'body', 'query', 'path', 'header', 'cookie'}.contains(source)) {
      throw const FormatException('Invalid field error');
    }
    return FieldFailure(
      code: wireString(json['code']),
      source: source,
      path: List<Object>.unmodifiable(path.cast<Object>()),
    );
  }
  final String code;
  final String source;
  final List<Object> path;
}

final class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    this.meta,
    this.fields = const [],
    this.currentRevision,
    this.retryAfter,
  });

  factory ApiFailure.fromJson(Object? value, {Duration? retryAfter}) {
    final json = wireObject(value);
    final error = wireObject(json['error']);
    final fields = error['field_errors'] ?? const <Object?>[];
    if (fields is! List<Object?> || fields.length > 50) {
      throw const FormatException('Invalid field errors');
    }
    final code = wireString(error['code']);
    int? revision;
    final details = error['details'];
    if (details != null && code == 'REVISION_CONFLICT') {
      final parsed = wireObject(details);
      final current = parsed['current_revision'];
      if (parsed['kind'] != 'revision_conflict' || current is! int || current < 0) {
        throw const FormatException('Invalid conflict details');
      }
      revision = current;
    }
    return ApiFailure(
      code: ApiCatalog.errorCodes.contains(code) ? code : 'UNKNOWN_ERROR',
      retryAfter: retryAfter,
      meta: ResponseMeta.fromJson(json['meta']),
      fields: List<FieldFailure>.unmodifiable(fields.map(FieldFailure.fromJson)),
      currentRevision: revision,
    );
  }

  final String code;
  final Duration? retryAfter;
  final ResponseMeta? meta;
  final List<FieldFailure> fields;
  final int? currentRevision;

  // Never retain or render remote message/body/request/URL, including proxy HTML.
  @override
  String toString() => 'ApiFailure($code)';
}

final class HealthRead {
  const HealthRead();
  factory HealthRead.fromJson(Object? value) {
    if (wireObject(value)['status'] != 'ok') throw const FormatException('Invalid health status');
    return const HealthRead();
  }
}

final class MetaRead {
  const MetaRead({required this.instanceId, required this.apiVersion, required this.release});

  factory MetaRead.fromJson(Object? value) {
    final json = wireObject(value);
    return MetaRead(
      instanceId: wireString(json['instance_id']),
      apiVersion: wireString(json['api_version']),
      release: wireString(json['release']),
    );
  }

  final String instanceId;
  final String apiVersion;
  final String release;
}

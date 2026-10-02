import '../../../core/api/wire.dart';

final class NotificationReadAllResult {
  const NotificationReadAllResult(this.changedCount, this.unreadCount);
  final int changedCount, unreadCount;
  factory NotificationReadAllResult.fromJson(Object? value) {
    final json = wireObject(value);
    final changed = json['changed_count'], unread = json['unread_count'];
    if (changed is! int || changed < 0 || unread is! int || unread < 0) {
      throw const FormatException('Invalid notification read result');
    }
    return NotificationReadAllResult(changed, unread);
  }
}

final class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.title,
    required this.detail,
    required this.route,
    required this.createdAt,
    this.resourceId,
    this.resourceRevision,
    this.readAt,
    this.messageCode,
    this.jobId,
  });

  final String id;
  final String title;
  final String detail;
  final String route;
  final DateTime createdAt;
  final String? resourceId;
  final int? resourceRevision;
  final DateTime? readAt;
  final String? messageCode;
  final String? jobId;

  bool get serverRecord => messageCode != null;

  /// Remote text and routes are never rendered. Only registered message codes
  /// and an owner-scoped material reference cross the API boundary.
  factory NotificationRecord.fromApiJson(Object? value) {
    final json = wireObject(value);
    final kind = json['notification_kind'];
    final code = wireString(json['message_code']);
    final available = json['resource_available'];
    final parameters = wireObject(json['safe_parameters']);
    final version = json['resource_version'];
    final id = json['resource_id'];
    final route = json['route_key'];
    if (json['schema_version'] != 1 ||
        !const {'completed', 'failed', 'needs_review'}.contains(kind) ||
        parameters.isNotEmpty ||
        json['resource_kind'] != 'material' ||
        available is! bool ||
        (available &&
            (id == null ||
                version is! int ||
                version < 1 ||
                route != 'material' ||
                code != 'material.import.$kind')) ||
        (!available &&
            (id != null ||
                version != null ||
                route != null ||
                code != 'notification.resource_unavailable'))) {
      throw const FormatException('Invalid notification projection');
    }
    return NotificationRecord(
      id: wireUuid(json['id']),
      title: '',
      detail: '',
      route: available ? 'material' : '',
      createdAt: wireUtc(json['created_at']),
      readAt: json['read_at'] == null ? null : wireUtc(json['read_at']),
      resourceId: available ? wireUuid(id) : null,
      resourceRevision: version as int?,
      messageCode: code,
      jobId: wireUuid(json['job_id']),
    );
  }

  NotificationRecord read(DateTime at) => NotificationRecord(
    id: id,
    title: title,
    detail: detail,
    route: route,
    createdAt: createdAt,
    resourceId: resourceId,
    resourceRevision: resourceRevision,
    readAt: at,
    messageCode: messageCode,
    jobId: jobId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'route_key': route,
    'resource_id': resourceId,
    'resource_revision': resourceRevision,
    'created_at': createdAt.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
    'message_code': messageCode,
    'job_id': jobId,
  };

  factory NotificationRecord.fromJson(Map<String, Object?> json) => NotificationRecord(
    id: json['id'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String,
    route: json['route_key'] as String,
    resourceId: json['resource_id'] as String?,
    resourceRevision: json['resource_revision'] as int?,
    createdAt: DateTime.parse(json['created_at'] as String),
    readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
    messageCode: json['message_code'] as String?,
    jobId: json['job_id'] as String?,
  );
}

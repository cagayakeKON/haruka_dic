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
  });

  final String id;
  final String title;
  final String detail;
  final String route;
  final DateTime createdAt;
  final String? resourceId;
  final int? resourceRevision;
  final DateTime? readAt;

  NotificationRecord read(DateTime at) => NotificationRecord(
    id: id,
    title: title,
    detail: detail,
    route: route,
    createdAt: createdAt,
    resourceId: resourceId,
    resourceRevision: resourceRevision,
    readAt: at,
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
  );
}

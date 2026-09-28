import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/notification_record.dart';

enum NotificationListStatus { initial, loading, ready, stale, blocked, failed }

final class NotificationListQuery {
  const NotificationListQuery({this.unreadOnly = false, this.cursor = ''});

  final bool unreadOnly;
  final String cursor;

  String get key => jsonEncode([unreadOnly, cursor]);

  factory NotificationListQuery.fromKey(String key) {
    final parts = jsonDecode(key);
    if (parts is! List || parts.length != 2 || parts[0] is! bool || parts[1] is! String) {
      throw const FormatException('Invalid notification list query');
    }
    return NotificationListQuery(unreadOnly: parts[0] as bool, cursor: parts[1] as String);
  }
}

/// The source issues this opaque reference with its list snapshot. Production
/// read-all will pass the server-issued snapshot token back to the API.
final class NotificationListSnapshot {
  NotificationListSnapshot({
    required List<NotificationRecord> items,
    required this.unreadCount,
    required this.snapshotToken,
  }) : items = List.unmodifiable(items);

  final List<NotificationRecord> items;
  final int unreadCount;
  final String snapshotToken;

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'unread_count': unreadCount,
    'snapshot_token': snapshotToken,
  };

  factory NotificationListSnapshot.fromJson(Map<String, Object?> json) {
    final rows = json['items'];
    if (rows is! List) throw const FormatException('Notification items missing');
    return NotificationListSnapshot(
      items: [
        for (final row in rows) NotificationRecord.fromJson((row as Map).cast<String, Object?>()),
      ],
      unreadCount: json['unread_count'] as int,
      snapshotToken: json['snapshot_token'] as String,
    );
  }
}

abstract interface class NotificationRepository implements Listenable {
  NotificationListStatus get status;
  List<NotificationRecord> get items;
  int get unreadCount;
  bool get busy;
  Object? get lastError;

  Future<void> refresh({
    NotificationListQuery query = const NotificationListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  });

  Future<void> markRead(String id);
  Future<void> markAllRead();
}

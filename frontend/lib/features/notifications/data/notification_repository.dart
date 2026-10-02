import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';

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
    this.nextCursor,
    this.snapshotExpiresAt,
  }) : items = List.unmodifiable(items);

  final List<NotificationRecord> items;
  final int unreadCount;
  final String snapshotToken;
  final String? nextCursor;
  final DateTime? snapshotExpiresAt;

  factory NotificationListSnapshot.fromApiPage(PageResponse<NotificationRecord> page) {
    final meta = page.pageMetadata;
    final count = meta['unread_count'];
    final token = wireString(meta['snapshot_token']);
    if (count is! int ||
        count < 0 ||
        token.isEmpty ||
        token.length > 2048 ||
        (page.nextCursor?.length ?? 0) > 2048 ||
        page.data.length > 50 ||
        page.data.map((item) => item.id).toSet().length != page.data.length) {
      throw const FormatException('Invalid notification page metadata');
    }
    return NotificationListSnapshot(
      items: page.data,
      unreadCount: count,
      snapshotToken: token,
      nextCursor: page.nextCursor,
      snapshotExpiresAt: wireUtc(meta['snapshot_expires_at']),
    );
  }

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'unread_count': unreadCount,
    'snapshot_token': snapshotToken,
    'next_cursor': nextCursor,
    'snapshot_expires_at': snapshotExpiresAt?.toIso8601String(),
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
      nextCursor: json['next_cursor'] as String?,
      snapshotExpiresAt: json['snapshot_expires_at'] == null
          ? null
          : DateTime.parse(json['snapshot_expires_at'] as String),
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

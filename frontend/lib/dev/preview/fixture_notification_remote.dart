import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/cache/cache_coordinator.dart';
import '../../core/cache/cache_models.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/notifications/domain/notification_record.dart';
import '../../features/notifications/domain/notification_target.dart';
import 'fixture_store.dart';

/// Development source for the same notification repository used by the page.
final class FixtureNotificationRemote implements CacheRemote<NotificationListSnapshot> {
  const FixtureNotificationRemote(this.store, {this.permits});

  final PreviewFixtureStore store;
  final bool Function(String action)? permits;

  void _requireRead(CacheResource resource) {
    if (resource.action != 'client.notification.read' ||
        permits?.call('client.notification.read') == false) {
      throw const CacheBlocked('forbidden');
    }
  }

  void _requireUpdate() {
    if (permits?.call('client.notification.read') == false ||
        permits?.call('client.notification.update') == false) {
      throw const CacheBlocked('forbidden');
    }
  }

  NotificationRecord _visibleNotification(NotificationRecord item) {
    final available = store.materials.any(
      (material) => store.canReadMaterial(material.id) && notificationTargetMatches(item, material),
    );
    return NotificationRecord(
      id: item.id,
      // The presentation localizes the unavailable state. Source titles must
      // not travel in a snapshot after its target disappears.
      title: available ? item.title : '',
      detail: available ? item.detail : '',
      route: item.route,
      createdAt: item.createdAt,
      readAt: item.readAt,
      resourceId: available ? item.resourceId : null,
      resourceRevision: available ? item.resourceRevision : null,
    );
  }

  NotificationListSnapshot _snapshot(CacheResource resource) {
    final query = NotificationListQuery.fromKey(resource.queryKey);
    final rows = [
      for (final item in store.notifications)
        if (!query.unreadOnly || item.readAt == null) _visibleNotification(item),
    ];
    // The preview freezes exactly the visible set. A later new message is not
    // included in read-all even when its created_at is older.
    return NotificationListSnapshot(
      items: rows,
      unreadCount: store.unreadCount,
      snapshotToken: jsonEncode([for (final item in rows) item.id]),
    );
  }

  CacheVersion _version(NotificationListSnapshot snapshot) {
    final digest = sha256.convert(utf8.encode(jsonEncode(snapshot.toJson()))).toString();
    return CacheVersion(
      resource: digest,
      representation: 'notification-summary-v1',
      artifact: digest,
    );
  }

  @override
  Future<CachePayload<NotificationListSnapshot>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    _requireRead(resource);
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final snapshot = _snapshot(resource);
    return CachePayload(value: snapshot, version: _version(snapshot));
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async {
    _requireRead(resource);
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    final version = _version(_snapshot(resource));
    return CacheValidation(
      state: known.resource == version.resource ? ValidationState.same : ValidationState.changed,
      version: version,
    );
  }

  Future<void> markRead(String id) async {
    _requireUpdate();
    if (!store.notifications.any((item) => item.id == id)) {
      throw ArgumentError.value(id, 'id', 'Notification unavailable');
    }
    store.readNotification(id);
  }

  Future<void> markAllRead(String snapshotToken) async {
    _requireUpdate();
    final ids = jsonDecode(snapshotToken);
    if (ids is! List || ids.any((id) => id is! String)) {
      throw const FormatException('Invalid notification snapshot');
    }
    for (final id in ids.cast<String>()) {
      store.readNotification(id);
    }
  }
}

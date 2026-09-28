import 'dart:async';

import 'package:flutter/services.dart';

import '../data/notification_repository.dart';

abstract interface class NotificationShade {
  Future<void> showUnreadCount(int count);
  Future<void> clear();
  Future<bool> consumeOpenRequest();
  void setOpenHandler(VoidCallback? handler);
}

/// Sends only a generic unread count to Android. Message content never crosses
/// the system notification boundary.
final class AndroidNotificationShade implements NotificationShade {
  AndroidNotificationShade({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.haruka.dictionary/notifications');

  final MethodChannel _channel;

  @override
  Future<void> showUnreadCount(int count) async {
    await _channel.invokeMethod<void>('showUnreadCount', count);
  }

  @override
  Future<void> clear() async {
    await _channel.invokeMethod<void>('clear');
  }

  @override
  Future<bool> consumeOpenRequest() async =>
      await _channel.invokeMethod<bool>('consumeOpenRequest') ?? false;

  @override
  void setOpenHandler(VoidCallback? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'openNotifications') {
                await consumeOpenRequest();
                handler();
              }
            },
    );
  }
}

/// Reads the authorized repository before showing a native summary. A changed
/// account binding invalidates in-flight reads and removes the old summary.
final class NotificationShadeController {
  NotificationShadeController({
    required this.repository,
    required this.shade,
    required this.currentBinding,
    required this.onOpen,
  });

  final NotificationRepository repository;
  final NotificationShade shade;
  final String? Function() currentBinding;
  final VoidCallback onOpen;

  String? _binding;
  int _generation = 0;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshQueued = false;

  Future<void> start() async {
    shade.setOpenHandler(onOpen);
    repository.addListener(_onRepositoryChanged);
    try {
      // A previous process may have left a summary for an account whose
      // current identity is not established yet.
      await shade.clear();
      if (await shade.consumeOpenRequest() && !_disposed) onOpen();
    } on PlatformException {
      // The in-app message page remains available when the native surface fails.
    }
    await synchronize();
  }

  void _onRepositoryChanged() {
    if (_disposed || currentBinding() != _binding || _binding == null) return;
    if (repository.status == NotificationListStatus.loading ||
        repository.status == NotificationListStatus.initial) {
      return;
    }
    unawaited(_publishCurrentSnapshot());
  }

  Future<void> _publishCurrentSnapshot() async {
    final generation = _generation;
    final binding = _binding;
    if (binding == null || currentBinding() != binding || _disposed) return;
    try {
      if (repository.status == NotificationListStatus.ready) {
        await shade.showUnreadCount(repository.unreadCount);
      } else {
        await shade.clear();
      }
      if (!_disposed && (generation != _generation || currentBinding() != binding)) {
        await shade.clear();
      }
    } on Object {
      // The in-app list remains the fallback when the system surface fails.
    }
  }

  Future<void> synchronize({bool refresh = true}) async {
    if (_disposed) return;
    final binding = currentBinding();
    if (binding != _binding) {
      _binding = binding;
      _generation++;
      try {
        await shade.clear();
      } on PlatformException {
        // Account scoping still prevents publishing the old repository snapshot.
      }
    }
    if (binding == null || !refresh) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      await repository.refresh(force: true, preserveCurrent: true);
      if (_disposed || generation != _generation || currentBinding() != binding) return;
      await _publishCurrentSnapshot();
    } on Object {
      // A rejected permission or unavailable native channel does not remove
      // the existing "我的 > 消息" route.
    } finally {
      _refreshing = false;
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        unawaited(synchronize());
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    repository.removeListener(_onRepositoryChanged);
    shade.setOpenHandler(null);
    unawaited(shade.clear().catchError((Object _) {}));
  }
}

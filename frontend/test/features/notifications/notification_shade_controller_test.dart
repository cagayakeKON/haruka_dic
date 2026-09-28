import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';
import 'package:haruka/features/notifications/domain/notification_record.dart';
import 'package:haruka/features/notifications/platform/notification_shade.dart';

void main() {
  test('startup without confirmed identity removes prior native summary', () async {
    final repository = _Repository();
    final shade = _Shade();
    final controller = NotificationShadeController(
      repository: repository,
      shade: shade,
      currentBinding: () => null,
      onOpen: () {},
    );
    await controller.start();
    expect(shade.clears, 1);
    expect(shade.shown, isEmpty);
    expect(repository.refreshes, 0);
    controller.dispose();
  });

  test('native summary reads only authorized count and tap opens message route', () async {
    final repository = _Repository();
    final shade = _Shade();
    String? binding = 'account-a';
    var opens = 0;
    final controller = NotificationShadeController(
      repository: repository,
      shade: shade,
      currentBinding: () => binding,
      onOpen: () => opens++,
    );
    await controller.start();
    expect(shade.shown, [2]);
    shade.open?.call();
    expect(opens, 1);

    repository.unread = 0;
    await controller.synchronize();
    expect(shade.shown, [2, 0]);
    binding = 'account-b';
    await controller.synchronize();
    expect(shade.clears, 3);
    controller.dispose();
  });

  test('account switch clears native summary before a stale refresh completes', () async {
    final repository = _Repository();
    final shade = _Shade();
    String? binding = 'account-a';
    final controller = NotificationShadeController(
      repository: repository,
      shade: shade,
      currentBinding: () => binding,
      onOpen: () {},
    );
    await controller.start();
    final delayed = Completer<void>();
    repository.nextRefresh = delayed.future;
    final oldRead = controller.synchronize();
    binding = null;
    await controller.synchronize();
    delayed.complete();
    await oldRead;
    expect(shade.shown, [2]);
    expect(shade.clears, 3);
    controller.dispose();
  });

  test('committed read state updates the shade without refetching', () async {
    final repository = _Repository();
    final shade = _Shade();
    final controller = NotificationShadeController(
      repository: repository,
      shade: shade,
      currentBinding: () => 'account-a',
      onOpen: () {},
    );
    await controller.start();
    final reads = repository.refreshes;
    repository.unread = 0;
    repository.publish();
    await Future<void>.delayed(Duration.zero);
    expect(shade.shown.last, 0);
    expect(repository.refreshes, reads);

    repository.currentStatus = NotificationListStatus.blocked;
    repository.publish();
    await Future<void>.delayed(Duration.zero);
    expect(shade.clears, 3);
    controller.dispose();
  });

  test('background account transition clears without fetching new account', () async {
    final repository = _Repository();
    final shade = _Shade();
    String? binding = 'account-a';
    final controller = NotificationShadeController(
      repository: repository,
      shade: shade,
      currentBinding: () => binding,
      onOpen: () {},
    );
    await controller.start();
    final reads = repository.refreshes;
    binding = 'account-b';
    await controller.synchronize(refresh: false);
    expect(shade.clears, 3);
    expect(repository.refreshes, reads);
    await controller.synchronize();
    expect(repository.refreshes, reads + 1);
    controller.dispose();
  });
}

final class _Repository extends ChangeNotifier implements NotificationRepository {
  int unread = 2;
  int refreshes = 0;
  NotificationListStatus currentStatus = NotificationListStatus.ready;
  Future<void>? nextRefresh;

  void publish() => notifyListeners();

  @override
  NotificationListStatus get status => currentStatus;
  @override
  List<NotificationRecord> get items => const [];
  @override
  int get unreadCount => unread;
  @override
  bool get busy => false;
  @override
  Object? get lastError => null;

  @override
  Future<void> refresh({
    NotificationListQuery query = const NotificationListQuery(),
    bool force = false,
    bool preserveCurrent = false,
  }) async {
    refreshes++;
    final pending = nextRefresh;
    nextRefresh = null;
    if (pending != null) await pending;
  }

  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

final class _Shade implements NotificationShade {
  final shown = <int>[];
  int clears = 0;
  VoidCallback? open;

  @override
  Future<void> showUnreadCount(int count) async => shown.add(count);
  @override
  Future<void> clear() async => clears++;
  @override
  Future<bool> consumeOpenRequest() async => false;
  @override
  void setOpenHandler(VoidCallback? handler) => open = handler;
}

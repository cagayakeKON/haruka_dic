import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';
import 'package:haruka/features/notifications/domain/notification_record.dart';

import '../../support/preview_test_app.dart';

class _CountingNotificationRepository extends ChangeNotifier implements NotificationRepository {
  int refreshCount = 0;
  Completer<void>? pendingRefresh;
  bool clearOnRefresh = true;
  NotificationListStatus visibleStatus = NotificationListStatus.ready;
  List<NotificationRecord> visibleItems = const [];

  @override
  NotificationListStatus get status => visibleStatus;

  @override
  List<NotificationRecord> get items => visibleItems;

  @override
  int get unreadCount => 0;

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
    refreshCount++;
    if (!preserveCurrent && clearOnRefresh) {
      visibleStatus = NotificationListStatus.loading;
      notifyListeners();
    }
    final pending = pendingRefresh;
    if (pending != null) await pending.future;
    visibleStatus = NotificationListStatus.ready;
    notifyListeners();
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

void main() {
  testWidgets('notification dialog does not gate or refetch a visible notification', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CountingNotificationRepository()
      ..visibleItems = [
        NotificationRecord(
          id: 'visible-notice',
          title: 'Visible private title',
          detail: 'Visible private detail',
          route: 'novel',
          resourceId: 'material-1',
          resourceRevision: 1,
          createdAt: DateTime.utc(2026, 9, 27),
        ),
      ];
    addTearDown(repository.dispose);
    await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
    router.go(AppRoutes.mockNotifications);
    await tester.pumpAndSettle();
    final notice = tester.element(find.text('Visible private title'));
    final reads = repository.refreshCount;
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Visible private title')),
        builder: (_) => const AlertDialog(title: Text('notification dialog')),
      ),
    );
    await tester.pump();
    expect(tester.element(find.text('Visible private title')), same(notice));
    expect(repository.refreshCount, reads);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('Visible private title')), same(notice));
    expect(repository.refreshCount, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification refresh runs only while its route and app are visible', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _CountingNotificationRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
      router.go(AppRoutes.mockNotifications);
      await tester.pumpAndSettle();
      expect(repository.refreshCount, 1);

      await tester.pump(const Duration(seconds: 30));
      expect(repository.refreshCount, 2);
      expect(repository.status, NotificationListStatus.ready);

      unawaited(router.push<void>(AppRoutes.mockJobs));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(repository.refreshCount, 2);
      expect(
        repository.status,
        NotificationListStatus.ready,
        reason: 'A slow periodic update keeps the current list visible',
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(repository.refreshCount, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.refreshCount, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.refreshCount, 4);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a slow refresh is not restarted by the timer and route return queues one recheck', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _CountingNotificationRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
      router.go(AppRoutes.mockNotifications);
      await tester.pumpAndSettle();
      expect(repository.refreshCount, 1);

      final pending = Completer<void>();
      repository.pendingRefresh = pending;
      await tester.pump(const Duration(seconds: 30));
      expect(repository.refreshCount, 2);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.refreshCount, 2);

      unawaited(router.push<void>(AppRoutes.mockJobs));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.refreshCount, 2);

      repository.pendingRefresh = null;
      pending.complete();
      await tester.pump();
      expect(repository.refreshCount, 3);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('foreground revalidation hides a stale private notification until it finishes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CountingNotificationRepository()
      ..visibleItems = [
        NotificationRecord(
          id: 'private-notice',
          title: 'Old private title',
          detail: 'Old private detail',
          route: 'novel',
          resourceId: 'material-1',
          resourceRevision: 1,
          createdAt: DateTime.utc(2026, 9, 27),
        ),
      ];
    addTearDown(repository.dispose);
    await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
    router.go(AppRoutes.mockNotifications);
    await tester.pumpAndSettle();
    expect(find.text('Old private title'), findsOneWidget);

    final pending = Completer<void>();
    repository.pendingRefresh = pending;
    repository.clearOnRefresh = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Old private title'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.visibleItems = const [];
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Old private title'), findsNothing);
    expect(find.text('暂无消息'), findsOneWidget);
  });

  testWidgets('returning to the notification route gates stale details during revalidation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CountingNotificationRepository()
      ..visibleItems = [
        NotificationRecord(
          id: 'private-notice',
          title: 'Old private title',
          detail: 'Old private detail',
          route: 'novel',
          resourceId: 'material-1',
          resourceRevision: 1,
          createdAt: DateTime.utc(2026, 9, 27),
        ),
      ];
    addTearDown(repository.dispose);
    await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
    router.go(AppRoutes.mockNotifications);
    await tester.pumpAndSettle();
    expect(find.text('Old private title'), findsOneWidget);

    unawaited(router.push<void>(AppRoutes.mockJobs));
    await tester.pumpAndSettle();
    final pending = Completer<void>();
    repository.pendingRefresh = pending;
    repository.clearOnRefresh = false;
    router.pop();
    await tester.pump();
    expect(find.text('Old private title'), findsNothing);

    repository.visibleItems = const [];
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Old private title'), findsNothing);
    expect(find.text('暂无消息'), findsOneWidget);
  });
}

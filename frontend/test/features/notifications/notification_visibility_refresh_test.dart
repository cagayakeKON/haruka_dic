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
  setUpAll(initializeTestDatabase);
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

  testWidgets('ready notifications retain widgets across timer, resize, route return and resume', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _CountingNotificationRepository()
        ..visibleItems = [
          NotificationRecord(
            id: 'visible-notice',
            title: 'Retained notice',
            detail: 'Safe detail',
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
      final notice = tester.element(find.text('Retained notice'));
      expect(repository.refreshCount, 0);
      await tester.pump(const Duration(seconds: 60));
      expect(repository.refreshCount, 0);
      tester.view.physicalSize = const Size(410, 844);
      await tester.pumpAndSettle();
      expect(tester.element(find.text('Retained notice')), same(notice));
      unawaited(router.push<void>(AppRoutes.mockJobs));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.text('Retained notice')), same(notice));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 60));
      expect(repository.refreshCount, 0);
      expect(tester.element(find.text('Retained notice')), same(notice));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'missing notifications load once and navigation does not duplicate an in-flight read',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final repository = _CountingNotificationRepository()
          ..visibleStatus = NotificationListStatus.initial;
        final pending = Completer<void>();
        repository.pendingRefresh = pending;
        addTearDown(repository.dispose);
        await tester.pumpWidget(buildTestPreviewApp(notificationRepository: repository));
        await tester.pumpAndSettle();
        final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));
        router.go(AppRoutes.mockNotifications);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(repository.refreshCount, 1);
        await tester.pump(const Duration(seconds: 60));
        expect(repository.refreshCount, 1);
        unawaited(router.push<void>(AppRoutes.mockJobs));
        await tester.pump(const Duration(milliseconds: 400));
        router.pop();
        await tester.pump(const Duration(milliseconds: 400));
        expect(repository.refreshCount, 1);
        repository.pendingRefresh = null;
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('暂无消息'), findsOneWidget);
        expect(repository.refreshCount, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

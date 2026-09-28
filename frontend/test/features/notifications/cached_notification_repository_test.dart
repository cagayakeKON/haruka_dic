import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_notification_remote.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/features/notifications/data/cached_notification_repository.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';
import 'package:haruka/features/notifications/domain/notification_record.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'cached_notification_repository_test.mocks.dart';

@GenerateNiceMocks([MockSpec<CacheRemote<NotificationListSnapshot>>(as: #MockNotificationRemote)])
void main() {
  late CacheCoordinator cache;

  setUp(() async {
    cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'notification-test',
        userId: 'account-a',
        audience: 'client',
        sessionRef: 'session-a',
      ),
    );
    addTearDown(cache.closeScope);
  });

  test('mutable list stays in memory and read/read-all refetch committed state', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: remote.markRead,
      readAllSource: remote.markAllRead,
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);

    await repository.refresh();
    expect(repository.status, NotificationListStatus.ready);
    expect(repository.items, hasLength(3));
    expect(repository.unreadCount, 2);
    expect((await cache.usage()).textBytes, 0);

    await repository.markRead(store.notifications.first.id);
    expect(repository.items.first.readAt, isNotNull);
    expect(repository.unreadCount, 1);

    await repository.markAllRead();
    expect(repository.unreadCount, 0);
    expect(repository.items.every((item) => item.readAt != null), isTrue);
    expect((await cache.usage()).textBytes, 0);
    expect(
      notificationListResourceFor(const NotificationListQuery()).action,
      'client.notification.read',
    );
  });

  test('material list mutations do not refetch unrelated notifications', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final source = FixtureNotificationRemote(store);
    final remote = MockNotificationRemote();
    provideDummy<CachePayload<NotificationListSnapshot>>(
      await source.fetch(notificationListResourceFor(const NotificationListQuery()), CancelToken()),
    );
    when(remote.fetch(any, any)).thenAnswer(
      (invocation) => source.fetch(
        invocation.positionalArguments[0] as CacheResource,
        invocation.positionalArguments[1] as CancelToken,
      ),
    );
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: source.markRead,
      readAllSource: source.markAllRead,
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    await cache.applyCommittedMutation({'material:list'});
    cache.handleExternalCacheHint('invalidate', {'material:list'});
    await Future<void>.delayed(Duration.zero);
    verify(remote.fetch(any, any)).called(1);
    expect(repository.status, NotificationListStatus.ready);
  });

  test('read-all uses the visible snapshot and does not include a later arrival', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final snapshot = await remote.fetch(
      notificationListResourceFor(const NotificationListQuery()),
      CancelToken(),
    );
    store.notifications.add(
      NotificationRecord(
        id: 'new-later-message',
        title: 'Later',
        detail: 'Later',
        route: 'textbook',
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    );
    await remote.markAllRead(snapshot.value.snapshotToken);
    expect(store.notifications.last.readAt, isNull);
    expect(store.notifications.take(3).every((item) => item.readAt != null), isTrue);
  });

  test('deleted notification target is not rebound to another material of the same type', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final original = store.materials.first;
    store.deleteMaterial(original.id);
    store.importMaterial(original.type, 'Replacement', original.language);

    final snapshot = await remote.fetch(
      notificationListResourceFor(const NotificationListQuery()),
      CancelToken(),
    );
    expect(snapshot.value.items.first.resourceId, isNull);
    expect(snapshot.value.items.first.title, isEmpty);
    expect(snapshot.value.items.first.detail, isEmpty);
    expect(snapshot.value.items.first.id, store.notifications.first.id);
  });

  test('revoked, old-version and unknown notification targets contain no source text', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final novel = store.materials.first;
    store.revokeMaterialRead(novel.id);
    final textbook = store.materials[1];
    store.materials[1] = MaterialSummary.fromJson({
      ...textbook.toJson(),
      'revision': textbook.revision + 1,
    });
    store.notifications.add(
      NotificationRecord(
        id: 'unknown-target',
        title: 'Private title',
        detail: 'Private detail',
        route: 'unsupported',
        resourceId: novel.id,
        resourceRevision: novel.revision,
        createdAt: DateTime.utc(2026, 9, 27),
      ),
    );

    final snapshot = await remote.fetch(
      notificationListResourceFor(const NotificationListQuery()),
      CancelToken(),
    );
    for (final item in [
      snapshot.value.items[0],
      snapshot.value.items[2],
      snapshot.value.items.last,
    ]) {
      expect(item.resourceId, isNull);
      expect(item.title, isEmpty);
      expect(item.detail, isEmpty);
    }
    expect(snapshot.value.items[1].resourceId, isNotNull);
  });

  test('preview source enforces read and update actions', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final allowed = <String>{'client.notification.read'};
    final remote = FixtureNotificationRemote(store, permits: allowed.contains);
    final valid = notificationListResourceFor(const NotificationListQuery());
    const wrongAction = CacheResource(
      kind: 'notification_list',
      id: 'list',
      projection: 'notification-summary-v1',
      action: 'material.list',
      sourceBinding: 'notification:list',
      queryKey: '[false,""]',
    );
    await expectLater(remote.fetch(wrongAction, CancelToken()), throwsA(isA<CacheBlocked>()));
    final initial = await remote.fetch(valid, CancelToken());
    await expectLater(remote.markRead(store.notifications.first.id), throwsA(isA<CacheBlocked>()));
    await expectLater(
      remote.markAllRead(initial.value.snapshotToken),
      throwsA(isA<CacheBlocked>()),
    );
    expect(store.unreadCount, 2);

    allowed.clear();
    await expectLater(remote.fetch(valid, CancelToken()), throwsA(isA<CacheBlocked>()));
    await expectLater(
      remote.validate(valid, initial.version, CancelToken()),
      throwsA(isA<CacheBlocked>()),
    );
  });

  test('invalidation signal refreshes a visible list', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: remote.markRead,
      readAllSource: remote.markAllRead,
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(repository.unreadCount, 2);

    final refreshed = Completer<void>();
    repository.addListener(() {
      if (repository.status == NotificationListStatus.ready &&
          repository.unreadCount == 1 &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    });
    store.readNotification(store.notifications.first.id);
    await cache.applyCommittedMutation({notificationListDependency});
    await refreshed.future.timeout(const Duration(seconds: 2));
    expect(repository.items.first.readAt, isNotNull);
    expect((await cache.usage()).textBytes, 0);
  });

  test('next notification read masks a deleted material target', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: remote.markRead,
      readAllSource: remote.markAllRead,
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(repository.items.first.title, contains('夏の手紙'));

    store.deleteMaterial(store.materials.first.id);
    await cache.applyCommittedMutation({'material:list'});
    await repository.refresh(force: true, preserveCurrent: true);
    expect(repository.items.first.title, isEmpty);
    expect(repository.items.first.resourceId, isNull);
    expect(repository.items.first.detail, isEmpty);
  });

  test('scope close and account switch hide the previous account synchronously', () async {
    final remote = MockNotificationRemote();
    provideDummy<CachePayload<NotificationListSnapshot>>(
      CachePayload(
        value: NotificationListSnapshot(items: const [], unreadCount: 0, snapshotToken: '[]'),
        version: const CacheVersion(resource: '', representation: '', artifact: ''),
      ),
    );
    when(remote.fetch(any, any)).thenAnswer((_) async {
      final userId = cache.scope!.userId;
      final row = NotificationRecord(
        id: 'notice-$userId',
        title: 'Message for $userId',
        detail: 'Ready',
        route: 'textbook',
        createdAt: DateTime.utc(2026, 9, 27),
      );
      return CachePayload(
        value: NotificationListSnapshot(
          items: [row],
          unreadCount: 1,
          snapshotToken: '["notice-$userId"]',
        ),
        version: CacheVersion(
          resource: userId,
          representation: 'notification-summary-v1',
          artifact: userId,
        ),
      );
    });
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: (_) async {},
      readAllSource: (_) async {},
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(repository.items.single.title, 'Message for account-a');

    final closing = cache.closeScope();
    expect(repository.items, isEmpty);
    expect(repository.unreadCount, 0);
    expect(repository.status, isNot(NotificationListStatus.ready));
    await closing;
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'notification-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    expect(repository.items.where((item) => item.title.contains('account-a')), isEmpty);
    await repository.refresh(force: true);
    expect(repository.items.single.title, 'Message for account-b');
    expect(repository.unreadCount, 1);
  });

  test('concurrent read and read-all calls are gated until the first commit settles', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final remote = FixtureNotificationRemote(store);
    final gate = Completer<void>();
    var readCalls = 0;
    var readAllCalls = 0;
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: (id) async {
        readCalls++;
        await gate.future;
        store.readNotification(id);
      },
      readAllSource: (token) async {
        readAllCalls++;
        await remote.markAllRead(token);
      },
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    final first = repository.markRead(store.notifications.first.id);
    expect(repository.busy, isTrue);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      repository.markRead(store.notifications.first.id),
      throwsA(isA<CacheBlocked>()),
    );
    await expectLater(repository.markAllRead(), throwsA(isA<CacheBlocked>()));
    expect(readCalls, 1);
    expect(readAllCalls, 0);
    expect(repository.unreadCount, 2);

    gate.complete();
    await first;
    expect(repository.busy, isFalse);
    expect(repository.unreadCount, 1);
  });

  test('scope change clears a visible list while a read mutation is suspended', () async {
    final remote = MockNotificationRemote();
    final gate = Completer<void>();
    final enteredSource = Completer<void>();
    provideDummy<CachePayload<NotificationListSnapshot>>(
      CachePayload(
        value: NotificationListSnapshot(items: const [], unreadCount: 0, snapshotToken: '[]'),
        version: const CacheVersion(resource: '', representation: '', artifact: ''),
      ),
    );
    when(remote.fetch(any, any)).thenAnswer((_) async {
      final userId = cache.scope!.userId;
      return CachePayload(
        value: NotificationListSnapshot(
          items: [
            NotificationRecord(
              id: 'notice-$userId',
              title: 'Message for $userId',
              detail: 'Ready',
              route: 'textbook',
              createdAt: DateTime.utc(2026, 9, 27),
            ),
          ],
          unreadCount: 1,
          snapshotToken: '["notice-$userId"]',
        ),
        version: CacheVersion(
          resource: userId,
          representation: 'notification-summary-v1',
          artifact: userId,
        ),
      );
    });
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: (_) {
        enteredSource.complete();
        return gate.future;
      },
      readAllSource: (_) async {},
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);
    await repository.refresh();
    expect(repository.items.single.title, 'Message for account-a');
    var notifiedClear = false;
    repository.addListener(() {
      if (repository.busy && repository.items.isEmpty) notifiedClear = true;
    });

    final pendingRead = repository.markRead('notice-account-a');
    final pendingOutcome = expectLater(pendingRead, throwsA(isA<CacheBlocked>()));
    await enteredSource.future;
    expect(repository.busy, isTrue);
    final closing = cache.closeScope();
    expect(notifiedClear, isTrue);
    expect(repository.items, isEmpty);
    await closing;
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'notification-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    expect(repository.items.where((item) => item.title.contains('account-a')), isEmpty);
    gate.complete();
    await pendingOutcome;
    await repository.refresh(force: true);
    expect(repository.items.single.title, 'Message for account-b');
    expect(repository.busy, isFalse);
  });

  test('old in-flight list cannot overwrite a newer read result', () async {
    final remote = MockNotificationRemote();
    final old = Completer<CachePayload<NotificationListSnapshot>>();
    final original = NotificationRecord(
      id: 'notice-1',
      title: 'Ready',
      detail: 'Done',
      route: 'textbook',
      createdAt: DateTime.utc(2026, 9, 27),
    );
    var committed = false;
    var fetches = 0;
    provideDummy<CachePayload<NotificationListSnapshot>>(
      CachePayload(
        value: NotificationListSnapshot(items: const [], unreadCount: 0, snapshotToken: '[]'),
        version: const CacheVersion(resource: '', representation: '', artifact: ''),
      ),
    );
    provideDummy<CacheValidation>(const CacheValidation(state: ValidationState.changed));
    when(remote.fetch(any, any)).thenAnswer((_) {
      fetches++;
      if (fetches == 2) return old.future;
      return Future.value(
        CachePayload(
          value: NotificationListSnapshot(
            items: [committed ? original.read(DateTime.utc(2026, 9, 27, 10)) : original],
            unreadCount: committed ? 0 : 1,
            snapshotToken: '["notice-1"]',
          ),
          version: CacheVersion(
            resource: 'revision-$fetches',
            representation: 'notification-summary-v1',
            artifact: 'revision-$fetches',
          ),
        ),
      );
    });
    final repository = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: (id) async => committed = true,
      readAllSource: (_) async {},
      waitForReadiness: () async {},
    );
    addTearDown(repository.dispose);

    await repository.refresh();
    expect(repository.unreadCount, 1);
    final staleRead = repository.refresh(force: true, preserveCurrent: true);
    await Future<void>.delayed(Duration.zero);
    await repository.markRead(original.id);
    expect(repository.unreadCount, 0);
    expect(repository.items.single.readAt, isNotNull);

    old.complete(
      CachePayload(
        value: NotificationListSnapshot(
          items: [original],
          unreadCount: 1,
          snapshotToken: '["notice-1"]',
        ),
        version: const CacheVersion(
          resource: 'old',
          representation: 'notification-summary-v1',
          artifact: 'old',
        ),
      ),
    );
    await staleRead;
    expect(repository.unreadCount, 0);
    expect(repository.items.single.readAt, isNotNull);
    expect((await cache.usage()).textBytes, 0);
  });

  test(
    'external list hint refreshes, unrelated hint does not, and a missed hint recovers',
    () async {
      final remote = MockNotificationRemote();
      var unread = 2;
      var fetches = 0;
      provideDummy<CachePayload<NotificationListSnapshot>>(
        CachePayload(
          value: NotificationListSnapshot(items: const [], unreadCount: 0, snapshotToken: '[]'),
          version: const CacheVersion(resource: '', representation: '', artifact: ''),
        ),
      );
      when(remote.fetch(any, any)).thenAnswer((_) async {
        fetches++;
        return CachePayload(
          value: NotificationListSnapshot(
            items: [
              NotificationRecord(
                id: 'notice-1',
                title: 'Notice',
                detail: 'Ready',
                route: 'textbook',
                createdAt: DateTime.utc(2026, 9, 27),
              ),
            ],
            unreadCount: unread,
            snapshotToken: '["notice-1"]',
          ),
          version: CacheVersion(
            resource: '$fetches',
            representation: 'notification-summary-v1',
            artifact: '$fetches',
          ),
        );
      });
      final repository = CachedNotificationRepository(
        cache: cache,
        remote: remote,
        readSource: (_) async {},
        readAllSource: (_) async {},
        waitForReadiness: () async {},
      );
      addTearDown(repository.dispose);
      await repository.refresh();
      expect(repository.unreadCount, 2);
      expect(fetches, 1);

      unread = 1;
      await cache.applyCommittedMutation({'query:history'});
      await Future<void>.delayed(Duration.zero);
      expect(repository.unreadCount, 2);
      expect(fetches, 1);

      final changed = Completer<void>();
      repository.addListener(() {
        if (repository.status == NotificationListStatus.ready &&
            repository.unreadCount == 1 &&
            !changed.isCompleted) {
          changed.complete();
        }
      });
      await cache.applyCommittedMutation({notificationListDependency});
      await changed.future.timeout(const Duration(seconds: 2));
      expect(fetches, 2);

      unread = 0;
      await Future<void>.delayed(Duration.zero);
      expect(repository.unreadCount, 1);
      await repository.refresh(force: true, preserveCurrent: true);
      expect(repository.unreadCount, 0);
      expect(fetches, 3);
      expect((await cache.usage()).textBytes, 0);
    },
  );
}

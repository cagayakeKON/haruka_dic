import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/features/settings/presentation/settings_chrome.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/library/data/http_material_catalog.dart';
import 'package:haruka/features/library/data/material_repository.dart';
import 'package:haruka/features/library/data/material_import_repository.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/features/notifications/presentation/notification_repository_scope.dart';
import 'package:haruka/features/notifications/presentation/notifications_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/library/domain/material_metadata.dart';
import 'package:haruka/features/notifications/domain/notification_record.dart';
import 'package:haruka/features/notifications/domain/notification_target.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';
import 'package:haruka/features/notifications/data/cached_notification_repository.dart';
import 'package:haruka/features/notifications/data/http_notification_source.dart';

import '../../support/generated/api_compatibility_samples.dart';
import '../../support/sample_adapter.dart';

const _id = '018f1234-5678-7123-8123-123456789abc';
const _request = '018f1234-1234-7123-8123-123456789abc';
Map<String, Object?> _row({bool unavailable = false, bool read = false}) => {
  'id': _id,
  'schema_version': 1,
  'notification_kind': 'completed',
  'message_code': unavailable ? 'notification.resource_unavailable' : 'material.import.completed',
  'safe_parameters': <String, Object?>{},
  'job_id': _id,
  'resource_kind': 'material',
  'resource_available': !unavailable,
  'resource_id': unavailable ? null : _id,
  'resource_version': unavailable ? null : 1,
  'route_key': unavailable ? null : 'material',
  'created_at': '2026-10-03T00:00:00Z',
  'read_at': read ? '2026-10-03T01:00:00Z' : null,
};

void main() {
  for (final permission in [true, false]) {
    testWidgets(
      'formal mobile My notification entry requires read permission and opens the formal route: $permission',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = (await tester.runAsync(
          () => _Http.start(write: false, notificationRead: permission, providerOwned: true),
        ))!;
        final cache = (await tester.runAsync(_Cache.start))!.cache;
        final source = _NoSettingsRequests();
        final settings = CachedSettingsRepository(cache: cache, source: source);
        addTearDown(settings.dispose);
        final router = GoRouter(
          initialLocation: AppRoutes.settings,
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (_, _) => const Scaffold(body: MobileSettingsView()),
            ),
            GoRoute(
              path: AppRoutes.notifications,
              builder: (_, _) => const Scaffold(body: Text('FORMAL_NOTIFICATION_ROUTE')),
            ),
            GoRoute(
              path: AppRoutes.mockNotifications,
              builder: (_, _) => const Scaffold(body: Text('WRONG_PREVIEW_ROUTE')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authControllerProvider.overrideWith((ref) => h.auth)],
            child: SettingsRepositoryScope(
              repository: settings,
              child: SettingsLocations(
                home: AppRoutes.settings,
                child: MaterialApp.router(
                  routerConfig: router,
                  theme: HarukaTheme.light(),
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.widgetWithText(ListTile, '站内消息');
        if (permission) {
          await tester.scrollUntilVisible(row, 220);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(find.text('FORMAL_NOTIFICATION_ROUTE'), findsOneWidget);
          expect(find.text('WRONG_PREVIEW_ROUTE'), findsNothing);
        } else {
          expect(row, findsNothing);
          expect(router.routeInformationProvider.value.uri.path, AppRoutes.settings);
        }
        expect(source.calls, 0);
        expect(h.requests, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final scenario in [
    (true, null),
    (false, null),
    (false, 'RESOURCE_NOT_FOUND'),
    (false, 'PERMISSION_DENIED'),
    (false, 'NETWORK_UNAVAILABLE'),
  ]) {
    final (write, failure) = scenario;
    testWidgets(
      'formal ${write ? 'writable' : 'read-only'} ${failure ?? "valid"} source notification rechecks ID/version without catalog or Job reads',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = (await tester.runAsync(() => _Http.start(write: write)))!;
        h.materialFailure = failure;
        final cache = (await tester.runAsync(_Cache.start))!.cache;
        final imports = HttpMaterialImportRepository(h.auth);
        final catalog = HttpMaterialCatalog(
          auth: h.auth,
          cache: cache,
          repository: HttpMaterialRepository(h.auth),
          imports: imports,
        );
        addTearDown(() {
          catalog.dispose();
          imports.dispose();
        });
        final source = HttpNotificationSource(h.auth);
        final repo = CachedNotificationRepository(
          cache: cache,
          remote: source,
          readSource: source.markRead,
          readAllSource: source.markAllRead,
          waitForReadiness: () async {},
          allows: source.allows,
        );
        addTearDown(repo.dispose);
        await tester.runAsync(() => repo.refresh());
        final router = GoRouter(
          initialLocation: AppRoutes.notifications,
          routes: [
            GoRoute(path: AppRoutes.notifications, builder: (_, _) => const NotificationsPage()),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialCatalogScope(
            catalog: catalog,
            child: NotificationRepositoryScope(
              repository: repo,
              child: MaterialApp.router(
                routerConfig: router,
                theme: HarukaTheme.light(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('材料来源验证已完成');
        final background = tester.element(title);
        if (!write) expect(find.text('全部标为已读'), findsNothing);
        await tester.tap(title);
        if (failure != null) {
          for (var i = 0; i < 100 && h.materialReads == 0; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pumpAndSettle();
          expect(find.text('材料详情'), findsNothing);
          final strings = AppLocalizations.of(tester.element(title));
          expect(
            find.text(
              failure == 'NETWORK_UNAVAILABLE'
                  ? strings.mockSupportNotificationsReadFailed
                  : strings.mockMaterialUnavailableMessage,
            ),
            findsOneWidget,
          );
          expect(h.requests.where((r) => r.method == 'POST'), isEmpty);
          h.materialFailure = null;
          await tester.tap(title);
        }
        for (var i = 0; i < 100 && find.text('材料详情').evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(
          find.text('材料详情'),
          findsOneWidget,
          reason:
              'safe diagnostic: materialReads=${h.materialReads}; posts=${h.requests.where((r) => r.method == "POST").length}; status=${repo.status}; allowsMaterial=${catalog.allows("client.material.read")}; catalog=${catalog.status}; visible=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList()}',
        );
        expect(find.text('当前源版本：1'), findsOneWidget);
        expect(h.materialReads, failure == null ? 1 : 2);
        expect(h.requests.where((r) => r.method == 'POST').length, write ? 1 : 0);
        final listReads = h.requests.where((r) => r.method == 'GET').length;
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect(tester.element(title), same(background));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 1));
        expect(h.requests.where((r) => r.method == 'GET').length, listReads);
        h.sourceNumber = 2;
        final previousReads = h.materialReads;
        await tester.tap(title);
        for (var i = 0; i < 100 && h.materialReads <= previousReads; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        expect(find.text('材料详情'), findsNothing);
        expect(h.materialReads, previousReads + 1);
        expect(h.requests.where((r) => r.method == 'POST').length, write ? 1 : 0);
        expect(tester.takeException(), isNull);
        h.auth.pauseAccessDeadline();
      },
    );
  }
  testWidgets(
    'formal desktop header badge follows notification publication and scope clear without extra reads',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(_Cache.start))!;
      final repo = h.repository(
        readAll: (_) async {
          h.remote.unread = 0;
        },
      );
      await tester.runAsync(() => repo.refresh());
      await tester.pumpWidget(
        NotificationRepositoryScope(
          repository: repo,
          child: ShellPresentationScope(
            displayName: '本人',
            activeLanguage: 'en',
            reducedMotion: true,
            canReadMaterials: true,
            canReadCollections: false,
            child: MaterialApp(
              theme: HarukaTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const PreviewPageFrame(
                location: AppRoutes.materials,
                title: '材料',
                mobile: SizedBox(),
                desktop: SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      await tester.runAsync(() => repo.markAllRead());
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      h.remote.unread = 1;
      await tester.runAsync(() => repo.refresh(force: true));
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      final reads = h.remote.queries.length;
      await tester.runAsync(() => h.cache.closeScope());
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      expect(h.remote.queries.length, reads);
    },
  );
  test(
    'Pydantic notification samples and source/CAS metadata decode through current consumers',
    () {
      final samples = wireObject(jsonDecode(apiCompatibilitySamplesJson));
      final page = NotificationListSnapshot.fromApiPage(
        PageResponse.fromJson(samples['notification_page'], NotificationRecord.fromApiJson),
      );
      expect(page.items, hasLength(2));
      expect(page.unreadCount, 1);
      expect(page.snapshotToken, wireObject(samples['notification_read_all'])['snapshot_token']);
      expect(page.snapshotExpiresAt, DateTime.utc(2026, 10, 2, 0, 15));
      expect(page.items.last.resourceId, isNull);
      expect(page.items.last.jobId, isNotNull);
      expect(samples['notification_mark_read'], isEmpty);
      final single = SuccessResponse.fromJson(
        samples['notification_read'],
        NotificationRecord.fromApiJson,
      ).data;
      expect(single.readAt, isNotNull);
      final all = SuccessResponse.fromJson(
        samples['notification_read_all_result'],
        NotificationReadAllResult.fromJson,
      ).data;
      expect(all.changedCount, 1);
      expect(all.unreadCount, 1);
      final original = MaterialMetadata.fromJson(
        wireObject(samples['material_metadata_pending'])['data'],
      );
      final renamed = MaterialMetadata.fromJson(
        wireObject(samples['material_metadata_renamed'])['data'],
      );
      expect(original.revision, 1);
      expect(renamed.revision, 2);
      expect(original.sourceRevisionNumber, 1);
      expect(renamed.sourceRevisionNumber, 1);
      final pointer = NotificationRecord.fromApiJson({..._row(), 'resource_id': original.id});
      expect(notificationMetadataTargetMatches(pointer, original), isTrue);
      expect(notificationMetadataTargetMatches(pointer, renamed), isTrue);
      expect(
        MaterialMetadata.fromJson(wireObject(samples['material_metadata_published'])['data'])
            .sourceRevisionNumber,
        isNull,
      );
    },
  );
  test('persistent projections reject private parameters and unsafe/mismatched pointers', () {
    final row = NotificationRecord.fromApiJson(_row());
    expect(row.title, isEmpty);
    expect(row.detail, isEmpty);
    final unavailable = NotificationRecord.fromApiJson(_row(unavailable: true));
    expect(unavailable.resourceId, isNull);
    expect(unavailable.resourceRevision, isNull);
    expect(unavailable.route, isEmpty);
    expect(unavailable.jobId, _id);
    for (final patch in <Map<String, Object?>>[
      {
        'safe_parameters': {'title': 'private source'},
      },
      {'route_key': 'https://external.example/private'},
      {'resource_version': 0},
      {'message_code': 'material.import.failed'},
      {'resource_available': false},
    ]) {
      expect(() => NotificationRecord.fromApiJson({..._row(), ...patch}), throwsFormatException);
    }
    final samples = wireObject(jsonDecode(apiCompatibilitySamplesJson));
    final published = Map<String, Object?>.from(
      wireObject(samples['material_metadata_pending'])['data'] as Map,
    );
    final metadata = MaterialMetadata.fromJson({
      ...published,
      'id': _id,
      'revision': 8,
      'source_revision_number': 1,
    });
    expect(
      notificationMetadataTargetMatches(row, metadata),
      isTrue,
      reason: 'Title CAS changes do not replace the accepted source version',
    );
    expect(metadata.readable, isFalse);
    expect(
      notificationMetadataTargetMatches(
        row,
        MaterialMetadata.fromJson({
          ...published,
          'id': _id,
          'revision': 8,
          'source_revision_number': 2,
        }),
      ),
      isFalse,
    );
    expect(
      notificationMetadataTargetMatches(
        row,
        MaterialMetadata.fromJson({...published, 'id': _id, 'source_revision_number': null}),
      ),
      isFalse,
    );
  });

  test('HTTP notifications preserve page snapshot and send only approved read payloads', () async {
    final h = await _Http.start();
    final events = <String>[];
    final source = HttpNotificationSource(
      h.auth,
      onEvent: (name, attrs) {
        expect(attrs.keys, ['result']);
        events.add(name);
      },
    );
    final payload = await source.fetch(
      notificationListResourceFor(
        const NotificationListQuery(unreadOnly: true, cursor: 'signed-cursor'),
      ),
      CancelToken(),
    );
    expect(h.requests.single.uri.queryParameters, {
      'unread_only': 'true',
      'limit': '50',
      'cursor': 'signed-cursor',
    });
    expect(payload.value.snapshotToken, 'original-snapshot');
    expect(payload.value.nextCursor, 'next-page');
    expect(payload.value.snapshotExpiresAt, DateTime.utc(2099));
    await source.markRead(_id);
    expect(h.requests[1].data, isEmpty);
    expect(h.requests[1].contentType, 'application/json');
    await source.markAllRead('original-snapshot');
    expect(h.requests[2].data, {'snapshot_token': 'original-snapshot'});
    expect(h.requests.every((r) => !r.data.toString().contains('user_id')), isTrue);
    expect(events, [
      'notification.list.loaded',
      'notification.read.updated',
      'notification.read_all.updated',
    ]);
  });

  test('HTTP read-only account can list but cannot submit read or read-all', () async {
    final h = await _Http.start(write: false);
    final source = HttpNotificationSource(h.auth);
    await source.fetch(notificationListResourceFor(const NotificationListQuery()), CancelToken());
    await expectLater(source.markRead(_id), throwsA(isA<ApiFailure>()));
    await expectLater(source.markAllRead('original-snapshot'), throwsA(isA<ApiFailure>()));
    expect(h.requests, hasLength(1));
  });

  test(
    'unknown read-all retries its original snapshot after a fresh list and keeps query',
    () async {
      final h = await _Cache.start();
      final tokens = <String>[];
      var lose = true;
      final repo = h.repository(
        readAll: (token) async {
          tokens.add(token);
          if (lose) {
            lose = false;
            throw const ApiFailure(code: 'NETWORK_UNAVAILABLE', retryableTransport: true);
          }
        },
      );
      await repo.refresh(query: const NotificationListQuery(unreadOnly: true));
      await expectLater(repo.markAllRead(), throwsA(isA<ApiFailure>()));
      h.remote.token = 'newer-snapshot';
      await repo.refresh(
        query: const NotificationListQuery(unreadOnly: true),
        force: true,
        preserveCurrent: true,
      );
      await repo.markAllRead();
      expect(tokens, ['original-snapshot', 'original-snapshot']);
      expect(repo.activeQuery.unreadOnly, isTrue);
      expect(h.remote.queries.every((q) => q.unreadOnly), isTrue);
    },
  );

  test('pagination retains the first committed bound and does not replace existing rows', () async {
    final h = await _Cache.start();
    final tokens = <String>[];
    final repo = h.repository(readAll: (token) async => tokens.add(token));
    await repo.refresh(query: const NotificationListQuery(unreadOnly: true));
    final first = repo.items.single;
    await repo.loadMore();
    expect(repo.items, hasLength(2));
    expect(repo.items.first, same(first));
    expect(repo.nextCursor, isNull);
    expect(h.remote.queries.last.cursor, 'next-page');
    await repo.markAllRead();
    expect(tokens, ['original-snapshot']);
    expect(repo.activeQuery.unreadOnly, isTrue);
  });

  test('local cache clear retires a suspended mutation and its unknown snapshot', () async {
    final h = await _Cache.start();
    final entered = Completer<void>(), finish = Completer<void>();
    final tokens = <String>[];
    final repo = h.repository(
      readAll: (token) async {
        tokens.add(token);
        if (tokens.length == 1) {
          entered.complete();
          await finish.future;
        }
      },
    );
    await repo.refresh();
    final pending = repo.markAllRead();
    await entered.future;
    await h.cache.clearScope();
    expect(repo.items, isEmpty);
    h.remote.token = 'post-clear-snapshot';
    await repo.refresh(force: true);
    final reads = h.remote.queries.length;
    final revision = h.cache.dependencyRevision(notificationListDependency);
    finish.complete();
    await expectLater(pending, throwsA(isA<CacheBlocked>()));
    expect(h.remote.queries.length, reads);
    expect(h.cache.dependencyRevision(notificationListDependency), revision);
    await repo.markAllRead();
    expect(tokens, ['original-snapshot', 'post-clear-snapshot']);
  });

  test(
    'expired unknown read-all fails once before an explicit action can use the refreshed bound',
    () async {
      final h = await _Cache.start();
      var clock = DateTime.utc(2098);
      final tokens = <String>[];
      final repo = h.repository(
        now: () => clock,
        readAll: (token) async {
          tokens.add(token);
          if (tokens.length == 1) {
            throw const ApiFailure(code: 'NETWORK_UNAVAILABLE', retryableTransport: true);
          }
        },
      );
      await repo.refresh();
      await expectLater(repo.markAllRead(), throwsA(isA<ApiFailure>()));
      clock = DateTime.utc(2100);
      h.remote.token = 'explicit-new-bound';
      h.remote.expiry = DateTime.utc(2101);
      await repo.refresh(force: true);
      await expectLater(repo.markAllRead(), throwsA(isA<CacheBlocked>()));
      expect(tokens, ['original-snapshot']);
      await repo.markAllRead();
      expect(tokens, ['original-snapshot', 'explicit-new-bound']);
    },
  );

  test('single read cannot invalidate a new publication after local cache clear', () async {
    final h = await _Cache.start();
    final entered = Completer<void>(), finish = Completer<void>();
    final repo = h.repository(
      readAll: (_) async {},
      read: (_) async {
        entered.complete();
        await finish.future;
      },
    );
    await repo.refresh();
    final pending = repo.markRead(_id);
    await entered.future;
    await h.cache.clearScope();
    h.remote.token = 'new-generation';
    await repo.refresh(force: true);
    final reads = h.remote.queries.length;
    final revision = h.cache.dependencyRevision(notificationListDependency);
    finish.complete();
    await expectLater(pending, throwsA(isA<CacheBlocked>()));
    expect(h.remote.queries.length, reads);
    expect(h.cache.dependencyRevision(notificationListDependency), revision);
    expect(repo.items, hasLength(1));
  });
}

final class _Http {
  late AuthController auth;
  int materialReads = 0, sourceNumber = 1;
  bool wasRead = false;
  String? materialFailure;
  final requests = <RequestOptions>[];
  static Future<_Http> start({
    bool write = true,
    bool notificationRead = true,
    bool providerOwned = false,
  }) async {
    final h = _Http();
    final samples = wireObject(jsonDecode(apiCompatibilitySamplesJson));
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://localhost:18443',
    );
    ResponseBody response(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    ResponseBody envelope(Object value) => response({
      'data': value,
      'meta': {'request_id': _request},
    });
    final api = ApiClient(
      config,
      adapter: SampleAdapter((options, _) async {
        final path = options.uri.path;
        if (path == '/api/v1/meta') {
          return envelope({
            'instance_id': config.instanceId,
            'api_version': 'v1',
            'release': 'test',
          });
        }
        if (path == '/api/v1/auth/login') {
          return response(wireObject(samples['auth_web_authenticated']));
        }
        if (path == '/api/v1/auth/csrf') {
          return envelope({
            'session_ref': '018f1234-0000-7000-8000-000000000002',
            'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          });
        }
        if (path == '/api/v1/me/access') {
          final access = jsonDecode(
            jsonEncode(samples['auth_client_access_login_only']),
          ) as Map<String, dynamic>;
          wireObject(access['data'])['permissions'] = [
            for (final code in [
              'client.login',
              if (notificationRead) 'client.notification.read',
              'client.material.read',
              'client.exam.read',
              if (write) 'client.notification.update',
            ])
              {'code': code, 'data_scope': 'self'},
          ];
          return response(access);
        }
        if (path.startsWith('/api/v1/notifications')) {
          h.requests.add(options);
          if (options.method == 'GET') {
            return response({
              'data': [_row(read: h.wasRead)],
              'meta': {
                'request_id': _request,
                'has_more': true,
                'next_cursor': 'next-page',
                'unread_count': 1,
                'snapshot_token': 'original-snapshot',
                'snapshot_expires_at': '2099-01-01T00:00:00Z',
              },
            });
          }
          if (path.endsWith('/read-all')) return envelope({'changed_count': 1, 'unread_count': 0});
          if (path.endsWith('/read')) {
            h.wasRead = true;
            return envelope(_row(read: true));
          }
        }
        if (path == '/api/v1/materials/$_id' && options.method == 'GET') {
          h.materialReads++;
          if (h.materialFailure case final code?) {
            if (code == 'NETWORK_UNAVAILABLE') {
              throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
            }
            return ResponseBody.fromString(
              jsonEncode({
                'error': {'code': code, 'field_errors': <Object>[]},
                'meta': {'request_id': _request},
              }),
              code == 'PERMISSION_DENIED' ? 403 : 404,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          return envelope({
            ...wireObject(wireObject(samples['material_metadata_renamed'])['data']),
            'id': _id,
            'source_revision_number': h.sourceNumber,
          });
        }
        throw const FormatException('Unexpected synthetic route');
      }),
    );
    h.auth = AuthController(AuthRepository(api, config), config, vault: _Vault(), sync: _Sync());
    addTearDown(() {
      if (!providerOwned) h.auth.dispose();
      api.close();
    });
    expect(await h.auth.login('synthetic@example.test', 'synthetic-test-password'), isTrue);
    h.auth.pauseAccessDeadline();
    return h;
  }
}

final class _NoSettingsRequests implements SettingsSource {
  int calls = 0;
  @override
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel) async {
    calls++;
    throw StateError('Unexpected settings fetch');
  }

  @override
  Future<SettingsSnapshot> patch(SettingsGroup group, SettingsPatch patch) async {
    calls++;
    throw StateError('Unexpected settings patch');
  }
}

final class _Cache {
  _Cache(this.cache);
  final CacheCoordinator cache;
  final remote = _Pages();
  static Future<_Cache> start() async {
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://notification.example'),
        instanceId: 'notification-test',
        userId: 'account-a',
        audience: 'client',
        sessionRef: 'session-a',
      ),
    );
    addTearDown(cache.closeScope);
    return _Cache(cache);
  }

  CachedNotificationRepository repository({
    required Future<void> Function(String) readAll,
    Future<void> Function(String)? read,
    DateTime Function()? now,
  }) {
    final repo = CachedNotificationRepository(
      cache: cache,
      remote: remote,
      readSource: read ?? (_) async {},
      readAllSource: readAll,
      waitForReadiness: () async {},
      now: now,
    );
    addTearDown(repo.dispose);
    return repo;
  }
}

final class _Pages implements CacheRemote<NotificationListSnapshot> {
  String token = 'original-snapshot';
  DateTime expiry = DateTime.utc(2099);
  int unread = 2;
  final queries = <NotificationListQuery>[];
  var generation = 0;
  @override
  Future<CachePayload<NotificationListSnapshot>> fetch(
    CacheResource resource,
    CancelToken cancel,
  ) async {
    final query = NotificationListQuery.fromKey(resource.queryKey);
    queries.add(query);
    final isNext = query.cursor.isNotEmpty;
    final snapshot = NotificationListSnapshot(
      items: [
        NotificationRecord.fromApiJson({..._row(), if (isNext) 'id': _request}),
      ],
      unreadCount: unread,
      snapshotToken: isNext ? 'same-bound-page-token' : token,
      nextCursor: isNext ? null : 'next-page',
      snapshotExpiresAt: expiry,
    );
    final version = '${++generation}';
    return CachePayload(
      value: snapshot,
      version: CacheVersion(
        resource: version,
        representation: 'notification-summary-v1',
        artifact: version,
      ),
    );
  }

  @override
  Future<CacheValidation> validate(
    CacheResource resource,
    CacheVersion known,
    CancelToken cancel,
  ) async => const CacheValidation(state: ValidationState.changed);
}

final class _Vault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

final class _Sync implements AuthSync {
  @override
  void dispose() {}
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void publishChanged() {}
  @override
  void publishStarted() {}
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
}

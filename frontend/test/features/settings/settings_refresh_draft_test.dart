import '../../support/test_database.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_snapshot_gate.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:mockito/mockito.dart';

import 'cached_settings_repository_test.mocks.dart';

void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('unchanged settings keep the mounted draft without periodic or return reads', (
    tester,
  ) async {
    final cache = (await tester.runAsync(() async {
      final cache = CacheCoordinator(
        openBackend: (_) async => OpenedCacheBackend(
          executor: memoryTestDatabase(),
          mode: CacheStorageMode.memoryOnly,
          closeOwner: () async {},
        ),
      );
      await cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://cache.example'),
          instanceId: 'settings-visibility',
          userId: 'reader',
          audience: 'client',
          sessionRef: 'session',
        ),
      );
      return cache;
    }))!;
    final source = MockSettingsSource();
    provideDummy<SettingsSnapshot>(
      SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {'display_name': '服务端名字'},
      ),
    );
    var fetches = 0;
    when(source.fetch(any, any)).thenAnswer((_) async {
      fetches++;
      return SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: fetches,
        fields: const {'display_name': '服务端名字'},
      );
    });
    final repository = CachedSettingsRepository(cache: cache, source: source);
    try {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [PageRouteActivityObserver()],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsRepositoryScope(
            repository: repository,
            child: Scaffold(
              body: SettingsSnapshotGate(
                groups: const {SettingsGroup.profile},
                builder: (_) => const TextField(key: ValueKey('draft')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fetches, 1);
      final field = find.byKey(const ValueKey('draft'));
      final element = tester.element(field);
      await tester.enterText(field, '未提交');
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(fetches, 1);
      expect(tester.element(field), same(element));
      expect(find.text('未提交'), findsOneWidget);

      final dialog = showDialog<void>(
        context: tester.element(field),
        builder: (_) => const AlertDialog(title: Text('弹层')),
      );
      await tester.pumpAndSettle();
      expect(fetches, 1);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;
      expect(fetches, 1);

      final covered = navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('其他页面'))),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(fetches, 1);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await covered;
      expect(fetches, 1);
      expect(tester.element(field), same(element));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      var inactive = true;
      try {
        await tester.pump(const Duration(seconds: 30));
        expect(fetches, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        inactive = false;
        await tester.pump();
        expect(fetches, 1);
      } finally {
        if (inactive) tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
      await tester.runAsync<void>(() => cache.closeScope().timeout(const Duration(seconds: 10)));
    }
  });

  testWidgets('initial read waits for the attached account scope', (tester) async {
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: memoryTestDatabase(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    final ready = Completer<void>();
    final source = MockSettingsSource();
    provideDummy<SettingsSnapshot>(
      SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: const {'display_name': '已确认'},
      ),
    );
    var fetches = 0;
    when(source.fetch(any, any)).thenAnswer((_) async {
      fetches++;
      return SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: const {'display_name': '已确认'},
      );
    });
    final repository = CachedSettingsRepository(
      cache: cache,
      source: source,
      waitForReadiness: () => ready.future,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsRepositoryScope(
            repository: repository,
            child: Scaffold(
              body: SettingsSnapshotGate(
                groups: const {SettingsGroup.profile},
                builder: (_) => const Text('资料可用'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(fetches, 0);
      await tester.runAsync<void>(
        () => cache.attach(
          CacheScope.confirmed(
            endpoint: Uri.parse('https://cache.example'),
            instanceId: 'settings-attach',
            userId: 'reader',
            audience: 'client',
            sessionRef: 'session',
          ),
        ),
      );
      await tester.pump();
      expect(fetches, 0);
      ready.complete();
      await tester.pumpAndSettle();
      expect(fetches, 1);
      expect(find.text('资料可用'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
      await tester.runAsync<void>(() => cache.closeScope().timeout(const Duration(seconds: 10)));
    }
  });

  testWidgets('cross-tab refresh and own save keep the mounted form draft', (tester) async {
    final cache = (await tester.runAsync(() async {
      final cache = CacheCoordinator(
        openBackend: (_) async => OpenedCacheBackend(
          executor: memoryTestDatabase(),
          mode: CacheStorageMode.memoryOnly,
          closeOwner: () async {},
        ),
      );
      await cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://cache.example'),
          instanceId: 'settings',
          userId: 'reader',
          audience: 'client',
          sessionRef: 'session',
        ),
      );
      return cache;
    }))!;
    var snapshot = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 1,
      fields: const {'display_name': '服务端名字'},
    );
    provideDummy<SettingsSnapshot>(snapshot);
    final source = MockSettingsSource();
    Completer<void>? pending;
    when(source.fetch(any, any)).thenAnswer((_) async {
      await pending?.future;
      return snapshot;
    });
    when(source.patch(any, any)).thenAnswer((_) async {
      snapshot = SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 2,
        fields: const {'display_name': '已保存名字'},
      );
      return snapshot;
    });
    final repository = CachedSettingsRepository(cache: cache, source: source);
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsRepositoryScope(
            repository: repository,
            child: Scaffold(
              body: SettingsSnapshotGate(
                groups: const {SettingsGroup.profile},
                builder: (_) => const TextField(key: ValueKey('draft')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('draft'));
      final element = tester.element(field);
      await tester.enterText(field, '尚未提交的草稿');
      pending = Completer<void>();
      cache.handleExternalCacheHint('invalidate', {'settings:profile'});
      await tester.pump();
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.refreshing);
      expect(tester.element(field), same(element));
      expect(find.text('尚未提交的草稿'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.ready);
      expect(tester.element(field), same(element));
      pending = Completer<void>();
      final saving = repository.save(SettingsGroup.profile, {'display_name': '已保存名字'});
      await tester.pump();
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.refreshing);
      expect(tester.element(field), same(element));
      expect(find.text('尚未提交的草稿'), findsOneWidget);
      pending.complete();
      await saving;
      await tester.pumpAndSettle();
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.ready);
      expect(tester.element(field), same(element));
      expect(find.text('尚未提交的草稿'), findsOneWidget);
      cache.blockForAuthorizationFailure();
      await tester.pumpAndSettle();
      expect(field, findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
      await tester.runAsync<void>(() => cache.closeScope().timeout(const Duration(seconds: 10)));
    }
  });
}

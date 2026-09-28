import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/data/cached_collection_catalog.dart';
import 'package:haruka/features/collections/data/collection_catalog.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/collections/presentation/collection_catalog_scope.dart';
import 'package:haruka/features/collections/presentation/daily_words_page.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:mockito/mockito.dart';

import '../settings/cached_settings_repository_test.mocks.dart';
import 'cached_collection_catalog_test.mocks.dart';

void main() {
  final accountAWord = CollectionEntry(
    id: 'account-a-word',
    kind: CollectionKind.word,
    displayText: '境界',
    targetLanguage: 'ja',
    meaning: '边界',
    createdAt: DateTime.utc(2026, 9, 27, 14, 59),
  );
  final accountBWord = CollectionEntry(
    id: 'account-b-word',
    kind: CollectionKind.word,
    displayText: 'separate',
    targetLanguage: 'en',
    meaning: '分开的',
    createdAt: DateTime.utc(2026, 9, 27, 14, 58),
  );

  Future<CacheCoordinator> pumpDailyWords(
    WidgetTester tester, {
    required DateTime Function() clock,
    bool coldAttach = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cache = CacheCoordinator(
      openBackend: (_) async {
        final executor = NativeDatabase.memory();
        return OpenedCacheBackend(
          executor: executor,
          mode: CacheStorageMode.memoryOnly,
          closeOwner: executor.close,
        );
      },
    );
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://daily-words.example/api'),
      instanceId: 'daily-words-test',
      userId: 'account-a',
      audience: 'client',
      sessionRef: 'session-a',
    );
    if (!coldAttach) await cache.attach(scope);

    final store = PreviewFixtureStore()..timezone = 'Pacific/Honolulu';
    final settingsSource = MockSettingsSource();
    provideDummy<SettingsSnapshot>(
      SettingsSnapshot(group: SettingsGroup.preferences, revision: 1, fields: const {}),
    );
    when(settingsSource.fetch(any, any)).thenAnswer((_) async {
      return SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: {
          'timezone': cache.scope?.userId == 'account-a' ? 'Asia/Tokyo' : 'America/New_York',
        },
      );
    });
    final readiness = Completer<void>();
    final settings = CachedSettingsRepository(
      cache: cache,
      source: settingsSource,
      waitForReadiness: coldAttach ? () => readiness.future : null,
    );

    final collectionSource = MockCollectionSource();
    CachePayload<List<CollectionEntry>> collectionPayload(String account) {
      final rows = account == 'account-a' ? [accountAWord] : [accountBWord];
      return CachePayload(
        value: rows,
        version: CacheVersion(
          resource: '$account:collection-list',
          representation: 'collection-list-v1',
          artifact: '$account:collection-list',
        ),
      );
    }

    final notebookPayload = CachePayload(
      value: NotebookListSnapshot(notebooks: const [], counts: const {}),
      version: const CacheVersion(
        resource: 'notebooks',
        representation: 'notebook-list-v1',
        artifact: 'notebooks',
      ),
    );
    provideDummy<CachePayload<List<CollectionEntry>>>(collectionPayload('account-a'));
    provideDummy<CachePayload<NotebookListSnapshot>>(notebookPayload);
    when(collectionSource.fetchCollections(any, any)).thenAnswer((_) async {
      return collectionPayload(cache.scope?.userId ?? 'account-b');
    });
    when(collectionSource.fetchNotebooks(any, any)).thenAnswer((_) async => notebookPayload);
    final catalog = CachedCollectionCatalog(cache: cache, source: collectionSource);
    addTearDown(() async {
      catalog.dispose();
      settings.dispose();
      await cache.closeScope();
      store.dispose();
    });

    await tester.pumpWidget(
      PreviewStoreScope(
        store: store,
        child: SettingsRepositoryScope(
          repository: settings,
          child: CollectionCatalogScope(
            catalog: catalog,
            child: MaterialApp(
              theme: HarukaTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DailyWordsPage(clock: clock),
            ),
          ),
        ),
      ),
    );
    if (coldAttach) {
      await tester.pump();
      expect(settings.status(SettingsGroup.preferences), SettingsReadStatus.initial);
      await tester.runAsync(() => cache.attach(scope));
      readiness.complete();
    }
    await tester.pumpAndSettle();
    return cache;
  }

  testWidgets('cold daily entry waits for account readiness before reading preferences', (
    tester,
  ) async {
    await pumpDailyWords(tester, clock: () => DateTime.utc(2026, 9, 27, 14, 59), coldAttach: true);
    expect(find.textContaining('Asia/Tokyo'), findsOneWidget);
    expect(find.text('境界'), findsOneWidget);
    expect(find.text('重试加载'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted account timezone drives visible midnight and count, not preview store', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 27, 14, 59, 59, 500);
    await pumpDailyWords(tester, clock: () => now);
    expect(find.text('2026-09-27'), findsOneWidget);
    expect(find.textContaining('Asia/Tokyo'), findsOneWidget);
    expect(find.textContaining('Pacific/Honolulu'), findsNothing);
    expect(find.text('境界'), findsOneWidget);
    expect(find.textContaining('1 个单词'), findsOneWidget);

    now = DateTime.utc(2026, 9, 27, 15);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('2026-09-28'), findsOneWidget);
    expect(find.text('境界'), findsNothing);
    expect(find.textContaining('0 个单词'), findsOneWidget);
    expect(find.text('这天没有加入单词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scope loss closes an open date picker and new account starts at its own today', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 27, 15);
    final cache = await pumpDailyWords(tester, clock: () => now);
    expect(find.text('2026-09-28'), findsOneWidget);
    await tester.tap(find.text('2026-09-28'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await cache.closeScope();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('境界'), findsNothing);
    expect(find.text('2026-09-28'), findsNothing);

    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://daily-words.example/api'),
        instanceId: 'daily-words-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('America/New_York'), findsOneWidget);
    expect(find.text('2026-09-27'), findsOneWidget);
    expect(find.text('境界'), findsNothing);
    expect(find.text('separate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

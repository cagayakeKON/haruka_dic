import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_app.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';
import 'package:haruka/features/agent/domain/query_history_entry.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import '../../support/preview_test_app.dart';
import 'query_repository_history_widget_test.mocks.dart';

@GenerateNiceMocks([MockSpec<QueryResultRepository>()])
class _EmptyTargetSettingsSource implements SettingsSource {
  @override
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel) async => SettingsSnapshot(
    group: group,
    revision: 1,
    fields: switch (group) {
      SettingsGroup.studyProfile => {
        'active_target_language': '',
        'explanation_language': 'zh-Hans',
      },
      SettingsGroup.preferences => {'reduce_motion': 'system'},
      SettingsGroup.profile => {},
    },
  );

  @override
  Future<SettingsSnapshot> patch(SettingsGroup group, SettingsPatch patch) async =>
      throw UnimplementedError();
}

void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('query without accepted settings never submits fixture-backed success', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    provideDummy<LearningCard>(store.cards.first);
    final repository = MockQueryResultRepository();
    when(repository.history).thenReturn(const []);
    await tester.pumpWidget(
      PreviewStoreScope(
        store: store,
        child: MaterialApp(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QueryPage(queryResults: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'そっと');
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, '发送');
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(SnackBar), findsOneWidget);
    verifyNever(repository.submit(any));
    expect(store.history, isEmpty);
  });

  testWidgets('injected repository owns query history across route rebuilds', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const card = LearningCard(
      id: 'repository-result',
      kind: CollectionKind.word,
      title: '仓储结果',
      explanation: '缓存确认后的结果',
      examples: [],
      version: 1,
    );
    provideDummy<LearningCard>(card);
    final repository = MockQueryResultRepository();
    final history = <QueryHistoryEntry>[];
    when(repository.history).thenAnswer((_) => List.unmodifiable(history));
    when(repository.submit(any)).thenAnswer((invocation) async {
      final request = invocation.positionalArguments.single as QueryRequest;
      history.add(
        QueryHistoryEntry(
          prompt: request.text.trim(),
          card: card,
          targetLanguage: request.targetLanguage,
        ),
      );
      return card;
    });

    await tester.pumpWidget(buildTestPreviewApp(queryResultRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    final store = PreviewStoreScope.of(tester.element(find.byType(QueryPage)));
    expect(store.history, isEmpty);
    final settings = SettingsRepositoryScope.of(tester.element(find.byType(QueryPage)));
    expect(settings.snapshot(SettingsGroup.studyProfile)?.fields['active_target_language'], 'ja');
    store.activeLanguage = 'en';
    store.explanationLanguage = 'en';

    await tester.enterText(find.byType(TextField).first, '测试仓储');
    await tester.pumpAndSettle();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(tester.widget<MobileQueryView>(find.byType(MobileQueryView)).entries, hasLength(1));
    expect(find.text('仓储结果'), findsOneWidget);
    expect(store.history, isEmpty);

    await tester.tap(find.widgetWithText(NavigationDestination, '材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    expect(tester.widget<MobileQueryView>(find.byType(MobileQueryView)).entries, hasLength(1));
    expect(find.byType(QueryResultCard), findsOneWidget);
    expect(find.text('仓储结果'), findsOneWidget);
    final submitted = verify(repository.submit(captureAny)).captured.single as QueryRequest;
    expect(submitted.targetLanguage, 'ja');
    expect(submitted.explanationLanguage, 'zh-Hans');
  });

  testWidgets('query may submit with no active target language', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    provideDummy<LearningCard>(store.cards.first);
    final repository = MockQueryResultRepository();
    when(repository.history).thenReturn(const []);
    when(repository.submit(any)).thenAnswer((_) async => store.cards.first);

    await tester.pumpWidget(
      PreviewHarukaApp(
        queryResultRepository: repository,
        settingsSource: _EmptyTargetSettingsSource(),
        settingsCacheAdapter: PreviewSettingsCacheAdapter(
          coordinator: CacheCoordinator(
            openBackend: (_) async {
              final executor = memoryTestDatabase();
              return OpenedCacheBackend(
                executor: executor,
                mode: CacheStorageMode.memoryOnly,
                closeOwner: executor.close,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '查询'));
    await tester.pumpAndSettle();
    final settings = SettingsRepositoryScope.of(tester.element(find.byType(QueryPage)));
    expect(settings.snapshot(SettingsGroup.studyProfile)?.fields['active_target_language'], '');
    await tester.enterText(find.byType(TextField).first, 'そっと');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    final submitted = verify(repository.submit(captureAny)).captured.single as QueryRequest;
    expect(submitted.targetLanguage, '');
  });
}

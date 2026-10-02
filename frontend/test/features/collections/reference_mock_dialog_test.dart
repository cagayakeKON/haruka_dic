import 'dart:convert';

import '../../support/generated/api_compatibility_samples.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/learning_models.dart' as published;
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/features/collections/reference_feature_scope.dart';
import 'package:haruka/features/collections/reference_repository.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/features/library/presentation/published_novel_reader.dart';
import 'package:haruka/features/novels/presentation/selection_overlay.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import '../../support/sample_adapter.dart';
import '../../support/async_frames.dart';

final class _Vault implements CredentialVault {
  RefreshCredential? value;
  @override
  Future<RefreshCredential?> read() async => value;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    if (prior == null ? value != null : value == null || !prior.sameVersion(value!)) return false;
    value = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async {
    if (sessionRef == null || value?.sessionRef == sessionRef) value = null;
  }
}

final class _Sync implements AuthSync {
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  void dispose() {}
}

void main() {
  final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
  final config = AppConfig.parse(
    platform: AppPlatform.windows,
    environment: 'dev',
    instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
    apiBaseUrl: 'http://127.0.0.1:18081',
  );
  const requestId = '018f1234-1234-7123-8123-123456789abc';
  ResponseBody body(Object value) => ResponseBody.fromString(
    jsonEncode(value),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  for (final viewport in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets(
      'published word uses the same centered dialog and closes on scope loss at $viewport',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var collectionGets = 0;
        var materialGets = 0;
        var logins = 0;
        final card =
            (samples['learning_word_card'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
        final locator = (card['source_refs'] as List<dynamic>).single as Map<String, dynamic>;
        final adapter = SampleAdapter((options, _) async {
          if (options.path == '/api/v1/meta') {
            return body({
              'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
              'meta': {'request_id': requestId},
            });
          }
          if (options.path == '/api/v1/auth/native/login') {
            logins++;
            return body(samples['auth_native_authenticated'] as Object);
          }
          if (options.path == '/api/v1/me/access') {
            final access = jsonDecode(
              jsonEncode(samples['auth_client_access_login_only']),
            ) as Map<String, dynamic>;
            (access['data'] as Map<String, dynamic>)['permissions'] = [
              {'code': 'client.login', 'data_scope': 'self'},
              {'code': 'client.collection.read', 'data_scope': 'self'},
              {'code': 'client.material.list', 'data_scope': 'self'},
              {'code': 'client.material.read', 'data_scope': 'self'},
            ];
            if (logins > 1) {
              (access['data'] as Map<String, dynamic>)['user_id'] =
                  '018f1234-0000-7000-8000-000000000099';
            }
            return body(access);
          }
          if (options.path.startsWith('/api/v1/collections?')) {
            collectionGets++;
            return body({
              'data': [(samples['learning_collection'] as Map<String, dynamic>)['data']],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          if (options.path.startsWith('/api/v1/materials?')) {
            materialGets++;
            return body({
              'data': [
                {
                  'id': locator['material_id'],
                  'library_id': locator['library_id'],
                  'revision_id': locator['material_revision_id'],
                  'first_chapter_id': locator['novel_chapter_id'],
                  'material_type': 'novel',
                  'title': locator['source_title'],
                  'language': 'ja',
                  'created_at': '2026-09-26T01:02:03Z',
                },
              ],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          throw StateError('Unexpected ${options.path}');
        });
        final api = ApiClient(config, adapter: adapter);
        final auth = AuthController(
          AuthRepository(api, config),
          config,
          vault: _Vault(),
          sync: _Sync(),
        );
        addTearDown(() {
          auth.dispose();
          api.close();
        });
        expect(
          await tester.runAsync(() => auth.login('user@example.test', 'valid-test-password')),
          isTrue,
        );
        final reference = ReferenceController(auth, ReferenceRepository(api));
        addTearDown(reference.dispose);
        await tester.runAsync(reference.ensureCollections);
        final collection =
            (samples['learning_collection'] as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showWordDetail(context, collection['id'] as String),
                    child: const Text('open word'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.material,
              builder: (_, _) => const Scaffold(body: Text('published source route')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ReferenceFeatureScope(
            controller: reference,
            child: MaterialApp.router(
              routerConfig: router,
              theme: HarukaTheme.light(),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open word'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byKey(const ValueKey(UiTestIds.referenceWordDialog)), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(collection['display_text'] as String), findsWidgets);
        expect(collectionGets, 1);
        expect(materialGets, 0, reason: 'opening detail must not load the material list');
        final sourceLabel = AppLocalizations.of(tester.element(find.byType(WordDetailDialog)))
            .mockLearningWordBackToSource;
        await tester.ensureVisible(find.text(sourceLabel));
        await tester.tap(find.text(sourceLabel));
        await tester.pumpAndSettle();
        expect(find.text('published source route'), findsOneWidget);
        expect(materialGets, 0, reason: 'source navigation is handled by the reader route');
        router.go('/');
        await tester.pumpAndSettle();
        await tester.tap(find.text('open word'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(collectionGets, 1, reason: 'returning from source must reuse the collection list');
        await tester.runAsync(auth.logout);
        if (viewport.width > 1000) {
          expect(
            await tester.runAsync(() => auth.login('other@example.test', 'valid-test-password')),
            isTrue,
          );
          // The root overlay must not rebind A's captured content to B on rebuild.
          await tester.pumpWidget(
            ReferenceFeatureScope(
              controller: reference,
              child: MaterialApp.router(
                routerConfig: router,
                theme: HarukaTheme.dark(),
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.text(collection['display_text'] as String), findsNothing);
        await reference.ensureCollections();
        expect(collectionGets, 1, reason: 'a stale controller must not read under the next scope');
      },
    );
  }

  testWidgets('published library keeps its list without read permission or another GET', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card =
        (samples['learning_word_card'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final locator = (card['source_refs'] as List<dynamic>).single as Map<String, dynamic>;
    var listGets = 0;
    var chapterGets = 0;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return body({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/native/login') {
        return body(samples['auth_native_authenticated'] as Object);
      }
      if (options.path == '/api/v1/me/access') {
        final access = jsonDecode(
          jsonEncode(samples['auth_client_access_login_only']),
        ) as Map<String, dynamic>;
        (access['data'] as Map<String, dynamic>)['permissions'] = [
          {'code': 'client.login', 'data_scope': 'self'},
          {'code': 'client.material.list', 'data_scope': 'self'},
        ];
        return body(access);
      }
      if (options.path.startsWith('/api/v1/materials?')) {
        listGets++;
        return body({
          'data': [
            {
              'id': locator['material_id'],
              'library_id': locator['library_id'],
              'revision_id': locator['material_revision_id'],
              'first_chapter_id': locator['novel_chapter_id'],
              'material_type': 'novel',
              'title': locator['source_title'],
              'language': 'ja',
              'created_at': '2026-09-26T01:02:03Z',
            },
          ],
          'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
        });
      }
      if (options.path.startsWith('/api/v1/novels/')) chapterGets++;
      throw StateError('Unexpected ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    addTearDown(() {
      auth.dispose();
      api.close();
    });
    expect(
      await tester.runAsync(() => auth.login('user@example.test', 'valid-test-password')),
      isTrue,
    );
    final reference = ReferenceController(auth, ReferenceRepository(api));
    addTearDown(reference.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.materials,
      routes: [
        GoRoute(path: AppRoutes.materials, builder: (_, _) => const LibraryPage()),
        GoRoute(
          path: AppRoutes.material,
          builder: (_, state) => MaterialEntryPage(materialId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ReferenceFeatureScope(
        controller: reference,
        child: ShellPresentationScope(
          displayName: 'Test',
          activeLanguage: 'ja',
          reducedMotion: false,
          canReadMaterials: true,
          canReadCollections: false,
          child: MaterialApp.router(
            routerConfig: router,
            theme: HarukaTheme.light(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    );
    await settleAsyncFrames(tester);
    await waitForAsyncState(
      tester,
      () => find.text(locator['source_title'] as String).evaluate().isNotEmpty,
      reason: 'The current authorized library list must be visible',
    );
    expect(find.text(locator['source_title'] as String), findsWidgets);
    expect(listGets, 1);
    await tester.tap(find.text(locator['source_title'] as String).first);
    await settleAsyncFrames(tester);
    await waitForAsyncState(
      tester,
      () => find.byType(MaterialEntryPage).evaluate().isNotEmpty,
      reason: 'The selected material route must complete before inspection',
    );
    expect(find.byType(MaterialEntryPage), findsOneWidget);
    expect(chapterGets, 0);
    router.pop();
    await settleAsyncFrames(tester);
    await waitForAsyncState(
      tester,
      () => find.text(locator['source_title'] as String).evaluate().isNotEmpty,
      reason: 'The current authorized library list must be visible',
    );
    expect(find.text(locator['source_title'] as String), findsWidgets);
    expect(listGets, 1, reason: 'returning from detail must retain the shared list');
  });

  testWidgets('published source navigation finds a material beyond the first page', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card =
        (samples['learning_word_card'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final locator = (card['source_refs'] as List<dynamic>).single as Map<String, dynamic>;
    final span = (locator['spans'] as List<dynamic>).single as Map<String, dynamic>;
    var materialGets = 0;
    var chapterGets = 0;
    final adapter = SampleAdapter((options, _) async {
      if (options.path == '/api/v1/meta') {
        return body({
          'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
          'meta': {'request_id': requestId},
        });
      }
      if (options.path == '/api/v1/auth/native/login') {
        return body(samples['auth_native_authenticated'] as Object);
      }
      if (options.path == '/api/v1/me/access') {
        final access = jsonDecode(
          jsonEncode(samples['auth_client_access_login_only']),
        ) as Map<String, dynamic>;
        (access['data'] as Map<String, dynamic>)['permissions'] = [
          {'code': 'client.login', 'data_scope': 'self'},
          {'code': 'client.material.list', 'data_scope': 'self'},
          {'code': 'client.material.read', 'data_scope': 'self'},
        ];
        return body(access);
      }
      if (options.path.startsWith('/api/v1/materials?')) {
        materialGets++;
        final later = options.path.contains('cursor=later');
        return body({
          'data': [
            {
              'id': later ? locator['material_id'] : '018f1234-0000-7000-8000-000000000077',
              'library_id': locator['library_id'],
              'revision_id': locator['material_revision_id'],
              'first_chapter_id': locator['novel_chapter_id'],
              'material_type': 'novel',
              'title': later ? locator['source_title'] : '其他材料',
              'language': 'ja',
              'created_at': '2026-09-26T01:02:03Z',
            },
          ],
          'meta': {
            'request_id': requestId,
            'next_cursor': later ? null : 'later',
            'has_more': !later,
          },
        });
      }
      if (options.path.startsWith('/api/v1/novels/')) {
        chapterGets++;
        return body({
          'data': {
            'material_id': locator['material_id'],
            'library_id': locator['library_id'],
            'revision_id': locator['material_revision_id'],
            'node_id': locator['novel_chapter_id'],
            'title': locator['node_title'],
            'blocks': [
              {
                'id': span['block_id'],
                'chapter_block_id': locator['chapter_block_id'],
                'canonical_text': locator['quote'],
                'ordinal': 0,
                'source_locator': locator,
              },
            ],
          },
          'meta': {'request_id': requestId},
        });
      }
      throw StateError('Unexpected ${options.path}');
    });
    final api = ApiClient(config, adapter: adapter);
    final auth = AuthController(
      AuthRepository(api, config),
      config,
      vault: _Vault(),
      sync: _Sync(),
    );
    addTearDown(() {
      auth.dispose();
      api.close();
    });
    expect(
      await tester.runAsync(() => auth.login('user@example.test', 'valid-test-password')),
      isTrue,
    );
    final reference = ReferenceController(auth, ReferenceRepository(api));
    addTearDown(reference.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.materialPath(locator['material_id'] as String),
      routes: [
        GoRoute(
          path: AppRoutes.materials,
          builder: (_, _) => const Scaffold(body: Text('library')),
        ),
        GoRoute(
          path: AppRoutes.material,
          builder: (_, state) => MaterialEntryPage(materialId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ReferenceFeatureScope(
        controller: reference,
        child: MaterialApp.router(
          routerConfig: router,
          theme: HarukaTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await settleAsyncFrames(tester);
    await waitForAsyncState(
      tester,
      () =>
          (reference.chapter?.blocks.isNotEmpty ?? false) &&
          find.byType(MobileNovelView).evaluate().isNotEmpty,
      reason: 'The authorized paginated source must publish its reader projection',
    );
    expect(materialGets, 2, reason: 'a source link may target a later authorized page');
    expect(chapterGets, 1);
    expect(reference.chapter?.blocks.single.text, locator['quote']);
    expect(find.byType(MobileNovelView), findsOneWidget);
  });

  for (final viewport in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('published second block owns one selection toolbar at $viewport', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = SampleAdapter((options, _) async {
        if (options.path == '/api/v1/meta') {
          return body({
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': requestId},
          });
        }
        if (options.path == '/api/v1/auth/native/login') {
          return body(samples['auth_native_authenticated'] as Object);
        }
        if (options.path == '/api/v1/me/access') {
          return body(samples['auth_client_access_login_only'] as Object);
        }
        throw StateError('Unexpected ${options.path}');
      });
      final api = ApiClient(config, adapter: adapter);
      final auth = AuthController(
        AuthRepository(api, config),
        config,
        vault: _Vault(),
        sync: _Sync(),
      );
      addTearDown(() {
        auth.dispose();
        api.close();
      });
      expect(
        await tester.runAsync(() => auth.login('user@example.test', 'valid-test-password')),
        isTrue,
      );
      final reference = ReferenceController(auth, ReferenceRepository(api));
      addTearDown(reference.dispose);
      final source =
          (samples['learning_word_card'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final locator = (source['source_refs'] as List<dynamic>).single as Map<String, dynamic>;
      final material = published.MaterialSummary(
        id: locator['material_id'] as String,
        libraryId: locator['library_id'] as String,
        revisionId: locator['material_revision_id'] as String,
        firstChapterId: locator['novel_chapter_id'] as String,
        title: locator['source_title'] as String,
        language: 'ja',
      );
      final blocks = List.generate(
        3,
        (index) => published.NovelBlock(
          id: '018f1234-0000-7000-8000-00000000000$index',
          chapterBlockId: '018f1234-0000-7000-8000-00000000001$index',
          text: '句子 $index。',
          ordinal: index,
          locator: published.NovelContentLocator.fromJson(locator),
        ),
      );
      final chapter = published.NovelChapter(
        materialId: material.id,
        libraryId: material.libraryId,
        revisionId: material.revisionId,
        nodeId: material.firstChapterId,
        title: '第一章',
        blocks: blocks,
      );
      final data = PublishedNovelViewData(
        item: material,
        chapter: chapter,
        blocks: blocks,
        reference: reference,
        openingScope: referenceScope(auth, 'reference'),
        selectedIndex: 1,
        selectedText: '句子 1',
        fontSize: 18,
        onWholeBlock: (_) {},
        onNativeSelection: (_, _) {},
        onQuery: () {},
        onClear: () {},
        onFont: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: HarukaTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: viewport.width < 600
                ? MobileNovelView.published(data: data)
                : DesktopNovelView.published(data: data),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NovelSelectionToolbar), findsOneWidget);
      expect(find.text('长按一句，点选词汇后查询。'), findsOneWidget);
    });
  }
}

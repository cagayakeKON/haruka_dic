import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';
import 'package:haruka/features/library/presentation/material_management_controls.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/library/data/http_material_catalog.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/collections/reference_repository.dart';
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/core/api/learning_models.dart' as published;
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/library/data/material_import_repository.dart';
import 'package:haruka/features/library/data/material_repository.dart';
import 'package:haruka/features/library/domain/material_import.dart';
import 'package:haruka/features/library/domain/material_metadata.dart';
import 'package:haruka/features/library/domain/material_summary.dart';

import '../../support/generated/api_compatibility_samples.dart';
import '../../support/sample_adapter.dart';
import '../../support/test_database.dart';

const _intentId = '018f1234-0000-7000-8000-0000000000aa';
const _uploadId = '018f1234-0000-7000-8000-0000000000bb';
const _materialId = '018f1234-0000-7000-8000-0000000000cc';
const _jobId = '018f1234-0000-7000-8000-0000000000dd';
const _requestId = '018f1234-0000-7000-8000-000000000099';

void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('M1 mobile source reuse closes its owner before import and stays closed on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = (await tester.runAsync(
      () => _Harness.start(
        permissions: [
          'client.material.list',
          'client.material.read',
          'client.material.import',
          'client.exam.read',
          'client.exam.edit',
        ],
      ),
    ))!;
    final catalog = (await tester.runAsync(() => _catalog(h)))!;
    await tester.runAsync(() => catalog.refresh());
    final backgroundDraft = TextEditingController(text: 'retained background draft');
    addTearDown(backgroundDraft.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.materials,
      routes: [
        GoRoute(
          path: AppRoutes.materials,
          builder: (context, _) => Scaffold(
            body: Column(
              children: [
                TextField(key: const ValueKey('background-draft'), controller: backgroundDraft),
                TextButton(
                  onPressed: () =>
                      showLiveMaterialDialog(context, catalog, _materialId, onOpenMaterial: () {}),
                  child: const Text('Open reuse details'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.materialImport,
          builder: (_, state) =>
              ImportPage(sourceMaterialId: state.uri.queryParameters['source_material_id']),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialCatalogScope(
        catalog: catalog,
        child: ShellPresentationScope(
          displayName: 'Synthetic',
          activeLanguage: 'ja',
          reducedMotion: true,
          canReadMaterials: true,
          canReadCollections: false,
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
    final background = tester.element(find.byKey(const ValueKey('background-draft')));
    final reads = h.materialReads, details = h.materialFindReads;
    final draft = catalog.importDraft;
    Future<void> openReuse() async {
      await tester.tap(find.text('Open reuse details'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialMetadataContent), findsOneWidget);
      await tester.tap(find.text('以另一类型重新导入'));
      for (var i = 0; i < 100 && find.byType(ImportPage).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ImportPage), findsOneWidget);
      expect(find.byType(MaterialMetadataContent), findsNothing);
      expect(tester.widget<ImportPage>(find.byType(ImportPage)).sourceMaterialId, _materialId);
    }

    await openReuse();
    await tester.tap(find.byTooltip('返回').first);
    await tester.pumpAndSettle();
    expect(find.text('材料详情'), findsNothing);
    expect(tester.element(find.byKey(const ValueKey('background-draft'))), same(background));
    expect(backgroundDraft.text, 'retained background draft');
    expect(catalog.importDraft, same(draft));
    expect(h.materialReads, reads);
    expect(h.materialFindReads, details);
    expect(h.createWrites, 0);
    await openReuse();
    for (var step = 0; step < 2; step++) {
      for (
        var i = 0;
        i < 100 &&
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed == null;
        i++
      ) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.tap(find.text('下一步'));
      await tester.pump();
    }
    await tester.tap(find.text('确认导入').last);
    for (var i = 0; i < 100 && find.byType(ImportPage).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ImportPage), findsNothing);
    expect(find.text('材料详情'), findsNothing);
    expect(find.text('Open reuse details'), findsOneWidget);
    expect(backgroundDraft.text, 'retained background draft');
    expect(h.createWrites, 1);
    expect(h.createBody!['source_material_id'], _materialId);
    expect(h.uploaded, isEmpty);
    expect(h.materialReads, reads + 1); // Only the accepted mutation invalidates the catalog.
    expect(h.materialFindReads, details);
    expect(tester.takeException(), isNull);
    h.auth.pauseAccessDeadline();
  });
  testWidgets('M1 committed deletion closes its dialog after the metadata child is removed', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => _Harness.start(
        permissions: [
          'client.material.list',
          'client.material.read',
          'client.material.delete',
          'client.exam.edit',
        ],
      ),
    ))!;
    final catalog = (await tester.runAsync(() => _catalog(h)))!;
    await tester.runAsync(() => catalog.refresh());
    final committedRefresh = Completer<void>(), releaseRefresh = Completer<ResponseBody>();
    await tester.pumpWidget(
      MaterialCatalogScope(
        catalog: catalog,
        child: MaterialApp(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showLiveMaterialDialog(context, catalog, _materialId, onOpenMaterial: () {}),
                child: const Text('Open existing details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open existing details'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialMetadataContent), findsOneWidget);
    h.pageWait = (_) {
      if (!committedRefresh.isCompleted) committedRefresh.complete();
      return releaseRefresh.future;
    };
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    for (var i = 0; i < 100 && !committedRefresh.isCompleted; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(committedRefresh.isCompleted, isTrue);
    await tester.pump();
    expect(find.byType(MaterialMetadataContent), findsNothing);
    expect(find.text('材料已删除或不可读取'), findsOneWidget);
    expect(h.materialWrites, [
      {'expected_revision': '3'},
    ]);
    releaseRefresh.complete(_page([]));
    for (var i = 0; i < 100 && find.text('材料详情').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(find.text('材料详情'), findsNothing);
    expect(find.text('Open existing details'), findsOneWidget);
    expect(catalog.metadata(_materialId), isNull);
    h.auth.pauseAccessDeadline();
  });
  testWidgets('M1 metadata rename uses registered update permission and selected revision', (
    tester,
  ) async {
    for (final grants in [(false, false), (true, false), (true, true)]) {
      final (canUpdate, canEditExam) = grants;
      final h = (await tester.runAsync(
        () => _Harness.start(
          permissions: [
            'client.material.list',
            'client.material.read',
            'client.material.delete',
            'client.material.import',
            if (canUpdate) 'client.material.update',
            if (canEditExam) ...['client.exam.read', 'client.exam.edit'],
          ],
        ),
      ))!;
      final catalog = (await tester.runAsync(() => _catalog(h)))!;
      h.pageWait = (_) async => _page([
        h.materialWrites.isEmpty ? _metadata() : {..._metadata(), 'title': '本人更新标题', 'revision': 4},
      ]);
      await tester.runAsync(() => catalog.refresh());
      await tester.pumpWidget(
        MaterialCatalogScope(
          catalog: catalog,
          child: MaterialApp(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MaterialMetadataContent(catalog: catalog, row: catalog.metadata(_materialId)!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!canUpdate || !canEditExam) {
        expect(find.widgetWithText(OutlinedButton, '修改标题'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, '以另一类型重新导入'), findsNothing);
        expect(find.widgetWithText(TextButton, '删除'), findsNothing);
        final context = tester.element(find.byType(MaterialMetadataContent));
        await renameMaterial(context, catalog, catalog.metadata(_materialId)!);
        await deleteLiveMaterial(context, catalog, catalog.metadata(_materialId)!);
        expect(h.materialWrites, isEmpty);
        continue;
      }
      await tester.tap(find.widgetWithText(OutlinedButton, '修改标题'));
      await tester.pumpAndSettle();
      // 101 graphemes, 201 Unicode code points: platform input length alone
      // cannot enforce the Pydantic title limit.
      await tester.enterText(find.byType(TextField), '${List.filled(100, 'a\u0301').join()}b');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(h.materialWrites, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '本人更新标题');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(h.materialWrites, [
        {'expected_revision': 3, 'title': '本人更新标题'},
      ]);
      expect(catalog.metadata(_materialId)!.revision, 4);
      expect(h.auth.isAuthenticated, isTrue);
      h.auth.pauseAccessDeadline();
    }
  });
  testWidgets('M1 desktop source-only rows do not invent catalog task progress', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final h = (await tester.runAsync(
      () => _Harness.start(permissions: ['client.material.list', 'client.material.read']),
    ))!;
    final catalog = (await tester.runAsync(() => _catalog(h)))!;
    await tester.runAsync(() => catalog.refresh());
    for (final width in [960.0, 660.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        MaterialCatalogScope(
          catalog: catalog,
          child: MaterialApp(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DesktopLibraryResults(
                items: catalog.filterMaterials(const MaterialCatalogQuery()),
                viewportAnchor: MaterialViewportAnchor(),
                type: null,
                query: '',
                onReset: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('处理中'), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    }
  });
  testWidgets(
    'M1 navigation restores the same unknown intent and logout rejects late draft results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(
        () => _Harness.start(
          loseCompletionResponse: true,
          permissions: ['client.material.import', 'client.material.list'],
        ),
      ))!;
      final catalog = (await tester.runAsync(() => _catalog(h)))!;
      final file = _MutableFile(utf8.encode('# Public synthetic material'));
      final router = GoRouter(
        initialLocation: AppRoutes.materialImport,
        routes: [
          GoRoute(
            path: AppRoutes.materialImport,
            builder: (_, _) => ImportPage(pickFile: () async => file),
          ),
          GoRoute(
            path: AppRoutes.materials,
            builder: (_, _) => const Scaffold(body: Text('library target')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialCatalogScope(
          catalog: catalog,
          child: ShellPresentationScope(
            displayName: 'Synthetic',
            activeLanguage: 'ja',
            reducedMotion: true,
            canReadMaterials: true,
            canReadCollections: false,
            child: MaterialApp.router(
              routerConfig: router,
              theme: HarukaTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      );
      Future<void> waitUntil(bool Function() ready) async {
        for (var i = 0; i < 100 && !ready(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          ready(),
          isTrue,
          reason:
              'phase=${h.auth.phase.name}, '
              'create=${h.createWrites}, complete=${h.completeWrites}, '
              'status=${catalog.importDraft?.intent?.status}, busy=${catalog.importDraft?.busy}, '
              'error=${catalog.importDraft?.error is ApiFailure ? (catalog.importDraft!.error as ApiFailure).code : catalog.importDraft?.error.runtimeType}, '
              'catalog=${catalog.status.name}',
        );
      }

      Future<void> selectAndSubmit() async {
        await waitUntil(
          () =>
              tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed !=
              null,
        );
        await tester.tap(find.text('下一步'));
        await tester.pump();
        await tester.tap(find.text('选择材料文件'));
        await tester.pump();
        final writesBefore = h.createWrites;
        await tester.enterText(find.byType(TextField), '${List.filled(100, 'a\u0301').join()}b');
        await tester.pump();
        expect(
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed,
          isNull,
        );
        tester.widget<MobileImportView>(find.byType(MobileImportView)).onNext();
        await tester.pump();
        expect(h.createWrites, writesBefore);
        await tester.enterText(find.byType(TextField), 'Public synthetic title');
        await tester.pump();
        await tester.tap(find.text('下一步'));
        await tester.pump();
        expect(find.text('本次仅验证原件；正文尚未就绪，不进行 OCR/AI 解析。'), findsOneWidget);
        expect(find.text('原件格式'), findsOneWidget);
        expect(find.text('MD'), findsOneWidget);
        expect(find.text('原件已受理，正文尚未就绪。当前任务仅验证来源，不进行 OCR 或 AI 解析。'), findsNothing);
        await tester.tap(find.text('确认导入').last);
        await tester.pump();
      }

      await tester.pump();
      await waitUntil(
        () =>
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed != null,
      );
      expect(find.text('试卷'), findsNothing);
      tester
          .widget<MobileImportView>(find.byType(MobileImportView))
          .onType(LearningMaterialType.exam);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed,
        isNull,
      );
      tester.widget<MobileImportView>(find.byType(MobileImportView)).onNext();
      await tester.pump();
      expect(h.createWrites, 0);
      tester
          .widget<MobileImportView>(find.byType(MobileImportView))
          .onType(LearningMaterialType.novel);
      await tester.pump();
      await selectAndSubmit();
      await waitUntil(
        () => catalog.importDraft?.unknown == true && catalog.importDraft?.busy == false,
      );
      final draft = catalog.importDraft!;
      expect(draft.intent!.id, _intentId);
      expect(h.createWrites, 1);
      expect(h.completeWrites, 1);
      router.go(AppRoutes.materials);
      await tester.pumpAndSettle();
      expect(find.byType(ImportPage), findsNothing);
      router.go(AppRoutes.materialImport);
      await tester.pump();
      await waitUntil(
        () =>
            find.text('查看受理结果').evaluate().isNotEmpty &&
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, '查看受理结果')).onPressed !=
                null,
      );
      expect(catalog.importDraft, same(draft));
      expect(h.createWrites, 1);
      await tester.tap(find.text('查看受理结果'));
      await tester.pump();
      await waitUntil(() => find.text('library target').evaluate().isNotEmpty);
      expect(catalog.importDraft, isNull);
      expect(h.createWrites, 1);
      expect(h.completeWrites, 1);

      // Cache clear advances the local identity even when the auth session stays
      // valid; a retained intent or late result cannot cross that generation.
      final clearDraft = MaterialImportDraft(
        scope: catalog.scopeIdentity,
        key: draft.key,
        type: draft.type,
        language: draft.language,
        title: draft.title,
        file: file,
      );
      clearDraft.intent = draft.intent;
      catalog.retainImport(clearDraft);
      final sessionBeforeClear = h.auth.repository.api.sessionBinding;
      final localBeforeClear = catalog.cache.accountGeneration;
      await tester.runAsync(() => catalog.cache.clearScope());
      await tester.pump();
      expect(h.auth.repository.api.sessionBinding, same(sessionBeforeClear));
      expect(catalog.cache.accountGeneration, greaterThan(localBeforeClear));
      expect(catalog.importDraft, isNull);
      catalog.retainImport(clearDraft);
      expect(catalog.importDraft, isNull);

      final createReached = Completer<void>(), createReleased = Completer<void>();
      h.createWait = () {
        createReached.complete();
        return createReleased.future;
      };
      router.go(AppRoutes.materialImport);
      await tester.pump();
      await selectAndSubmit();
      await waitUntil(() => createReached.isCompleted);
      final oldDraft = catalog.importDraft!;
      await tester.runAsync(h.auth.logout);
      await tester.pump();
      expect(catalog.importDraft, isNull);
      createReleased.complete();
      await waitUntil(() => !oldDraft.busy);
      catalog.retainImport(oldDraft);
      expect(catalog.importDraft, isNull);
      expect(h.createWrites, 2);
      expect(h.completeWrites, 1);
      expect(find.text('library target'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'M1 existing published metadata avoids an all-library read and tombstone cannot reopen it',
    () async {
      final h = await _Harness.start(permissions: ['client.material.list', 'client.material.read']);
      final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
      final row = published.MaterialSummary.fromJson(
        (samples['material_metadata_published'] as Map)['data'],
      );
      final controller = ReferenceController(h.auth, ReferenceRepository(h.api));
      addTearDown(controller.dispose);
      expect(await controller.ensureMaterial(row.id, available: row), same(row));
      expect(h.materialReads, 0);
      controller.retireMaterial(row.id);
      expect(await controller.ensureMaterial(row.id, available: row), isNull);
      await controller.openMaterial(row);
      expect(controller.chapter, isNull);
      expect(controller.materials, isEmpty);
      expect(h.materialReads, 0);
    },
  );
  test(
    'M1 committed deletion rejects a missing-detail response issued before its tombstone',
    () async {
      final h = await _Harness.start();
      final catalog = await _catalog(h);
      final pending = Completer<ResponseBody>();
      final reached = Completer<void>();
      h.materialFindWait = () {
        reached.complete();
        return pending.future;
      };
      h.pageResponse = (_) => _page([]);
      final detail = catalog.detail(_materialId);
      final rejected = expectLater(detail, throwsA(_code('SESSION_INVALID')));
      await reached.future;
      await catalog.deleteRevision(MaterialMetadata.fromJson(_metadata()));
      pending.complete(
        ResponseBody.fromString(
          jsonEncode({
            'data': _metadata(),
            'meta': {'request_id': _requestId},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await rejected;
      expect(catalog.metadata(_materialId), isNull);
      expect(h.materialFindReads, 1);
      expect(h.materialWrites, [
        {'expected_revision': '3'},
      ]);
    },
  );
  test(
    'M1 published projection skips non-novel and source-only rows without losing page cursor',
    () async {
      final h = await _Harness.start();
      final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
      final published =
          (samples['material_metadata_published'] as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      h.pageResponse = (_) => _page([
        _metadata(),
        {..._metadata(), 'material_type': 'novel'},
        published.cast<String, Object?>(),
      ], cursor: 'mixed-next-page');
      final page = await h.auth.authorizedRead(
        (headers) => ReferenceRepository(h.api).materials(headers),
      );
      expect(page.data, hasLength(1));
      expect(page.data.single.id, published['id']);
      expect(page.data.single.revisionId, published['revision_id']);
      expect(page.data.single.firstChapterId, published['first_chapter_id']);
      expect(page.nextCursor, 'mixed-next-page');
      expect(h.materialReads, 1);
      expect(h.materialFindReads, 0);
    },
  );
  test('M1 catalog preserves scoped metadata and reads only changed query or next page', () async {
    final h = await _Harness.start();
    final catalog = await _catalog(h);
    h.pageResponse = (request) => _page([
      _metadata(),
      if (request.uri.queryParameters['cursor'] != null)
        {..._metadata(), 'id': _uploadId, 'material_type': 'textbook'},
    ], cursor: request.uri.queryParameters['cursor'] == null ? 'next-page' : null);
    await catalog.refresh();
    expect(catalog.status, MaterialCatalogStatus.ready);
    final row = catalog.metadata(_materialId);
    expect(row!.readable, isFalse);
    expect(row.contentRevisionId, isNull);
    expect(await catalog.detail(_materialId), same(row));
    await catalog.refresh();
    expect(h.materialReads, 1);
    expect(h.materialFindReads, 0);
    await catalog.more();
    expect(h.materialReads, 2);
    expect(catalog.filterMaterials(const MaterialCatalogQuery()).map((r) => r.id), [
      _materialId,
      _uploadId,
    ]);
    expect(catalog.hasMore, isFalse);
    await catalog.refresh(
      query: const MaterialCatalogQuery(
        type: LearningMaterialType.exam,
        language: 'en',
        search: '合成',
      ),
    );
    expect(h.materialQuery!['language'], 'en');
    expect(h.materialQuery!['material_type'], 'exam');
    expect(h.materialQuery!['search'], '合成');
    expect(h.materialReads, 3);
  });

  test(
    'M1 catalog commits rename and exact confirmed deletion revision before one refresh',
    () async {
      final h = await _Harness.start();
      final events = <(String, Map<String, Object?>)>[];
      final catalog = await _catalog(h, onEvent: (event, attrs) => events.add((event, attrs)));
      h.pageResponse = (_) => _page(
        h.materialWrites.length > 1
            ? []
            : [
                h.materialWrites.isEmpty
                    ? _metadata()
                    : {..._metadata(), 'title': '更新标题', 'revision': 4},
              ],
      );
      await catalog.refresh();
      await catalog.rename(_materialId, 3, '更新标题');
      expect(catalog.metadata(_materialId)!.title, '更新标题');
      expect(h.materialReads, 2);
      final confirmed = catalog.metadata(_materialId)!;
      await catalog.deleteRevision(confirmed);
      expect(h.materialWrites, [
        {'expected_revision': 3, 'title': '更新标题'},
        {'expected_revision': '4'},
      ]);
      expect(h.materialReads, 3);
      expect(catalog.metadata(_materialId), isNull);
      expect(catalog.filterMaterials(const MaterialCatalogQuery()), isEmpty);
      expect(events.map((e) => e.$1), ['material.metadata.updated', 'material.deleted']);
      expect(
        events.every(
          (e) => e.$2.length == 2 && e.$2['material_type'] == 'exam' && e.$2['result'] == 'success',
        ),
        isTrue,
      );
    },
  );

  test('M1 catalog drops a pending old-account page and keeps its new scope empty', () async {
    final h = await _Harness.start();
    final catalog = await _catalog(h);
    final pending = Completer<ResponseBody>();
    final reached = Completer<void>();
    h.pageWait = (_) {
      reached.complete();
      return pending.future;
    };
    final read = catalog.refresh();
    await reached.future;
    await h.auth.logout();
    pending.complete(_page([_metadata()]));
    await read;
    expect(catalog.status, MaterialCatalogStatus.blocked);
    expect(catalog.metadata(_materialId), isNull);
    expect(catalog.filterMaterials(const MaterialCatalogQuery()), isEmpty);
    expect(h.materialReads, 1);
  });

  test('format-specific capability rejects before reading bytes or reserving an intent', () async {
    final h = await _Harness.start(formatLimit: 2);
    final file = _MutableFile([1, 2, 3]);
    await expectLater(h.create(file), throwsA(_code('INPUT_INVALID')));
    expect(file.reads, 0);
    expect(h.createWrites, 0);
  });
  test('only the verified snapshot is uploaded and completion keeps its intent key', () async {
    final h = await _Harness.start();
    final file = _MutableFile([35, 32, 65]);
    final intent = await h.create(file);
    expect((h.createBody!['file'] as Map)['sha256'], sha256.convert([35, 32, 65]).toString());
    file.bytes = [9, 9, 9, 9, 9];
    final accepted = await h.repository.uploadAndComplete(intent, file);
    expect(accepted.accepted, isTrue);
    expect(h.uploaded, [35, 32, 65]);
    expect(file.reads, 1);
    expect(
      h.uploadHeaders.keys.any(
        (key) => const {'cookie', 'authorization'}.contains(key.toLowerCase()),
      ),
      isFalse,
    );
    expect(h.uploadHeaders['X-Haruka-Upload-Grant'], 'synthetic-staging-only');
    expect(h.completeBody, {'expected_revision': 1});
    expect(h.completeKey, _intentId);
    expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
  });

  test('a source that grows during snapshot reading is rejected before intent creation', () async {
    final h = await _Harness.start();
    final file = _MutableFile([1, 2, 3], declaredSize: 2);
    await expectLater(h.create(file), throwsA(_code('INPUT_INVALID')));
    expect(h.createWrites, 0);
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
  });

  test(
    'concurrent file readers share one bounded snapshot budget and release on failure',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final h = await _Harness.start(maxSize: 80 * 1024 * 1024);
      final first = _MutableFile(
        [],
        declaredSize: 80 * 1024 * 1024,
        beforeRead: () async {
          started.complete();
          await release.future;
        },
      );
      final pending = h.create(first);
      final failed = expectLater(pending, throwsA(_code('INPUT_INVALID')));
      await started.future;
      final second = _MutableFile([1]);
      await expectLater(h.create(second), throwsA(_code('STATE_CONFLICT')));
      expect(second.reads, 0);
      expect(h.createWrites, 0);
      release.complete();
      await failed;
      expect((await h.create(second)).status, 'awaiting_upload');
      expect(second.reads, 1);
      expect(h.createWrites, 1);
    },
  );

  for (final target in [
    'https://external.example/api/v1/uploads/$_uploadId/content',
    '/api/v1/uploads/$_materialId/content',
    '/api/v1/uploads/$_uploadId/content?token=unexpected',
    '/api/v1/uploads/$_uploadId/content#fragment',
    'http://user@localhost:18443/api/v1/uploads/$_uploadId/content',
  ]) {
    test(
      'a forged staging target is rejected before private file transmission: ${Uri.parse(target).hasQuery
          ? 'query'
          : Uri.parse(target).hasFragment
          ? 'fragment'
          : Uri.parse(target).userInfo.isNotEmpty
          ? 'userinfo'
          : Uri.parse(target).host.isEmpty
          ? 'different resource'
          : 'external origin'}',
      () async {
        final h = await _Harness.start(uploadTarget: target);
        final file = _MutableFile([1, 2, 3]);
        // Structurally invalid grants are rejected at the JSON boundary; valid
        // external and wrong-resource grants fail the transport fence.
        await expectLater(() async {
          final intent = await h.create(file);
          await h.repository.uploadAndComplete(intent, file);
        }(), throwsA(isA<ApiFailure>()));
        expect(h.uploaded, isEmpty);
        expect(h.completeWrites, 0);
      },
    );
  }

  test('logout during staging transfer never completes the old owner import', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final h = await _Harness.start(
      uploadWait: () async {
        started.complete();
        await release.future;
      },
    );
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    final pending = h.repository.uploadAndComplete(intent, file);
    await started.future;
    await h.auth.logout();
    release.complete();
    await expectLater(pending, throwsA(_code('SESSION_INVALID')));
    expect(h.completeWrites, 0);
  });

  test('unknown completion is recovered by reading the existing accepted import', () async {
    final h = await _Harness.start(loseCompletionResponse: true);
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    await expectLater(h.repository.uploadAndComplete(intent, file), throwsA(isA<ApiFailure>()));
    expect(h.completeWrites, 1);
    final recovered = await h.repository.find(intent.id);
    expect(recovered.accepted, isTrue);
    expect(recovered.materialId, _materialId);
    expect(recovered.jobId, _jobId);
    expect(h.completeWrites, 1);
    expect(h.createWrites, 1);
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
  });

  test(
    'cancellation sends revision CAS and authenticated write headers then drops bytes',
    () async {
      final h = await _Harness.start();
      final file = _MutableFile([1, 2, 3]);
      final intent = await h.create(file);
      await h.repository.cancel(intent);
      expect(h.cancelRevision, '1');
      expect(h.cancelHeaders['X-CSRF-Token'], isNotEmpty);
      await expectLater(
        h.repository.uploadAndComplete(intent, file),
        throwsA(_code('SESSION_INVALID')),
      );
      expect(h.completeWrites, 0);
    },
  );

  test('unsupported language and type-format combination create no intent', () async {
    final h = await _Harness.start();
    await expectLater(
      h.create(_MutableFile([1, 2, 3]), language: 'zh'),
      throwsA(_code('INPUT_INVALID')),
    );
    await expectLater(
      h.create(_MutableFile([1, 2, 3], filename: 'scan.png')),
      throwsA(_code('INPUT_INVALID')),
    );
    expect(h.createWrites, 0);
    expect(h.completeWrites, 0);
  });

  test('PDF admission follows the current novel and textbook capabilities', () async {
    for (final type in [LearningMaterialType.novel, LearningMaterialType.textbook]) {
      final h = await _Harness.start();
      final intent = await h.repository.create(
        file: _MutableFile([37, 80, 68, 70], filename: 'source.pdf'),
        type: type,
        language: 'ja',
        title: '合成PDF',
        idempotencyKey: _intentId,
      );
      expect(intent.type, type);
      expect(intent.status, 'awaiting_upload');
      expect(intent.accepted, isFalse);
      expect(intent.materialId, isNull);
      expect((h.createBody!['file'] as Map)['format'], 'pdf');
      expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
      expect(h.uploaded, isEmpty);
      expect(h.completeWrites, 0);
    }
  });

  test('expired local intent drops its snapshot without cancelling server state', () async {
    final h = await _Harness.start();
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    final expired = MaterialImport(
      id: intent.id,
      revision: intent.revision,
      type: intent.type,
      language: intent.language,
      status: intent.status,
      expiresAt: DateTime.utc(2000),
      upload: intent.upload,
    );
    await expectLater(
      h.repository.uploadAndComplete(expired, file),
      throwsA(_code('RESOURCE_EXPIRED')),
    );
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
    expect(h.cancelRevision, isNull);
  });

  test('owned source reuse sends only its ID and never stages private bytes', () async {
    final h = await _Harness.start();
    final result = await h.repository.reimportExisting(
      sourceId: _materialId,
      targetType: LearningMaterialType.exam,
      language: 'en',
      title: ' 新材料 ',
      idempotencyKey: _intentId,
    );
    expect(result.accepted, isTrue);
    expect(result.upload, isNull);
    expect(result.type, LearningMaterialType.exam);
    expect(h.createBody!['source_material_id'], _materialId);
    expect(h.createBody!.containsKey('file'), isFalse);
    expect(h.createBody!['title'], '新材料');
    expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
    expect(h.materialWrites, isEmpty);
  });

  test(
    'catalog preserves null content IDs and scoped filters without claiming readiness',
    () async {
      final h = await _Harness.start();
      final page = await HttpMaterialRepository(h.auth).list(
        type: LearningMaterialType.exam,
        language: 'en',
        search: ' 合成 ',
        cursor: 'safe-cursor',
      );
      expect(h.materialQuery, {
        'limit': '20',
        'material_type': 'exam',
        'language': 'en',
        'search': '合成',
        'cursor': 'safe-cursor',
      });
      expect(page.nextCursor, 'next-safe-cursor');
      final material = page.data.single;
      expect(material.sourceStatus, 'parsing');
      expect(material.analysisStatus, 'not_requested');
      expect(material.readable, isFalse);
      expect(material.contentRevisionId, isNull);
      expect(material.firstChapterId, isNull);
      expect(material.progressPercent, isNull);
      expect(material.revision, 3);
    },
  );

  test('material title and tombstone deletion use current revision and CSRF', () async {
    final h = await _Harness.start();
    final catalog = HttpMaterialRepository(h.auth);
    final renamed = await catalog.rename(_materialId, 3, ' 修改后 ');
    expect(renamed.title, '修改后');
    expect(renamed.revision, 4);
    await catalog.delete(_materialId, renamed.revision);
    expect(h.materialWrites, [
      {'expected_revision': 3, 'title': '修改后'},
      {'expected_revision': '4'},
    ]);
    expect(h.materialWriteHeaders.every((headers) => headers['X-CSRF-Token'] is String), isTrue);
    expect(h.completeWrites, 0);
    expect(h.createWrites, 0);
  });

  test('old published IDs remain available and unsupported metadata is rejected', () {
    final json = _metadata()
      ..['revision_id'] = _intentId
      ..['first_chapter_id'] = _uploadId
      ..['source_status'] = 'readable'
      ..['readable'] = true;
    final old = MaterialMetadata.fromJson(json);
    expect(old.contentRevisionId, _intentId);
    expect(old.firstChapterId, _uploadId);
    expect(old.readable, isTrue);
    expect(
      () => MaterialMetadata.fromJson({...json, 'material_type': 'mixed'}),
      throwsFormatException,
    );
    expect(
      () => MaterialMetadata.fromJson({...json, 'progress_percent': 101}),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _metadata() => {
  'id': _materialId,
  'library_id': _intentId,
  'material_type': 'exam',
  'title': '合成材料',
  'language': 'en',
  'source_format': 'pdf',
  'source_status': 'parsing',
  'analysis_status': 'not_requested',
  'revision': 3,
  'delete_generation': 0,
  'revision_id': null,
  'first_chapter_id': null,
  'job_id': _jobId,
  'progress_percent': null,
  'readable': false,
  'created_at': '2026-10-02T00:00:00Z',
  'updated_at': '2026-10-02T00:00:00Z',
};

ResponseBody _page(List<Map<String, Object?>> items, {String? cursor}) => ResponseBody.fromString(
  jsonEncode({
    'data': items,
    'meta': {'request_id': _requestId, 'has_more': cursor != null, 'next_cursor': cursor},
  }),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

Future<HttpMaterialCatalog> _catalog(
  _Harness h, {
  void Function(String, Map<String, Object?>)? onEvent,
}) async {
  final cache = CacheCoordinator(
    openBackend: (_) async => OpenedCacheBackend(
      executor: NativeDatabase.memory(),
      mode: CacheStorageMode.memoryOnly,
      closeOwner: () async {},
    ),
  );
  final access = h.auth.access!;
  await cache.attach(
    CacheScope.confirmed(
      endpoint: h.api.endpoint,
      instanceId: h.auth.boundInstanceId,
      userId: access.userId,
      audience: 'client',
      sessionRef: access.sessionRef,
      securityEpoch: access.securityEpoch ?? -1,
      authzVersion: access.authzVersion.user,
      policyVersion: access.authzVersion.policy,
    ),
  );
  final catalog = HttpMaterialCatalog(
    auth: h.auth,
    cache: cache,
    repository: HttpMaterialRepository(h.auth),
    imports: h.repository,
    onEvent: onEvent,
  );
  addTearDown(() async {
    catalog.dispose();
    await cache.closeScope();
  });
  return catalog;
}

Matcher _code(String code) => isA<ApiFailure>().having((error) => error.code, 'code', code);

final class _Harness {
  late final AuthController auth;
  late final ApiClient api;
  late final HttpMaterialImportRepository repository;
  Map<String, Object?>? createBody;
  Object? completeBody;
  Object? completeKey;
  int createWrites = 0;
  int completeWrites = 0;
  String? cancelRevision;
  Map<String, dynamic> cancelHeaders = {};
  Map<String, dynamic> uploadHeaders = {};
  final List<int> uploaded = [];
  Map<String, String>? materialQuery;
  final List<Object?> materialWrites = [];
  final List<Map<String, dynamic>> materialWriteHeaders = [];
  int materialReads = 0, materialFindReads = 0;
  ResponseBody Function(RequestOptions)? pageResponse;
  Future<ResponseBody> Function(RequestOptions)? pageWait;
  Future<ResponseBody> Function()? materialFindWait;
  Future<void> Function()? createWait;

  static Future<_Harness> start({
    String uploadTarget = '/api/v1/uploads/$_uploadId/content',
    Future<void> Function()? uploadWait,
    bool loseCompletionResponse = false,
    int maxSize = 1024,
    int? formatLimit,
    List<String> permissions = const [],
  }) async {
    final h = _Harness();
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://localhost:18443',
    );
    ResponseBody envelope(Object data, [int status = 200]) => ResponseBody.fromString(
      jsonEncode({
        'data': data,
        'meta': {'request_id': _requestId},
      }),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    Map<String, Object?> intent({
      bool accepted = false,
      String type = 'novel',
      String language = 'ja',
    }) => {
      'id': _intentId,
      'revision': accepted ? 2 : 1,
      'material_type': h.createBody?['material_type'] ?? type,
      'language': language,
      'status': accepted ? 'accepted' : 'awaiting_upload',
      'expires_at': '2099-01-01T00:00:00Z',
      'material_id': accepted ? _materialId : null,
      'job_id': accepted ? _jobId : null,
      'upload': accepted
          ? null
          : {
              'id': _uploadId,
              'method': 'PUT',
              'url': uploadTarget,
              'headers': {'X-Haruka-Upload-Grant': 'synthetic-staging-only'},
              'expires_at': '2099-01-01T00:00:00Z',
            },
    };
    final adapter = SampleAdapter((options, _) async {
      switch (options.uri.path) {
        case '/api/v1/meta':
          return envelope({
            'instance_id': config.instanceId,
            'api_version': 'v1',
            'release': 'test',
          });
        case '/api/v1/auth/login':
          return ResponseBody.fromString(
            jsonEncode(samples['auth_web_authenticated']),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/auth/csrf':
          return envelope({
            'session_ref': '018f1234-0000-7000-8000-000000000002',
            'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          });
        case '/api/v1/me/access':
          final access = jsonDecode(
            jsonEncode(samples['auth_client_access_login_only']),
          ) as Map<String, dynamic>;
          if (permissions.isNotEmpty) {
            (access['data'] as Map)['permissions'] = [
              {'code': 'client.login', 'data_scope': 'self'},
              for (final code in permissions) {'code': code, 'data_scope': 'self'},
            ];
          }
          return ResponseBody.fromString(
            jsonEncode(access),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/material-import-capabilities':
          return envelope({
            'schema_version': 1,
            'capabilities': [
              {
                'material_type': 'novel',
                'formats': ['md', 'epub', 'pdf'],
                'languages': ['ja', 'en'],
                'max_size_bytes': maxSize,
                if (formatLimit != null) 'format_max_size_bytes': {'md': formatLimit},
              },
              {
                'material_type': 'textbook',
                'formats': ['md', 'epub', 'pdf'],
                'languages': ['ja', 'en'],
                'max_size_bytes': maxSize,
              },
              {
                'material_type': 'exam',
                'formats': ['md', 'epub', 'pdf', 'png', 'jpeg', 'webp'],
                'languages': ['ja', 'en'],
                'max_size_bytes': 1024,
              },
            ],
            'quota_bytes': maxSize * 2,
            'used_bytes': 0,
            'reserved_bytes': 0,
            'upload_ttl_seconds': 600,
          });
        case '/api/v1/material-imports':
          h.createWrites++;
          h.createBody = (options.data as Map).cast<String, Object?>();
          await h.createWait?.call();
          if (h.createBody!.containsKey('source_material_id')) {
            return envelope(
              intent(
                accepted: true,
                type: h.createBody!['material_type'] as String,
                language: h.createBody!['language'] as String,
              ),
              201,
            );
          }
          return envelope(intent(), 201);
        case '/api/v1/uploads/$_uploadId/complete':
          h.completeWrites++;
          h.completeBody = options.data;
          h.completeKey = options.headers['Idempotency-Key'];
          if (loseCompletionResponse) {
            throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
          }
          return envelope(intent(accepted: true), 202);
        case '/api/v1/materials':
          h.materialReads++;
          h.materialQuery = options.uri.queryParameters;
          if (h.pageWait != null) return h.pageWait!(options);
          if (h.pageResponse != null) return h.pageResponse!(options);
          return ResponseBody.fromString(
            jsonEncode({
              'data': [_metadata()],
              'meta': {
                'request_id': _requestId,
                'has_more': true,
                'next_cursor': 'next-safe-cursor',
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/materials/$_materialId':
          if (options.method == 'PATCH') {
            h.materialWrites.add(options.data);
            h.materialWriteHeaders.add(options.headers);
            return envelope({
              ..._metadata(),
              'title': (options.data as Map)['title'],
              'revision': 4,
            });
          }
          if (options.method == 'DELETE') {
            h.materialWrites.add(options.uri.queryParameters);
            h.materialWriteHeaders.add(options.headers);
            return ResponseBody.fromString('', 204);
          }
          h.materialFindReads++;
          if (h.materialFindWait != null) return h.materialFindWait!();
          return envelope(_metadata());
        case '/api/v1/material-imports/$_intentId':
          if (options.method == 'DELETE') {
            h.cancelRevision = options.uri.queryParameters['expected_revision'];
            h.cancelHeaders = options.headers;
            return ResponseBody.fromString('', 204);
          }
          return envelope(intent(accepted: true));
      }
      throw const FormatException('Unexpected synthetic route');
    });
    final uploadAdapter = SampleAdapter((options, stream) async {
      h.uploadHeaders = options.headers;
      if (stream != null) {
        await for (final chunk in stream) {
          h.uploaded.addAll(chunk);
        }
      }
      await uploadWait?.call();
      return ResponseBody.fromString('', 204);
    });
    final transport = Dio();
    transport.httpClientAdapter = uploadAdapter;
    h.api = ApiClient(config, adapter: adapter);
    h.auth = AuthController(AuthRepository(h.api, config), config, vault: _Vault(), sync: _Sync());
    h.repository = HttpMaterialImportRepository(h.auth, uploads: transport);
    addTearDown(() {
      h.repository.dispose();
      h.auth.dispose();
      h.api.close();
    });
    expect(await h.auth.login('user@example.test', 'synthetic-test-password'), isTrue);
    h.auth.pauseAccessDeadline();
    return h;
  }

  Future<MaterialImport> create(XFile file, {String language = 'ja'}) => repository.create(
    file: file,
    type: LearningMaterialType.novel,
    language: language,
    title: '合成材料',
    idempotencyKey: _intentId,
  );
}

final class _MutableFile implements XFile {
  _MutableFile(this.bytes, {this.declaredSize, this.filename = 'source.md', this.beforeRead});
  List<int> bytes;
  final int? declaredSize;
  final String filename;
  final Future<void> Function()? beforeRead;
  int reads = 0;
  @override
  String get name => filename;
  @override
  Future<int> length() async => declaredSize ?? bytes.length;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    reads++;
    await beforeRead?.call();
    yield Uint8List.fromList(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected selected-file operation');
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

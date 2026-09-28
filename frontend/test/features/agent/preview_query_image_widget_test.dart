import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/agent/presentation/query_page.dart';
import 'package:haruka/features/agent/application/query_images.dart';
import 'package:haruka/core/platform/query_paste.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

final _png = File('test/fixtures/preview/query_image.png').readAsBytesSync();
RawQueryImage _sampleImage() => RawQueryImage(name: 'chosen.png', bytes: _png);

class _SettingsSourceStub implements SettingsSource {
  @override
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel) async => SettingsSnapshot(
    group: group,
    revision: 1,
    fields: switch (group) {
      SettingsGroup.studyProfile => {
        'active_target_language': 'ja',
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

class _FakeQueryImagePort implements QueryImagePort {
  List<RawQueryImage> selected = [];
  Future<List<RawQueryImage>>? pendingPick;
  RawQueryImage? photo;
  int pickCalls = 0;
  int cameraCalls = 0;

  @override
  Future<List<RawQueryImage>> pickImages() async {
    pickCalls++;
    return pendingPick ?? selected;
  }

  @override
  Future<RawQueryImage?> takePhoto() async {
    cameraCalls++;
    return photo;
  }

  @override
  Future<List<RawQueryImage>> recoverLostPhotos() async => [];
}

class _FakeQueryPasteSource implements QueryPasteSource {
  bool Function()? canAccept;
  void Function(List<RawQueryImage>)? onImages;

  @override
  void start({
    required bool Function() canAccept,
    required void Function(List<RawQueryImage>) onImages,
    required void Function(QueryImageProblem) onReadError,
  }) {
    this.canAccept = canAccept;
    this.onImages = onImages;
  }

  @override
  void dispose() {}

  void paste(RawQueryImage image) {
    if (canAccept?.call() ?? false) onImages?.call([image]);
  }
}

Future<CacheCoordinator> _pumpQuery(
  WidgetTester tester,
  PreviewFixtureStore store,
  QueryImagePort port,
  Size size, {
  QueryPasteSource? pasteSource,
}) async {
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
  addTearDown(cache.closeScope);
  await tester.runAsync(
    () => cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/mock-preview'),
        instanceId: 'preview-fixtures',
        userId: 'preview-user',
        audience: 'client',
        sessionRef: 'preview-session',
      ),
    ),
  );
  final settings = CachedSettingsRepository(cache: cache, source: _SettingsSourceStub());
  addTearDown(settings.dispose);
  await tester.runAsync(() => settings.refresh(SettingsGroup.studyProfile));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            QueryPage(imagePort: port, pasteSource: pasteSource, queryResults: store),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    SettingsRepositoryScope(
      repository: settings,
      child: PreviewStoreScope(
        store: store,
        child: MaterialApp.router(
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cache;
}

void main() {
  testWidgets('phone gallery image previews, can zoom/remove, and never fabricates a card', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final port = _FakeQueryImagePort()..selected = [_sampleImage()];
    await _pumpQuery(tester, store, port, const Size(390, 844));
    expect(find.byType(MobileQueryView), findsOneWidget);
    expect(find.byType(DesktopQueryView), findsNothing);

    await tester.tap(find.text('相册'));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(port.pickCalls, 1);
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsOneWidget);
    final removeSize = tester.getSize(find.byKey(const ValueKey('query-image-remove-0')));
    expect(removeSize.width, greaterThanOrEqualTo(44));
    expect(removeSize.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const ValueKey('query-image-preview-0')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(IconButton)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('图片尚未分析，无法生成学习卡片'), findsOneWidget);
    expect(find.byType(QueryResultCard), findsNothing);
    await tester.tap(find.byKey(const ValueKey('query-image-remove-0')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '发送')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop mixed draft keeps text while file cancellation and paste add images', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final port = _FakeQueryImagePort();
    final paste = _FakeQueryPasteSource();
    await _pumpQuery(tester, store, port, const Size(1440, 900), pasteSource: paste);
    expect(find.byType(DesktopQueryView), findsOneWidget);
    final input = find.byType(TextField).first;
    await tester.enterText(input, '翻译图片里的句子');
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    expect(port.pickCalls, 1);
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsNothing);
    await tester.tap(input);
    paste.paste(_sampleImage());
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '翻译图片里的句子');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('图片尚未分析，无法生成学习卡片'), findsOneWidget);
    expect(find.byType(QueryResultCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch clears draft and hides image preview and late picker result', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final port = _FakeQueryImagePort()..selected = [_sampleImage()];
    final cache = await _pumpQuery(tester, store, port, const Size(390, 844));
    await tester.enterText(find.byType(TextField).first, 'private query');
    await tester.tap(find.text('相册'));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsOneWidget);

    final delayed = Completer<List<RawQueryImage>>();
    port.pendingPick = delayed.future;
    await tester.tap(find.text('相册'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('query-image-preview-0')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.runAsync(
      () => cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('http://127.0.0.1/mock-preview'),
          instanceId: 'preview-fixtures',
          userId: 'another-user',
          audience: 'client',
          sessionRef: 'another-session',
        ),
      ),
    );
    delayed.complete([_sampleImage()]);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android phone camera returns photo to same draft', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final port = _FakeQueryImagePort()..photo = _sampleImage();
    await _pumpQuery(tester, store, port, const Size(390, 844));
    final input = find.byType(TextField).first;
    await tester.enterText(input, '请解释这道题');
    await tester.tap(find.text('拍照'));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(port.cameraCalls, 1);
    expect(find.byKey(const ValueKey('query-image-preview-0')), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '请解释这道题');
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

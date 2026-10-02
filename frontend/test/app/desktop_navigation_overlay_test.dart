import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/config/app_config.dart';

import '../support/sample_adapter.dart';

void main() {
  testWidgets('desktop real shell navigation retains an overlay for hover', (tester) async {
    final temporary = Directory.systemTemp.createTempSync('haruka-route-test-');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final stored = <String, String>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temporary.path,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storageChannel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final key = arguments['key'] as String?;
      if (call.method == 'write') stored[key!] = arguments['value'] as String;
      if (call.method == 'delete') stored.remove(key);
      if (call.method == 'read') return stored[key];
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storageChannel, null);
      temporary.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = AppConfig.parse(
      platform: AppPlatform.windows,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://127.0.0.1:18081',
    );
    final samples = jsonDecode(
      File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final reads = <String>[];
    final access = samples['auth_client_access_login_only'] as Map<String, dynamic>;
    final accessData = access['data'] as Map<String, dynamic>;
    (accessData['permissions'] as List<dynamic>).add({
      'code': 'client.profile.read',
      'data_scope': 'self',
    });
    final api = ApiClient(
      config,
      adapter: SampleAdapter((options, _) async {
        reads.add(options.path);
        final sample = switch (options.uri.path) {
          '/api/v1/meta' => {
            'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          },
          '/api/v1/auth/native/login' => samples['auth_native_authenticated'],
          '/api/v1/me/access' => access,
          '/api/v1/users/me/profile' => samples['settings_profile_empty'],
          '/api/v1/users/me/settings' => samples['settings_preferences_empty'],
          '/api/v1/users/me/study-profile' => samples['settings_study_empty'],
          '/api/v1/users/me/account' => samples['auth_account_legacy_unverified'],
          '/api/v1/auth/sessions' => samples['auth_sessions_page'],
          _ => {
            'data': <String, Object?>{},
            'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
          },
        };
        return ResponseBody.fromString(
          jsonEncode(sample),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }),
    );
    await tester.pumpWidget(HarukaApp(config: config, api: api, initialLocation: '/environment'));
    await tester.pumpAndSettle();
    final providers = tester
        .widget<UncontrolledProviderScope>(find.byType(UncontrolledProviderScope).first)
        .container;
    final auth = providers.read(authControllerProvider);
    await tester.runAsync(() => auth.login('test@example.test', 'synthetic-password'));
    await tester.pumpAndSettle();
    final router = tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig! as GoRouter;
    router.go('/settings');
    await tester.pumpAndSettle();
    final side = find.byType(PreviewSideNavigation);
    expect(side, findsOneWidget);
    final navigation = find.descendant(of: side, matching: find.text('我的')).first;
    expect(navigation, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    final labelsBeforeHover = find.text('我的').evaluate().length;
    await mouse.moveTo(tester.getCenter(navigation));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(RawTooltip), findsWidgets);
    expect(find.text('我的').evaluate().length, greaterThan(labelsBeforeHover));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('我的').evaluate().length, labelsBeforeHover);
    await mouse.moveTo(tester.getCenter(find.byTooltip('站内消息')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('站内消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(navigation);
    await tester.pumpAndSettle();
    final background = tester.element(find.byType(PreviewPageFrame).first);
    final before = reads.length;
    for (final width in [900.0, 390.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.element(find.byType(PreviewPageFrame).first), same(background));
    }
    expect(reads.skip(before), isEmpty);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });
}

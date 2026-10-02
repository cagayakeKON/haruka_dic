import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  testWidgets('security dialog preserves the matched page and immersive shell', (tester) async {
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
    tester.view.physicalSize = const Size(390, 844);
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
    await tester.ensureVisible(find.text('安全与账号').last);
    await tester.tap(find.text('安全与账号').last);
    await tester.pumpAndSettle();
    final background = tester.element(find.byType(PreviewPageFrame).first);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('查看会话'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    final before = reads.length;
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('查看会话'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PreviewPersistentShell>(find.byType(PreviewPersistentShell)).location.value,
        '/settings/security',
      );
      expect(find.byType(NavigationBar), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(PreviewPageFrame).first), same(background));
      expect(find.byType(NavigationBar), findsNothing);
    }
    expect(reads.skip(before).toList(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import '../test_support/sample_adapter.dart';

void main() {
  final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');

  testWidgets('health is explicit and survives resize without duplicate requests', (tester) async {
    final pending = Completer<ResponseBody>();
    final adapter = SampleAdapter((_, _) => pending.future);
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(HarukaApp(config: config, api: api, initialLocation: '/environment'));
    await tester.pumpAndSettle();
    expect(adapter.calls, 0);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.checkConnection)));
    await tester.pump();
    expect(find.text('正在检查…'), findsOneWidget);
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(adapter.calls, 1);
    pending.complete(
      ResponseBody.fromString(
        jsonEncode({
          'data': {'status': 'ok'},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('服务已就绪'), findsOneWidget);
    expect(adapter.calls, 1);
  });

  testWidgets('health failure uses local language and never remote messages', (tester) async {
    final adapter = SampleAdapter(
      (_, _) async => ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'SERVICE_UNAVAILABLE', 'message': 'private sentinel'},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        503,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    await tester.pumpWidget(HarukaApp(config: config, api: api, initialLocation: '/environment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(UiTestIds.checkConnection)));
    await tester.pumpAndSettle();
    expect(find.text('服务尚未就绪'), findsOneWidget);
    expect(find.textContaining('private sentinel'), findsNothing);
    expect(adapter.calls, 1);
  });
}

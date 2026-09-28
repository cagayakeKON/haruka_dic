import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';

void main() {
  testWidgets('unknown settings deep link shows a visible unavailable state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PreviewPageFrame).first);
    GoRouter.of(context).go(AppRoutes.mockSettingPath('unknown'));
    await tester.pumpAndSettle();
    expect(find.text('页面不可用'), findsOneWidget);
    expect(find.text('此页面不存在，或不适用于当前平台。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-numeric and out-of-range mistake deep links show not found', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(PreviewPageFrame).first));

    for (final path in ['/mock/mistakes/abc', '/mock/mistakes/999']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('未找到资源'), findsOneWidget, reason: path);
      expect(find.text('归因：'), findsNothing, reason: path);
      expect(tester.takeException(), isNull, reason: path);
    }
  });
}

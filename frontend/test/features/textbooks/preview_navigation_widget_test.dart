import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/features/library/presentation/material_pages.dart';

void main() {
  setUpAll(initializeTestDatabase);
  testWidgets('Android back returns from textbook unit to unit directory first', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('日语的日常表达'));
    await tester.pumpAndSettle();
    expect(find.text('单元目录'), findsOneWidget);

    await tester.tap(find.text('一起去车站'));
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPage), findsOneWidget);
    expect(find.text('Unit 02 · 一起去车站'), findsOneWidget);
    expect(find.text('单元目录'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextbookPage), findsOneWidget);
    expect(find.text('单元目录'), findsOneWidget);
    expect(find.text('一起去车站'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

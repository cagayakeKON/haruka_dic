import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import '../test_support/controls_app.dart';

void main() {
  testWidgets('control draft focus and identity survive adaptive reflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const ControlsApp());
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey(UiTestIds.fixtureInput)),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '保留草稿');
    for (final width in [599.0, 600.0, 1023.0, 1024.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      expect(find.byKey(const ValueKey(UiTestIds.fixtureInput)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

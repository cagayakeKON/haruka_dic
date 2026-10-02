import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/controls_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UIE-02 platform: edit, confirm, scroll and route using controls', (tester) async {
    await tester.pumpWidget(const ControlsApp());
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey(UiTestIds.fixtureInput)),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'Haruka 原型');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(UiTestIds.fixtureSubmit)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.fixtureDialog)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.fixtureConfirm)));
    await tester.pumpAndSettle();
    expect(find.text('已确认：Haruka 原型'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey(UiTestIds.fixtureLastRow)),
      500,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey(UiTestIds.fixtureList)),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('控件样本 80'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.fixtureNavigate)));
    await tester.pumpAndSettle();
    expect(find.text('路由刷新原型'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.backHome)));
    await tester.pumpAndSettle();
    expect(find.text('Haruka 原型'), findsOneWidget);
  });
}

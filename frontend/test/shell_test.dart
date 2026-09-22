import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/app/app_shell.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/generated/ui_test_ids.dart';

void main() {
  final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');

  Future<void> pumpShell(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(HarukaApp(config: config));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(390, 844),
    const Size(599, 600),
    const Size(600, 600),
    const Size(1023, 600),
    const Size(1024, 600),
    const Size(1280, 400),
  ]) {
    testWidgets('SCF-FE-SHELL widget: shell navigation at ${size.width}x${size.height}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, size, scale: size.height == 400 ? 2 : 1);
      expect(find.byKey(const ValueKey(UiTestIds.homePage)), findsOneWidget);
      expect(find.byKey(const ValueKey(UiTestIds.environmentNavigation)), findsOneWidget);
      expect(find.bySemanticsIdentifier(UiTestIds.environmentNavigation), findsOneWidget);
      final navigationSemantics = tester
          .getSemantics(find.bySemanticsIdentifier(UiTestIds.environmentNavigation))
          .getSemanticsData();
      expect(navigationSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(navigationSemantics.label, contains('环境信息'));
      expect(navigationSemantics.label, isNot(contains(UiTestIds.environmentNavigation)));
      expect(find.text('尚未开放'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.tap(find.byKey(const ValueKey(UiTestIds.environmentNavigation)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(UiTestIds.environmentPage)), findsOneWidget);
      expect(find.text('haruka-local-dev'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SCF-FE-RESIZE widget: current route survives a compact to expanded change', (
    tester,
  ) async {
    await pumpShell(tester, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey(UiTestIds.environmentNavigation)));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.environmentPage)), findsOneWidget);
    expect(find.byKey(const ValueKey(UiTestIds.environmentNavigation)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(WideNavigation), findsOneWidget);
  });

  testWidgets('SCF-FE-KEYBOARD widget: Tab and Enter reach environment information', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1280, 720));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.environmentPage)), findsOneWidget);
  });

  testWidgets('SCF-FE-ADMIN widget: admin route exists only in Web compilation', (tester) async {
    await tester.pumpWidget(HarukaApp(config: config, initialLocation: '/admin'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey(kIsWeb ? UiTestIds.adminPage : UiTestIds.notFoundPage)),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey(kIsWeb ? UiTestIds.notFoundPage : UiTestIds.adminPage)),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey(UiTestIds.backHome)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.homePage)), findsOneWidget);
  });

  testWidgets('SCF-FE-ERROR widget: invalid startup configuration has no normal shell', (
    tester,
  ) async {
    await tester.pumpWidget(const ConfigurationErrorApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.configurationError)), findsOneWidget);
    expect(find.byKey(const ValueKey(UiTestIds.homeNavigation)), findsNothing);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/generated/ui_test_ids.dart';

void main() {
  final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');

  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    testWidgets('service connection uses the single public surface at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(HarukaApp(config: config, initialLocation: AppRoutes.environment));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(UiTestIds.environmentPage)), findsOneWidget);
      expect(find.text(config.apiBaseUrl.toString()), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid startup configuration stays outside the application shell', (tester) async {
    await tester.pumpWidget(const ConfigurationErrorApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.configurationError)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('management route is available only to the Web build', (tester) async {
    await tester.pumpWidget(HarukaApp(config: config, initialLocation: AppRoutes.admin));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(UiTestIds.notFoundPage)),
      kIsWeb ? findsNothing : findsOneWidget,
    );
  });
}

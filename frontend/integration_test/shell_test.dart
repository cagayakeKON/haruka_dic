import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SCF-FE-SMOKE integration: launch and navigate using real controls', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.homePage)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.environmentNavigation)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.environmentPage)), findsOneWidget);
    expect(find.text('haruka-local-dev'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(UiTestIds.homeNavigation)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.homePage)), findsOneWidget);
  });

  testWidgets('SCF-FE-ADMIN integration: compiled platform controls admin registration', (
    tester,
  ) async {
    // This probes route registration. It does not authenticate or bypass a business flow.
    final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');
    await tester.pumpWidget(HarukaApp(config: config, initialLocation: '/admin'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey(kIsWeb ? UiTestIds.adminPage : UiTestIds.notFoundPage)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey(UiTestIds.backHome)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.homePage)), findsOneWidget);
  });
}

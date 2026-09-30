import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  testWidgets('phone shell keeps settings when fewer than two destinations remain', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShellPresentationScope(
          displayName: '测试',
          activeLanguage: 'ja',
          reducedMotion: false,
          canReadMaterials: false,
          canReadCollections: false,
          navigationRoutes: const {},
          child: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: PreviewBottomNavigation(
              location: AppRoutes.materials,
              onSelected: (section) => selected = section.name,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('我的'), findsOneWidget);
    await tester.tap(find.text('我的'));
    expect(selected, 'settings');
  });
}

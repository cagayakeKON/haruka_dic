import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'configured phone navigation preserves default labels and applies order and customization',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
            canReadMaterials: true,
            canReadCollections: true,
            navigationItems: const [
              NavigationItem(
                key: 'query',
                routeKey: AppRoutes.query,
                title: '查词入口',
                titleCustomized: true,
                iconKey: 'book',
                iconCustomized: true,
              ),
              NavigationItem(
                key: 'materials',
                routeKey: AppRoutes.materials,
                title: '书库',
                iconKey: 'library',
              ),
              NavigationItem(
                key: 'settings',
                routeKey: AppRoutes.settings,
                title: '设置',
                iconKey: 'settings',
              ),
            ],
            child: Scaffold(
              bottomNavigationBar: PreviewBottomNavigation(
                location: AppRoutes.query,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      final destinations = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .toList();
      expect(destinations.map((item) => item.label), ['查词入口', '材料', '我的']);
      expect(find.byIcon(Icons.menu_book_outlined), findsWidgets);
      expect(find.byIcon(Icons.auto_stories_outlined), findsWidgets);
      expect(find.byIcon(Icons.person_outline), findsWidgets);
    },
  );
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

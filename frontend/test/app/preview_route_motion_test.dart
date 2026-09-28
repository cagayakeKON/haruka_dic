import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/routes.dart';

import '../support/preview_test_app.dart';

void main() {
  testWidgets('preview routes animate and respect reduced motion', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();

    CustomTransitionPage<void> currentPage() =>
        tester.state<NavigatorState>(find.byType(Navigator).last).widget.pages.last
            as CustomTransitionPage<void>;

    expect(currentPage().transitionDuration, HarukaMotion.pageEnter);
    final pageContext = tester.element(find.byType(PreviewPageFrame).first);
    final store = PreviewStoreScope.of(pageContext);
    final router = GoRouter.of(pageContext);
    final navigation = tester.element(find.byType(NavigationBar));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).animationDuration,
      HarukaMotion.selection,
    );
    router.go(AppRoutes.mockNotebooks);
    await tester.pump();
    expect(identical(tester.element(find.byType(NavigationBar)), navigation), isTrue);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    await tester.pumpAndSettle();

    store.updateAppearance('light', true);

    router.go(AppRoutes.mockQuery);
    await tester.pumpAndSettle();
    expect(currentPage().transitionDuration, Duration.zero);
    expect(currentPage().reverseTransitionDuration, Duration.zero);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).animationDuration,
      Duration.zero,
    );
  });

  testWidgets('desktop shell stays mounted and each rail width owns one header', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final shell = tester.element(find.byType(PreviewPersistentShell));
    final sidebar = tester.element(find.byType(PreviewSideNavigation));
    final context = tester.element(find.byType(PreviewPageFrame).first);
    final router = GoRouter.of(context);
    final store = PreviewStoreScope.of(context);
    router.go(AppRoutes.mockNotebooks);
    await tester.pumpAndSettle();
    expect(identical(tester.element(find.byType(PreviewPersistentShell)), shell), isTrue);
    expect(identical(tester.element(find.byType(PreviewSideNavigation)), sidebar), isTrue);
    expect(find.byTooltip('站内消息'), findsOneWidget);

    for (final width in [600.0, 800.0, 900.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.byType(PreviewSideNavigation), findsOneWidget);
      expect(find.byType(MobilePreviewShell), width < 840 ? findsOneWidget : findsNothing);
      expect(find.byType(DesktopPreviewShell), width < 840 ? findsNothing : findsOneWidget);
      expect(find.byTooltip('站内消息'), width < 840 ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    store.updateAppearance('light', true);
    await tester.pumpAndSettle();
    final indicators = find.descendant(
      of: find.byType(PreviewSideNavigation),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.widget<AnimatedContainer>(indicators.first).duration, Duration.zero);
  });
}

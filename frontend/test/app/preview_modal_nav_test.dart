import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/preview_test_app.dart';

void main() {
  testWidgets('review: modal sheet must block persistent tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final more = find.byWidgetPredicate(
      (widget) => widget is IconButton && (widget.tooltip ?? '').contains('更多操作'),
    );
    expect(more, findsWidgets);
    await tester.tap(more.first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navCenter = tester.getCenter(find.byType(NavigationBar));
    expect(tester.getRect(find.byType(ModalBarrier).last).contains(navCenter), isTrue);
    await tester.tapAt(navCenter);
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
  });

  testWidgets('system back closes root sheet before leaving the tab', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final more = find.byWidgetPredicate(
      (widget) => widget is IconButton && (widget.tooltip ?? '').contains('更多操作'),
    );
    await tester.tap(more.first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
  });

  testWidgets('system back from a detail restores the persistent tabs', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('站内消息').first);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
  });
}

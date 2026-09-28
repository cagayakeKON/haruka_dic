import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';

import '../../support/preview_test_app.dart';

void main() {
  testWidgets('notebook row opens the same cached collection in mobile detail', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '词本'));
    await tester.pumpAndSettle();

    final row = find.byWidgetPredicate(
      (widget) => widget is MobileCollectionRow && widget.item.displayText == 'そっと',
    );
    expect(row, findsOneWidget);
    await tester.tap(find.descendant(of: row, matching: find.text('そっと')));
    await tester.pumpAndSettle();

    expect(find.byType(WordDetailDialog), findsOneWidget);
    expect(find.text('そっと'), findsWidgets);
    expect(find.text('轻轻地；悄悄地'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

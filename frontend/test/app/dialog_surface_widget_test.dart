import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';

void main() {
  testWidgets('short screen with keyboard keeps dialog close and action reachable', (tester) async {
    tester.view.physicalSize = const Size(360, 540);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 190);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showHarukaDialog<void>(
                context: context,
                builder: (dialogContext) => HarukaDialogSurface(
                  title: '材料详情',
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('完成'),
                    ),
                  ],
                  child: Column(children: [for (var i = 0; i < 20; i++) Text('内容 $i')]),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final close = find.byTooltip('关闭');
    final action = find.text('完成');
    expect(tester.getRect(close).bottom, lessThan(tester.getRect(action).top));
    expect(tester.getRect(action).bottom, lessThan(350));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(HarukaDialogSurface), findsNothing);
  });
}

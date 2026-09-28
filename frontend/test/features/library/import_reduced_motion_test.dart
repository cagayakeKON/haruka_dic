import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/library/domain/material_summary.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  testWidgets('import step indicator stops animating when reduced motion is selected', (
    tester,
  ) async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      PreviewStoreScope(
        store: store,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MobileImportView(
              step: 0,
              type: LearningMaterialType.novel,
              fileName: null,
              aiStructure: false,
              onType: (_) {},
              onAiStructure: (_) {},
              onFile: () {},
              onNext: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final indicators = find.descendant(
      of: find.byType(MobileImportView),
      matching: find.byType(AnimatedContainer),
    );
    expect(indicators, findsNWidgets(3));
    expect(tester.widget<AnimatedContainer>(indicators.first).duration, isNot(Duration.zero));

    store.updateAppearance('system', true);
    await tester.pump();
    for (final indicator in indicators.evaluate()) {
      expect((indicator.widget as AnimatedContainer).duration, Duration.zero);
    }
  });
}

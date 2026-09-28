import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/library/presentation/material_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  testWidgets('mobile question review keeps its actions above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const MobileExamQuestionReviewSheet(
                  questions: [
                    ExamQuestionDraft(number: 1, group: ExamQuestionGroup.listening, score: 2),
                    ExamQuestionDraft(number: 2, group: ExamQuestionGroup.language, score: 1),
                  ],
                ),
              ),
              child: const Text('打开校对'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开校对'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final confirm = find.text('确认校对');
    expect(confirm, findsOneWidget);
    expect(tester.getBottomRight(confirm).dy, lessThan(844 - 320));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/auth/auth_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

void main() {
  Future<void> pumpAuth(WidgetTester tester, Size size, Widget page) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mobile registration uses the confirmed layout and real callback', (tester) async {
    String? submittedEmail;
    String? submittedPassword;
    await pumpAuth(
      tester,
      const Size(390, 844),
      RegistrationPage(
        passwordMinLength: 15,
        passwordMaxLength: 128,
        onBackToLogin: () {},
        onRegister: (email, password) async {
          submittedEmail = email;
          submittedPassword = password;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey(UiTestIds.registerSubmit)));
    await tester.pump();
    expect(submittedEmail, isNull);

    await tester.enterText(
      find.byKey(const ValueKey(UiTestIds.registerEmail)),
      'demo@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey(UiTestIds.registerPassword)),
      'abcdefghijklmno',
    );
    await tester.enterText(
      find.byKey(const ValueKey(UiTestIds.registerConfirm)),
      'different-password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey(UiTestIds.registerSubmit)));
    await tester.tap(find.byKey(const ValueKey(UiTestIds.registerSubmit)));
    await tester.pump();
    expect(submittedEmail, isNull);
    expect(find.text('两次输入的密码不一致'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey(UiTestIds.registerConfirm)),
      'abcdefghijklmno',
    );
    await tester.ensureVisible(find.byKey(const ValueKey(UiTestIds.registerSubmit)));
    await tester.tap(find.byKey(const ValueKey(UiTestIds.registerSubmit)));
    await tester.pump();
    expect(submittedEmail, 'demo@example.test');
    expect(submittedPassword, 'abcdefghijklmno');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop registration retains the split composition', (tester) async {
    await pumpAuth(
      tester,
      const Size(1440, 900),
      RegistrationPage(
        passwordMinLength: 15,
        passwordMaxLength: 128,
        onBackToLogin: () {},
        onRegister: (email, password) async {},
      ),
    );
    expect(find.text('从这里开始。'), findsOneWidget);
    expect(find.text('个人学习空间'), findsOneWidget);
    expect(find.byKey(const ValueKey(UiTestIds.registerSubmit)), findsOneWidget);
  });

  testWidgets('mobile service connection preserves the mock card feedback', (tester) async {
    var back = false;
    await pumpAuth(
      tester,
      const Size(390, 844),
      ServiceConnectionPage.preview(onBack: () => back = true),
    );
    expect(find.text('服务连接'), findsOneWidget);
    expect(find.text('Haruka 服务地址'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '检查地址'));
    await tester.pumpAndSettle();
    expect(find.text('地址格式有效'), findsOneWidget);
    await tester.tap(find.byTooltip('返回登录'));
    expect(back, isTrue);
  });
}

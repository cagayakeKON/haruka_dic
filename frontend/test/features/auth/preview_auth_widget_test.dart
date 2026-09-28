import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/account/presentation/preview_auth_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

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

  testWidgets('mobile registration validates fields and shows accepted state', (tester) async {
    await pumpAuth(tester, const Size(390, 844), const PreviewRegisterPage());
    expect(find.text('创建账号'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('请输入邮箱'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('请再次输入密码'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'demo@example.com');
    await tester.enterText(fields.at(1), 'abcdefghijklmno');
    await tester.enterText(fields.at(2), 'different-password');
    await tester.tap(find.widgetWithText(FilledButton, '创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);

    await tester.enterText(fields.at(2), 'abcdefghijklmno');
    await tester.tap(find.widgetWithText(FilledButton, '创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('注册请求已受理'), findsOneWidget);
    expect(find.text('返回登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop registration keeps the split layout and accepted state', (tester) async {
    await pumpAuth(tester, const Size(1440, 900), const PreviewRegisterPage());
    expect(find.text('从这里开始。'), findsOneWidget);
    expect(find.text('个人学习空间'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'demo@example.com');
    await tester.enterText(fields.at(1), 'abcdefghijklmno');
    await tester.enterText(fields.at(2), 'abcdefghijklmno');
    await tester.tap(find.widgetWithText(FilledButton, '创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('注册请求已受理'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile service connection checks address and returns', (tester) async {
    await pumpAuth(tester, const Size(390, 844), const PreviewLoginPage());
    await tester.tap(find.text('服务地址'));
    await tester.pumpAndSettle();
    expect(find.text('服务连接'), findsOneWidget);
    expect(find.text('Haruka 服务地址'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '检查地址'));
    await tester.pumpAndSettle();
    expect(find.text('地址格式有效'), findsOneWidget);

    await tester.tap(find.byTooltip('返回登录'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

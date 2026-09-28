import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/features/auth/auth_forms.dart';
import 'package:haruka/features/auth/auth_pages.dart';
import 'package:haruka/features/auth/email_action_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: appTheme(),
  home: child,
);

void main() {
  testWidgets('administrator login offers the same email recovery without registration', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/admin/login',
      routes: [
        GoRoute(
          path: '/admin/login',
          builder: (context, _) => LoginPage(
            admin: true,
            registrationEnabled: true,
            recoveryEnabled: true,
            onLogin: (_, _) async {},
            onOpenRecovery: () => context.go('/recovery?from=admin'),
            onOpenRegistration: () {},
            onOpenService: () {},
          ),
        ),
        GoRoute(
          path: '/recovery',
          builder: (_, state) => RecoveryRequestPage(
            admin: state.uri.queryParameters['from'] == 'admin',
            onSubmit: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    expect(
      find.text(AppLocalizations.of(tester.element(find.byType(LoginPage))).authForgotPassword),
      findsOneWidget,
    );
    expect(
      find.text(AppLocalizations.of(tester.element(find.byType(LoginPage))).authCreateAccount),
      findsNothing,
    );
    await tester.tap(
      find.text(AppLocalizations.of(tester.element(find.byType(LoginPage))).authForgotPassword),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(), '/recovery?from=admin');
    expect(find.byKey(const ValueKey<String>(UiTestIds.recoveryRequestPage)), findsOneWidget);
  });

  testWidgets('client recovery accepts the first email entry after login navigation', (
    tester,
  ) async {
    String? submitted;
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, _) => LoginPage(
            registrationEnabled: true,
            recoveryEnabled: true,
            onLogin: (_, _) async {},
            onOpenRecovery: () => context.go('/recovery'),
            onOpenRegistration: () {},
            onOpenService: () {},
          ),
        ),
        GoRoute(
          path: '/recovery',
          builder: (_, _) => RecoveryRequestPage(onSubmit: (email) async => submitted = email),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.tap(find.byKey(const ValueKey(UiTestIds.loginRecoveryLink)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey(UiTestIds.recoveryRequestEmail)),
      'user@example.test',
    );
    await tester.tap(find.byKey(const ValueKey(UiTestIds.recoveryRequestSubmit)));
    await tester.pump();
    expect(submitted, 'user@example.test');
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary login action keeps prototype height under compact platform density', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final (viewport, minimumHeight) in [
      (const Size(390, 844), 54.0),
      (const Size(1440, 900), 48.0),
    ]) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: appTheme().copyWith(visualDensity: VisualDensity.compact),
          home: LoginPage(
            registrationEnabled: true,
            recoveryEnabled: true,
            onLogin: (_, _) async {},
            onOpenRecovery: () {},
            onOpenRegistration: () {},
            onOpenService: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.descendant(
        of: find.byKey(const ValueKey<String>(UiTestIds.loginSubmit)),
        matching: find.byType(FilledButton),
      );
      expect(tester.getSize(action).height, greaterThanOrEqualTo(minimumHeight));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('registration password limit counts Unicode codepoints', (tester) async {
    String? accepted;
    await tester.pumpWidget(
      _host(
        RegistrationPage(
          passwordMinLength: 2,
          passwordMaxLength: 2,
          onBackToLogin: () {},
          onRegister: (_, password) async => accepted = password,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.registerEmail)),
      'user@example.test',
    );
    await tester.enterText(find.byKey(const ValueKey<String>(UiTestIds.registerPassword)), '😀a');
    await tester.enterText(find.byKey(const ValueKey<String>(UiTestIds.registerConfirm)), '😀a');
    await tester.ensureVisible(find.byKey(const ValueKey<String>(UiTestIds.registerSubmit)));
    await tester.tap(find.byKey(const ValueKey<String>(UiTestIds.registerSubmit)));
    await tester.pump();
    expect(accepted, '😀a');
  });

  testWidgets('register form stays usable at 200% text scale in a short compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    String? email;
    String? password;
    await tester.pumpWidget(
      _host(
        RegistrationPage(
          passwordMinLength: 15,
          passwordMaxLength: 128,
          onBackToLogin: () {},
          onRegister: (value, secret) async {
            email = value;
            password = secret;
          },
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>(UiTestIds.registerPage)), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.registerEmail)),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.registerPassword)),
      'valid-test-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.registerConfirm)),
      'valid-test-password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey<String>(UiTestIds.registerSubmit)));
    await tester.tap(find.byKey(const ValueKey<String>(UiTestIds.registerSubmit)));
    await tester.pump();
    expect(email, 'user@example.test');
    expect(password, 'valid-test-password');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email link is not consumed before confirmation and wrong-purpose link is rejected', (
    tester,
  ) async {
    var calls = 0;
    const token = 'A1234567890123456789012345678901234567890_-';
    await tester.pumpWidget(
      _host(
        EmailActionPage(
          kind: EmailActionKind.verify,
          trustedActionBase: Uri.parse('https://localhost:18443'),
          onSubmit: (value, _) async {
            expect(value, token);
            calls++;
          },
        ),
      ),
    );
    expect(calls, 0);
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.verificationToken)),
      'https://localhost:18443/reset-password#token=$token',
    );
    await tester.tap(find.byKey(const ValueKey<String>(UiTestIds.verificationSubmit)));
    await tester.pump();
    expect(calls, 0);
    await tester.enterText(
      find.byKey(const ValueKey<String>(UiTestIds.verificationToken)),
      'https://localhost:18443/verify-email#token=$token',
    );
    await tester.tap(find.byKey(const ValueKey<String>(UiTestIds.verificationSubmit)));
    await tester.pump();
    expect(calls, 1);
  });
}

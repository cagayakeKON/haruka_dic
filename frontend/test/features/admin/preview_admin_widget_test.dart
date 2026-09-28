import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/admin/presentation/admin_pages.dart';
import 'package:haruka/features/library/presentation/library_pages.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

import '../../support/preview_test_app.dart';

void main() {
  testWidgets('persistent admin sidebar navigates once and keeps policy draft at rail widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final rootContext = tester.element(find.byType(PreviewPageFrame).first);
    final router = GoRouter.of(rootContext);
    final state = AdminPreviewScope.of(rootContext);
    state.signIn();
    router.go(AppRoutes.mockAdminPath('overview'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminPersistentFrame), findsOneWidget);
    await tester.tap(find.text('账号安全').first);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.mockAdminPath('security'));
    await tester.tap(find.text('注册策略').first);
    await tester.pumpAndSettle();
    state.setRegistration('closed');
    await tester.pumpAndSettle();
    final policyPage = tester.element(find.byType(AdminPage));
    for (final width in [899.0, 900.0, 1024.0, 899.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开管理导航'), width < 900 ? findsOneWidget : findsNothing);
      expect(find.byType(AdminPersistentFrame), findsOneWidget);
      expect(identical(tester.element(find.byType(AdminPage)), policyPage), isTrue);
      expect(state.registration, 'closed');
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.mockAdminPath('policy'));
      expect(tester.takeException(), isNull);
    }
  });

  Future<(AdminPreviewState, GoRouter)> pumpAdmin(
    WidgetTester tester,
    Size size, {
    bool signedIn = false,
    String section = 'overview',
    Set<String>? permissions,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AdminPreviewState(permissions: permissions);
    if (signedIn) state.signIn();
    final router = GoRouter(
      initialLocation: signedIn ? AppRoutes.mockAdminPath(section) : AppRoutes.mockAdminLogin,
      routes: [
        GoRoute(
          path: AppRoutes.mockAdminLogin,
          builder: (context, route) => AdminPage(section: 'login', previewState: state),
        ),
        GoRoute(
          path: AppRoutes.mockAdmin,
          builder: (context, route) => AdminPage(
            section: route.pathParameters['section'] ?? 'overview',
            previewState: state,
          ),
        ),
        GoRoute(path: AppRoutes.mockLogin, builder: (context, route) => const Text('用户端登录')),
      ],
    );
    addTearDown(() {
      router.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: HarukaTheme.light(),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return (state, router);
  }

  testWidgets('desktop admin login validates fields and enters overview', (tester) async {
    final (state, _) = await pumpAdmin(tester, const Size(1440, 900));
    expect(find.text('登录管理端'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效邮箱'), findsOneWidget);
    expect(find.text('密码至少 6 位'), findsOneWidget);
    expect(state.signedIn, isFalse);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'operator@example.test');
    await tester.enterText(fields.last, 'example-only-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isTrue);
    expect(find.text('运维概览'), findsWidgets);
    expect(find.text('登录管理端'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop admin users search and summary stay within operations data', (tester) async {
    final (state, _) = await pumpAdmin(tester, const Size(1440, 900), signedIn: true);
    await tester.tap(find.text('用户与会话').first);
    await tester.pumpAndSettle();
    expect(find.text('learner-a@example.test'), findsOneWidget);
    expect(find.text('learner-b@example.test'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'learner-b');
    await tester.pumpAndSettle();
    expect(state.search, 'learner-b');
    expect(find.text('learner-b@example.test'), findsOneWidget);
    expect(find.text('learner-a@example.test'), findsNothing);
    await tester.tap(find.text('查看运维摘要'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin section navigation uses selected Material list tiles', (tester) async {
    await pumpAdmin(tester, const Size(1440, 900), signedIn: true);
    final users = find.widgetWithText(ListTile, '用户与会话');
    expect(users, findsOneWidget);
    expect(tester.widget<ListTile>(users).selected, isFalse);

    await tester.tap(users);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '用户与会话')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact admin opens Material drawer and navigates from its list tiles', (
    tester,
  ) async {
    final (_, router) = await pumpAdmin(tester, const Size(390, 844), signedIn: true);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, '用户与会话'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.mockAdminPath('users'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop registration policy preview reflects local selections', (tester) async {
    final (state, _) = await pumpAdmin(tester, const Size(1440, 900), signedIn: true);
    await tester.tap(find.text('注册策略').first);
    await tester.pumpAndSettle();
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    expect(dropdowns, findsNWidgets(3));
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭新注册').last);
    await tester.pumpAndSettle();
    expect(state.registration, 'closed');
    expect(state.appliedRegistration, 'approval');
    await tester.tap(find.text('预览策略变化'));
    await tester.pumpAndSettle();
    expect(find.text('策略变更预览'), findsOneWidget);
    expect(find.textContaining('关闭新注册'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(state.appliedRegistration, 'approval');
    await tester.tap(find.text('预览策略变化'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用策略'));
    await tester.pumpAndSettle();
    expect(state.appliedRegistration, 'closed');
    expect(state.hasPolicyChanges, isFalse);
    expect(find.widgetWithText(FilledButton, '预览策略变化'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '预览策略变化')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop password change validates, revokes session, and requires new password', (
    tester,
  ) async {
    final (state, _) = await pumpAdmin(tester, const Size(1440, 900));
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.first, 'operator@example.test');
    await tester.enterText(loginFields.last, 'original-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号安全').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '修改密码'));
    await tester.pumpAndSettle();
    final passwordFields = find.byType(TextFormField);
    expect(passwordFields, findsNWidgets(3));
    await tester.enterText(passwordFields.at(0), 'incorrect-password');
    await tester.enterText(passwordFields.at(1), 'replacement-password');
    await tester.enterText(passwordFields.at(2), 'replacement-password');
    await tester.tap(find.text('保存新密码'));
    await tester.pumpAndSettle();
    expect(find.text('当前密码不正确'), findsOneWidget);
    expect(state.signedIn, isTrue);

    await tester.enterText(passwordFields.at(0), 'original-password');
    await tester.enterText(passwordFields.at(2), 'different-password');
    await tester.tap(find.text('保存新密码'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的新密码不一致'), findsOneWidget);
    await tester.enterText(passwordFields.at(2), 'replacement-password');
    await tester.tap(find.text('保存新密码'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('登录管理端'), findsWidgets);

    final newLoginFields = find.byType(TextFormField);
    await tester.enterText(newLoginFields.first, 'operator@example.test');
    await tester.enterText(newLoginFields.last, 'original-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('邮箱或密码不正确'), findsOneWidget);
    await tester.enterText(newLoginFields.last, 'replacement-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop operations tables span their cards', (tester) async {
    await pumpAdmin(tester, const Size(1440, 900), signedIn: true);
    await tester.tap(find.text('用户与会话').first);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DataTable)).width, greaterThan(900));
    await tester.tap(find.text('角色与权限').first);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DataTable)).width, greaterThan(700));
    final tableLeft = tester.getTopLeft(find.byType(DataTable)).dx;
    final headingLeft = tester.getTopLeft(find.text('角色与权限').last).dx;
    expect((tableLeft - headingLeft).abs(), lessThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop security logout removes management shell', (tester) async {
    final (state, _) = await pumpAdmin(tester, const Size(1440, 900));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'operator@example.test');
    await tester.enterText(fields.last, 'example-only-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isTrue);
    await tester.tap(find.text('账号安全').first);
    await tester.pumpAndSettle();
    expect(find.text('退出管理端'), findsOneWidget);
    await tester.tap(find.text('退出管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('登录管理端'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limited admin signs in to an allowed section and deep links deny data', (
    tester,
  ) async {
    const allowed = {'admin.login', 'admin.user.read'};
    final (state, router) = await pumpAdmin(tester, const Size(1440, 900), permissions: allowed);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'limited@example.test');
    await tester.enterText(fields.last, 'example-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isTrue);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.mockAdminPath('users'));
    expect(find.text('learner-a@example.test'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '用户与会话'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '账号安全'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '角色与权限'), findsNothing);

    router.go(AppRoutes.mockAdminPath('roles'));
    await tester.pumpAndSettle();
    expect(find.text('当前管理会话没有此操作权限。'), findsWidgets);
    expect(find.text('受保护'), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identity without management login permission cannot enter admin', (tester) async {
    final (state, _) = await pumpAdmin(
      tester,
      const Size(1440, 900),
      permissions: {'admin.dashboard.view'},
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'operator@example.test');
    await tester.enterText(fields.last, 'example-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('当前管理会话没有此操作权限。'), findsOneWidget);
    expect(find.text('运维概览'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview hides actions without their destination permissions', (tester) async {
    await pumpAdmin(
      tester,
      const Size(1440, 900),
      signedIn: true,
      permissions: {'admin.login', 'admin.dashboard.view'},
    );
    expect(find.text('128'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '查看任务'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '查看角色'), findsNothing);
    expect(find.widgetWithText(ListTile, '任务与重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('policy reader sees committed values but cannot edit or preview', (tester) async {
    final (state, _) = await pumpAdmin(
      tester,
      const Size(1440, 900),
      signedIn: true,
      section: 'policy',
      permissions: {'admin.login', 'admin.auth_policy.read'},
    );
    expect(find.text('当前策略'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.widgetWithText(FilledButton, '预览策略变化'), findsNothing);
    state.setRegistration('closed');
    expect(state.registration, 'approval');
    expect(state.applyPolicy(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission revocation clears an open summary and a pending policy change', (
    tester,
  ) async {
    final (state, router) = await pumpAdmin(
      tester,
      const Size(1440, 900),
      signedIn: true,
      section: 'users',
    );
    await tester.tap(find.text('查看运维摘要').first);
    await tester.pumpAndSettle();
    expect(find.text('学习者 A'), findsWidgets);
    state.setPermissions({...AdminPreviewState.defaultPermissions}..remove('admin.user.read'));
    await tester.pumpAndSettle();
    expect(find.text('learner-a@example.test'), findsNothing);
    expect(find.text('当前管理会话没有此操作权限。'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    router.go(AppRoutes.mockAdminPath('policy'));
    await tester.pumpAndSettle();
    state.setRegistration('closed');
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览策略变化'));
    await tester.pumpAndSettle();
    state.setPermissions({'admin.login', 'admin.auth_policy.read'});
    await tester.pumpAndSettle();
    expect(state.registration, 'approval');
    expect(find.textContaining('关闭新注册'), findsNothing);
    expect(find.widgetWithText(FilledButton, '应用策略'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '应用策略')).onPressed,
      isNull,
    );
    expect(state.appliedRegistration, 'approval');
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoking admin login hides an open password form and prevents submit', (
    tester,
  ) async {
    final (state, router) = await pumpAdmin(tester, const Size(1440, 900));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'operator@example.test');
    await tester.enterText(fields.last, 'original-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    router.go(AppRoutes.mockAdminPath('security'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '修改密码'));
    await tester.pumpAndSettle();
    expect(find.text('当前密码'), findsOneWidget);
    state.setPermissions({'admin.dashboard.view'});
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('当前密码'), findsNothing);
    expect(find.text('当前管理会话没有此操作权限。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存新密码')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilding preview app starts a fresh management identity and closes old dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final libraryContext = tester.element(find.byType(DesktopLibraryView));
    final oldState = AdminPreviewScope.of(libraryContext);
    oldState.setPermissions({'admin.login', 'admin.user.read'});
    GoRouter.of(libraryContext).go(AppRoutes.mockAdminLogin);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'limited@example.test');
    await tester.enterText(fields.last, 'example-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(oldState.signedIn, isTrue);
    expect(find.text('learner-a@example.test'), findsOneWidget);
    await tester.tap(find.text('查看运维摘要').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    final freshContext = tester.element(find.byType(DesktopLibraryView));
    final freshState = AdminPreviewScope.of(freshContext);
    expect(identical(oldState, freshState), isFalse);
    expect(freshState.signedIn, isFalse);
    expect(freshState.allowsLogin, isTrue);
    GoRouter.of(freshContext).go(AppRoutes.mockAdminPath('users'));
    await tester.pumpAndSettle();
    expect(find.text('登录管理端'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('learner-a@example.test'), findsNothing);
    final freshFields = find.byType(TextFormField);
    await tester.enterText(freshFields.first, 'new-operator@example.test');
    await tester.enterText(freshFields.last, 'different-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录管理端'));
    await tester.pumpAndSettle();
    expect(freshState.signedIn, isTrue);
    expect(freshState.canSection('roles'), isTrue);
    expect(find.widgetWithText(ListTile, '角色与权限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

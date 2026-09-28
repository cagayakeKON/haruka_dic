import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/features/settings/presentation/profile_page.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';

void main() {
  Future<void> pumpMock(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
  }

  PreviewFixtureStore storeFor(WidgetTester tester) =>
      PreviewStoreScope.of(tester.element(find.byType(ProfileDetailPage)));

  Future<void> openMobileProfile(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsView), findsOneWidget);
    await tester.tap(find.text('小遥'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileProfileView), findsOneWidget);
  }

  testWidgets('mobile profile saves edited name, year, gender and timezone', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await openMobileProfile(tester);
    final store = storeFor(tester);
    final fields = find.descendant(
      of: find.byType(ProfileFields),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, '  新名字  ');
    await tester.enterText(fields.last, '2001');

    final dropdowns = find.descendant(
      of: find.byType(ProfileFields),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(dropdowns.first);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('女').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(dropdowns.last);
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('上海 / Asia/Shanghai').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    expect(store.displayName, '新名字');
    expect(store.birthYear, 2001);
    expect(store.gender, 'female');
    expect(store.timezone, 'Asia/Shanghai');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile avatar changes and AI consent can be enabled and revoked', (tester) async {
    await pumpMock(tester, const Size(390, 844));
    await openMobileProfile(tester);
    final store = storeFor(tester);
    expect(store.avatarGlyph, '遥');
    expect(store.allowProfileForAi, isFalse);
    final avatarButton = find.descendant(
      of: find.byType(MobileProfileView),
      matching: find.text('更换头像'),
    );
    await tester.scrollUntilVisible(
      avatarButton.first,
      220,
      scrollable: find
          .descendant(of: find.byType(MobileProfileView), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(avatarButton.first);
    await tester.pumpAndSettle();
    expect(store.avatarGlyph, '花');
    expect(find.text('头像已更新'), findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(store.allowProfileForAi, isTrue);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(store.allowProfileForAi, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop profile uses a separate view and retains edits across resize', (
    tester,
  ) async {
    await pumpMock(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(TextButton, '我的').first);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsView), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(DesktopSettingsView), matching: find.text('小遥')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopProfileView), findsOneWidget);
    expect(find.byType(MobileProfileView), findsNothing);
    expect(find.byType(ProfileFields), findsOneWidget);
    expect(find.byType(ProfileAvatarPrivacy), findsOneWidget);
    final store = storeFor(tester);
    final nameField = find
        .descendant(of: find.byType(ProfileFields), matching: find.byType(TextField))
        .first;
    await tester.enterText(nameField, '桌面编辑');
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(store.displayName, '桌面编辑');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MobileProfileView), findsOneWidget);
    expect(find.byType(DesktopProfileView), findsNothing);
    expect(find.text('你好，桌面编辑。'), findsOneWidget);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopProfileView), findsOneWidget);
    expect(store.displayName, '桌面编辑');
    expect(tester.takeException(), isNull);
  });
}

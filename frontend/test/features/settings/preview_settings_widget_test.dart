import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/motion.dart';

import '../../support/preview_test_app.dart';

import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/profile_page.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';

void main() {
  Future<PreviewFixtureStore> launch(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildTestPreviewApp());
    await tester.pumpAndSettle();
    return PreviewStoreScope.of(tester.element(find.byType(PreviewPageFrame).first));
  }

  Future<void> openMobile(WidgetTester tester, String title) async {
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(of: find.byType(MobileSettingsView), matching: find.byType(Scrollable))
        .first;
    final row = find.widgetWithText(ListTile, title);
    await tester.scrollUntilVisible(row, 220, scrollable: scrollable);
    final position = tester.getCenter(row).dy;
    if (position > 680) {
      await tester.drag(scrollable, Offset(0, 600 - position));
      await tester.pumpAndSettle();
    }
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsDetail), findsOneWidget);
  }

  testWidgets('language drafts save independently and appearance can turn motion off', (
    tester,
  ) async {
    final store = await launch(tester, const Size(390, 844));
    await openMobile(tester, '语言选项');
    final selects = find.descendant(
      of: find.byType(MobileSettingsDetail),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(selects.at(1));
    await tester.tap(selects.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英语').last);
    await tester.pumpAndSettle();
    expect(store.explanationLanguage, 'zh-Hans');
    await tester.ensureVisible(find.text('保存语言选项'));
    await tester.tap(find.text('保存语言选项'));
    await tester.pumpAndSettle();
    expect(store.explanationLanguage, 'en');
    expect(store.activeLanguage, 'ja');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(ListTile, '外观设置'), 220);
    await tester.tap(find.widgetWithText(ListTile, '外观设置'));
    await tester.pumpAndSettle();
    final motion = find.byType(SwitchListTile);
    await tester.ensureVisible(motion);
    await tester.tap(motion);
    await tester.pumpAndSettle();
    expect(store.reducedMotion, isTrue);
    await tester.tap(motion);
    await tester.pumpAndSettle();
    expect(store.reducedMotion, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query preset remains a draft across resize until saved', (tester) async {
    final store = await launch(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(ListTile, store.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查询与上下文'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsDetail), findsOneWidget);
    await tester.tap(find.text('20000'));
    await tester.pumpAndSettle();
    expect(store.queryContextBudget, 10000);
    expect(store.settingsDraft.queryContextBudget, 20000);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsDetail), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '20000');
    await tester.ensureVisible(find.text('保存查询偏好'));
    await tester.tap(find.text('保存查询偏好'));
    await tester.pumpAndSettle();
    expect(store.queryContextBudget, 20000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cache limits require save and clearing keeps saved results', (tester) async {
    final store = await launch(tester, const Size(390, 844));
    final cache = PreviewSettingsCacheScope.of(tester.element(find.byType(PreviewPageFrame).first));
    store.runQuery('そっと');
    await tester.pumpAndSettle();
    await openMobile(tester, '本机缓存');
    expect(cache.usage!.textEntries, 0);
    expect(cache.usage!.audioAssets, 0);
    expect(find.text('0 份解释 · 0 段音频'), findsOneWidget);
    expect(find.text('1 份解释 · 0 段音频'), findsOneWidget);
    final selects = find.descendant(
      of: find.byType(MobileSettingsDetail),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(selects.first);
    await tester.tap(selects.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('250 MB').last);
    await tester.pumpAndSettle();
    expect(store.textLimitMb, 100);
    expect(cache.usage!.textQuotaBytes, 100000000);
    await tester.ensureVisible(find.text('保存本机上限'));
    await tester.tap(find.text('保存本机上限'));
    await tester.pumpAndSettle();
    expect(store.textLimitMb, 250);
    expect(cache.usage!.textQuotaBytes, 250000000);
    await tester.ensureVisible(find.text('清除此账号本机缓存'));
    await tester.tap(find.text('清除此账号本机缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(cache.lastClear, isNull);
    expect(store.localExplanationCount, 1);
    await tester.tap(find.text('清除此账号本机缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();
    expect(store.localExplanationCount, 0);
    expect(store.savedExplanationCount, 1);
    expect(cache.lastClear?.pendingAudio, 0);
    expect(cache.usage!.textQuotaBytes, 250000000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile and level selections save API enum values with group revisions', (
    tester,
  ) async {
    await launch(tester, const Size(390, 844));
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(MobileSettingsView), matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    final settings = SettingsRepositoryScope.of(tester.element(find.byType(ProfileFields)));
    var revision = settings.snapshot(SettingsGroup.profile)!.revision;
    for (final (label, code) in [('自我描述', 'self_described'), ('不愿说明', 'prefer_not_to_say')]) {
      final gender = find
          .descendant(
            of: find.byType(ProfileFields),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .first;
      final profileScroll = find
          .descendant(of: find.byType(MobileProfileView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(gender, -200, scrollable: profileScroll);
      await tester.tap(gender);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      if (code == 'self_described') {
        final description = find
            .descendant(of: find.byType(ProfileFields), matching: find.byType(TextField))
            .last;
        await tester.enterText(description, '个人描述');
      }
      await tester.scrollUntilVisible(find.text('保存资料'), 200, scrollable: profileScroll);
      await tester.tap(find.text('保存资料'));
      await tester.pumpAndSettle();
      expect(settings.snapshot(SettingsGroup.profile)?.fields['gender_code'], code);
      expect(settings.snapshot(SettingsGroup.profile)?.revision, ++revision);
    }
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openMobile(tester, '语言选项');
    revision = settings.snapshot(SettingsGroup.studyProfile)!.revision;
    for (final (label, code) in [('未填写', 'unknown'), ('初级', 'elementary')]) {
      final level = find
          .descendant(
            of: find.byType(MobileSettingsDetail),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .last;
      final scrollable = find
          .descendant(of: find.byType(MobileSettingsDetail), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(level, 180, scrollable: scrollable);
      final center = tester.getCenter(level).dy;
      if (center > 740) {
        await tester.drag(scrollable, Offset(0, 650 - center));
        await tester.pumpAndSettle();
      }
      await tester.tap(level);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存语言选项'));
      await tester.tap(find.text('保存语言选项'));
      await tester.pumpAndSettle();
      final targets =
          (settings.snapshot(SettingsGroup.studyProfile)!.fields['target_languages'] as List)
              .cast<Map<String, Object?>>();
      expect(targets.firstWhere((row) => row['language_tag'] == 'ja')['self_assessed_level'], code);
      expect(settings.snapshot(SettingsGroup.studyProfile)?.revision, ++revision);
    }
    final activeLanguage = find.byKey(const ValueKey('当前学习语言:ja'));
    await tester.ensureVisible(activeLanguage);
    await tester.tap(activeLanguage);
    await tester.pumpAndSettle();
    await tester.tap(find.text('英语').last);
    await tester.pumpAndSettle();
    final readingGoal = find.widgetWithText(CheckboxListTile, '阅读');
    await tester.ensureVisible(readingGoal);
    expect(tester.widget<CheckboxListTile>(readingGoal).value, isFalse);
    await tester.tap(readingGoal);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存学习目标'));
    await tester.tap(find.text('保存学习目标'));
    await tester.pumpAndSettle();
    final savedStudy = settings.snapshot(SettingsGroup.studyProfile)!;
    final targets = (savedStudy.fields['target_languages'] as List).cast<Map<String, Object?>>();
    expect(
      targets.firstWhere((row) => row['language_tag'] == 'en')['learning_goals'],
      contains('reading'),
    );
    expect(
      targets.firstWhere((row) => row['language_tag'] == 'ja')['learning_goals'],
      contains('exam'),
    );
    expect(savedStudy.fields['active_target_language'], 'en');
    expect(savedStudy.revision, ++revision);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new settings dialogs immediately follow theme and reduced motion', (tester) async {
    final store = await launch(tester, const Size(390, 844));
    await openMobile(tester, '本机缓存');
    final clear = find.text('清除此账号本机缓存');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    final firstRoute = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
    expect(firstRoute.transitionDuration, HarukaMotion.dialogEnter);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    store.updateAppearance('dark', true);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    final dialogContext = tester.element(find.byType(AlertDialog));
    final nextRoute = ModalRoute.of(dialogContext)!;
    expect(Theme.of(dialogContext).brightness, Brightness.dark);
    expect(nextRoute.transitionDuration, Duration.zero);
    expect(nextRoute.reverseTransitionDuration, Duration.zero);
    expect(firstRoute.reverseTransitionDuration, HarukaMotion.exit);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model key stays in memory and speech changes only after save', (tester) async {
    final store = await launch(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(ListTile, store.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置 API Key'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'local-key',
    );
    await tester.tap(find.text('保存 API Key'));
    await tester.pumpAndSettle();
    expect(store.hasPersonalApiKey, isTrue);
    await tester.tap(find.widgetWithText(TextButton, '朗读与声音'));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopSettingsDetail), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(110, 0));
    await tester.pumpAndSettle();
    expect(store.speechSpeed, 1);
    expect(store.settingsDraft.speechSpeed, greaterThan(1));
    await tester.tap(find.text('保存朗读偏好'));
    await tester.pumpAndSettle();
    expect(store.speechSpeed, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection validates address and security password dialog records success', (
    tester,
  ) async {
    final store = await launch(tester, const Size(1440, 900));
    await tester.tap(find.widgetWithText(ListTile, store.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务连接'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://example.com');
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 HTTPS 地址'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(store.serviceAddressValidated, isTrue);
    expect(store.serviceAddress, 'https://example.com');
    await tester.tap(find.widgetWithText(TextButton, '安全与账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '修改密码'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'current-pass');
    await tester.enterText(fields.at(1), 'new-password');
    await tester.enterText(fields.at(2), 'different');
    await tester.tap(find.widgetWithText(FilledButton, '修改密码'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    await tester.enterText(fields.at(2), 'new-password');
    await tester.tap(find.widgetWithText(FilledButton, '修改密码'));
    await tester.pumpAndSettle();
    expect(store.passwordChangeCount, 1);
    expect(tester.takeException(), isNull);
  });
}

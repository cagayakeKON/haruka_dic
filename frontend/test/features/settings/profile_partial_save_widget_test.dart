import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_app.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/data/http_settings_source.dart';
import 'package:haruka/features/settings/presentation/profile_page.dart';
import 'package:haruka/features/settings/presentation/settings_pages.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_form_draft.dart';
import 'package:mockito/mockito.dart';

import 'cached_settings_repository_test.mocks.dart';

Widget injectedSettingsApp(MockSettingsSource source) => PreviewHarukaApp(
  settingsSource: source,
  settingsCacheAdapter: PreviewSettingsCacheAdapter(
    coordinator: CacheCoordinator(
      openBackend: (_) async {
        final executor = NativeDatabase.memory();
        return OpenedCacheBackend(
          executor: executor,
          mode: CacheStorageMode.memoryOnly,
          closeOwner: executor.close,
        );
      },
    ),
  ),
);

Future<void> tapVisibleText(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  provideDummy<SettingsSnapshot>(
    SettingsSnapshot(group: SettingsGroup.profile, revision: 1, fields: const {}),
  );

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('appearance switch submits system and stays off at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = MockSettingsSource();
      var preferences = SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: const {'theme_mode': 'light', 'reduce_motion': 'on'},
      );
      when(source.fetch(any, any)).thenAnswer((invocation) async {
        final group = invocation.positionalArguments.first as SettingsGroup;
        return group == SettingsGroup.preferences
            ? preferences
            : SettingsSnapshot(group: group, revision: 1, fields: const {});
      });
      final submitted = <SettingsPatch>[];
      when(source.patch(any, any)).thenAnswer((invocation) async {
        final patch = invocation.positionalArguments[1] as SettingsPatch;
        submitted.add(patch);
        preferences = SettingsSnapshot(
          group: SettingsGroup.preferences,
          revision: patch.expectedRevision + 1,
          fields: {...preferences.fields, ...patch.fields},
        );
        return preferences;
      });
      await tester.pumpWidget(injectedSettingsApp(source));
      await tester.pumpAndSettle();
      if (size.width < 600) {
        await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
        await tester.pumpAndSettle();
        final appearance = find.widgetWithText(ListTile, '外观设置');
        await tester.ensureVisible(appearance);
        await tester.tap(appearance);
      } else {
        await tester.tap(find.text('我的').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('外观设置').first);
      }
      await tester.pumpAndSettle();
      final switchTile = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
      await tester.tap(switchTile);
      await tester.pumpAndSettle();
      expect(submitted, hasLength(1));
      expect(submitted.single.fields['reduce_motion'], 'system');
      expect(
        settingsPatchBody(SettingsGroup.preferences, submitted.single)['fields'],
        containsPair('reduce_motion', 'system'),
      );
      expect(preferences.fields['reduce_motion'], 'system');
      expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile confirmation followed by timezone failure reports partial save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = MockSettingsSource();
    final records = <SettingsGroup, SettingsSnapshot>{
      SettingsGroup.profile: SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {
          'display_name': '原名',
          'birth_year': null,
          'gender_code': 'unspecified',
          'use_optional_demographics_for_ai': false,
        },
      ),
      SettingsGroup.studyProfile: SettingsSnapshot(
        group: SettingsGroup.studyProfile,
        revision: 1,
        fields: {
          'native_languages': <String>['zh-Hans'],
          'target_languages': <Map<String, Object?>>[],
          'active_target_language': '',
          'explanation_language': 'zh-Hans',
        },
      ),
      SettingsGroup.preferences: SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: {'timezone': 'Asia/Tokyo'},
      ),
    };
    when(source.fetch(any, any)).thenAnswer((invocation) async {
      return records[invocation.positionalArguments.first as SettingsGroup]!;
    });
    when(source.patch(any, any)).thenAnswer((invocation) async {
      final group = invocation.positionalArguments.first as SettingsGroup;
      final patch = invocation.positionalArguments[1] as SettingsPatch;
      if (group == SettingsGroup.preferences) throw StateError('timezone rejected');
      records[group] = SettingsSnapshot(
        group: group,
        revision: patch.expectedRevision + 1,
        fields: {...records[group]!.fields, ...patch.fields},
      );
      return records[group]!;
    });
    await tester.pumpWidget(injectedSettingsApp(source));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    final profile = find
        .descendant(of: find.byType(MobileSettingsView), matching: find.byType(ListTile))
        .first;
    await tester.tap(profile);
    await tester.pumpAndSettle();
    expect(find.byType(MobileProfileView), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(ProfileFields),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '原名  ');
    await tester.enterText(fields.at(1), '无效年份');
    await tapVisibleText(tester, '保存资料');
    expect(find.text('请输入有效的出生年份'), findsOneWidget);
    verifyNever(source.patch(any, any));
    await tester.enterText(fields.at(1), '');
    await tester.enterText(fields.first, '新名字  ');
    final timezone = find.byKey(const ValueKey('profile-timezone:Asia/Tokyo'));
    await tester.ensureVisible(timezone);
    await tester.tap(timezone);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTC').last);
    await tester.pumpAndSettle();
    await tapVisibleText(tester, '保存资料');

    expect(records[SettingsGroup.profile]!.fields['display_name'], '新名字');
    expect(records[SettingsGroup.preferences]!.fields['timezone'], 'Asia/Tokyo');
    expect(find.text('个人资料已保存，时区未保存，请重试'), findsOneWidget);
    await tapVisibleText(tester, '保存资料');
    verify(source.patch(SettingsGroup.profile, any)).called(1);
    verify(source.patch(SettingsGroup.preferences, any)).called(2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail forms use injected scoped snapshots and allow no target language', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = MockSettingsSource();
    final records = <SettingsGroup, SettingsSnapshot>{
      SettingsGroup.profile: SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {'display_name': '异源姓名'},
      ),
      SettingsGroup.studyProfile: SettingsSnapshot(
        group: SettingsGroup.studyProfile,
        revision: 1,
        fields: {
          'native_languages': <String>['en'],
          'target_languages': <Map<String, Object?>>[],
          'active_target_language': '',
          'explanation_language': 'en',
        },
      ),
      SettingsGroup.preferences: SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: {'query_context_budget_tokens': 23000, 'timezone': 'UTC'},
      ),
    };
    when(source.fetch(any, any)).thenAnswer(
      (invocation) async => records[invocation.positionalArguments.first as SettingsGroup]!,
    );
    when(source.patch(any, any)).thenAnswer((invocation) async {
      final group = invocation.positionalArguments.first as SettingsGroup;
      final patch = invocation.positionalArguments[1] as SettingsPatch;
      records[group] = SettingsSnapshot(
        group: group,
        revision: patch.expectedRevision + 1,
        fields: {...records[group]!.fields, ...patch.fields},
      );
      return records[group]!;
    });
    await tester.pumpWidget(injectedSettingsApp(source));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    expect(find.text('异源姓名'), findsOneWidget);
    final scrollable = find
        .descendant(of: find.byType(MobileSettingsView), matching: find.byType(Scrollable))
        .first;
    final language = find.widgetWithText(ListTile, '语言选项');
    await tester.scrollUntilVisible(language, 180, scrollable: scrollable);
    await tester.tap(language);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsDetail), findsOneWidget);
    expect(tester.takeException(), isNull);
    final targetEnglish = find.widgetWithText(CheckboxListTile, '英语').last;
    await tester.ensureVisible(targetEnglish);
    await tester.tap(targetEnglish);
    await tester.pumpAndSettle();
    final readingGoal = find.widgetWithText(CheckboxListTile, '阅读');
    await tester.ensureVisible(readingGoal);
    await tester.tap(readingGoal);
    await tester.pumpAndSettle();
    await tapVisibleText(tester, '保存学习目标');
    final targets = (records[SettingsGroup.studyProfile]!.fields['target_languages'] as List)
        .cast<Map<String, Object?>>();
    expect(targets.single['language_tag'], 'en');
    expect(targets.single['learning_goals'], contains('reading'));
    expect(records[SettingsGroup.studyProfile]!.fields['active_target_language'], 'en');
    expect(records[SettingsGroup.studyProfile]!.revision, 2);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final query = find.widgetWithText(ListTile, '查询与上下文');
    await tester.scrollUntilVisible(query, 180, scrollable: scrollable);
    await tester.tap(query);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '23000');
    await tapVisibleText(tester, '保存查询偏好');
    expect(records[SettingsGroup.preferences]?.fields['query_context_budget_tokens'], 23000);
    expect(records[SettingsGroup.preferences]?.revision, 2);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final repository = SettingsRepositoryScope.of(
      tester.element(find.byType(MobileSettingsDetail)),
    );
    records[SettingsGroup.preferences] = SettingsSnapshot(
      group: SettingsGroup.preferences,
      revision: 3,
      fields: {'query_context_budget_tokens': 32000, 'timezone': 'UTC'},
    );
    await repository.refresh(SettingsGroup.preferences, force: true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '32000');
    await tester.enterText(find.byType(TextField), '27000');
    records[SettingsGroup.preferences] = SettingsSnapshot(
      group: SettingsGroup.preferences,
      revision: 4,
      fields: {'query_context_budget_tokens': 40000, 'timezone': 'UTC'},
    );
    await repository.refresh(SettingsGroup.preferences, force: true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '27000');
    expect(repository.snapshot(SettingsGroup.preferences)?.revision, 4);
    expect(
      settingsFormDraftHasConflict(
        PreviewStoreScope.of(tester.element(find.byType(MobileSettingsDetail))),
        SettingsGroup.preferences,
      ),
      isTrue,
    );
    await tapVisibleText(tester, '保存查询偏好');
    expect(
      find.text('内容已更新，请重新加载'),
      findsOneWidget,
      reason:
          'visible snackbars: ${tester.widgetList<SnackBar>(find.byType(SnackBar)).map((bar) => (bar.content as Text).data).toList()}',
    );
    verify(source.patch(SettingsGroup.preferences, any)).called(1);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '27000');
    await tapVisibleText(tester, '保存查询偏好');
    expect(records[SettingsGroup.preferences]?.fields['query_context_budget_tokens'], 27000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile revision keeps a conflicting name draft through reload', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = MockSettingsSource();
    final records = <SettingsGroup, SettingsSnapshot>{
      SettingsGroup.profile: SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {'display_name': '原名', 'birth_year': null, 'gender_code': 'unspecified'},
      ),
      SettingsGroup.preferences: SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: {'timezone': 'Asia/Tokyo'},
      ),
    };
    when(source.fetch(any, any)).thenAnswer(
      (invocation) async => records[invocation.positionalArguments.first as SettingsGroup]!,
    );
    when(source.patch(any, any)).thenAnswer((invocation) async {
      final group = invocation.positionalArguments.first as SettingsGroup;
      final patch = invocation.positionalArguments[1] as SettingsPatch;
      records[group] = SettingsSnapshot(
        group: group,
        revision: patch.expectedRevision + 1,
        fields: {...records[group]!.fields, ...patch.fields},
      );
      return records[group]!;
    });
    await tester.pumpWidget(injectedSettingsApp(source));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(MobileSettingsView), matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    final profile = find.byType(ProfileFields);
    final repository = SettingsRepositoryScope.of(tester.element(profile));
    final name = find.descendant(of: profile, matching: find.byType(TextField)).first;
    await tester.enterText(name, '本地草稿');
    records[SettingsGroup.profile] = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 2,
      fields: {'display_name': '远端姓名', 'birth_year': null, 'gender_code': 'unspecified'},
    );
    records[SettingsGroup.preferences] = SettingsSnapshot(
      group: SettingsGroup.preferences,
      revision: 2,
      fields: {'timezone': 'UTC'},
    );
    await repository.refresh(SettingsGroup.profile, force: true);
    await repository.refresh(SettingsGroup.preferences, force: true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller?.text, '本地草稿');
    expect(find.byKey(const ValueKey('profile-timezone:UTC')), findsOneWidget);
    await tapVisibleText(tester, '保存资料');
    expect(find.text('内容已更新，请重新加载'), findsOneWidget);
    verifyNever(source.patch(any, any));
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller?.text, '本地草稿');
    final timezone = find.byKey(const ValueKey('profile-timezone:UTC'));
    await tester.ensureVisible(timezone);
    await tester.tap(timezone);
    await tester.pumpAndSettle();
    await tester.tap(find.text('东京 / Asia/Tokyo').last);
    await tester.pumpAndSettle();
    await tapVisibleText(tester, '保存资料');
    verify(source.patch(SettingsGroup.profile, any)).called(1);
    verify(source.patch(SettingsGroup.preferences, any)).called(1);
    await tester.enterText(name, '确认后的姓名');
    await tapVisibleText(tester, '保存资料');
    verify(source.patch(SettingsGroup.profile, any)).called(1);
    when(source.patch(SettingsGroup.profile, any)).thenAnswer((_) async {
      records[SettingsGroup.profile] = SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: records[SettingsGroup.profile]!.revision + 1,
        fields: {'display_name': '另一端姓名', 'birth_year': null, 'gender_code': 'unspecified'},
      );
      throw const SettingsRevisionConflict();
    });
    await tester.enterText(name, '冲突草稿');
    await tapVisibleText(tester, '保存资料');
    expect(find.text('内容已更新，请重新加载'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller?.text, '冲突草稿');
    expect(repository.snapshot(SettingsGroup.profile)?.fields['display_name'], '另一端姓名');
    expect(tester.takeException(), isNull);
  });
}

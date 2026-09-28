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

void main() {
  provideDummy<SettingsSnapshot>(
    SettingsSnapshot(group: SettingsGroup.profile, revision: 1, fields: const {}),
  );

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
    await tester.ensureVisible(find.text('保存资料'));
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的出生年份'), findsOneWidget);
    verifyNever(source.patch(any, any));
    await tester.enterText(fields.at(1), '');
    await tester.enterText(fields.first, '新名字  ');
    final selects = find.descendant(
      of: find.byType(ProfileFields),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(selects.at(1));
    await tester.tap(selects.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTC').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存资料'));
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    expect(records[SettingsGroup.profile]!.fields['display_name'], '新名字');
    expect(records[SettingsGroup.preferences]!.fields['timezone'], 'Asia/Tokyo');
    expect(find.text('个人资料已保存，时区未保存，请重试'), findsOneWidget);
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('保存学习目标'));
    await tester.tap(find.text('保存学习目标'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('保存查询偏好'));
    await tester.tap(find.text('保存查询偏好'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('保存查询偏好'));
    await tester.pumpAndSettle();
    expect(
      find.text('内容已更新，请重新加载'),
      findsOneWidget,
      reason:
          'visible snackbars: ${tester.widgetList<SnackBar>(find.byType(SnackBar)).map((bar) => (bar.content as Text).data).toList()}',
    );
    verify(source.patch(SettingsGroup.preferences, any)).called(1);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '40000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile revision merges clean timezone and blocks conflicting name until reload', (
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
    await tester.ensureVisible(find.text('保存资料'));
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('内容已更新，请重新加载'), findsOneWidget);
    verifyNever(source.patch(any, any));
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller?.text, '远端姓名');
    final timezone = find.byKey(const ValueKey('profile-timezone:UTC'));
    await tester.ensureVisible(timezone);
    await tester.tap(timezone);
    await tester.pumpAndSettle();
    await tester.tap(find.text('东京 / Asia/Tokyo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    verifyNever(source.patch(SettingsGroup.profile, any));
    verify(source.patch(SettingsGroup.preferences, any)).called(1);
    await tester.enterText(name, '确认后的姓名');
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('内容已更新，请重新加载'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller?.text, '冲突草稿');
    expect(repository.snapshot(SettingsGroup.profile)?.fields['display_name'], '另一端姓名');
    expect(tester.takeException(), isNull);
  });
}

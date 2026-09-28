import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/settings/domain/profile_guide.dart';
import 'package:haruka/features/settings/data/language_capabilities.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/profile_guide_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  final emptyProfile = SettingsSnapshot(
    group: SettingsGroup.profile,
    revision: 1,
    fields: const {},
  );
  final emptyStudy = SettingsSnapshot(
    group: SettingsGroup.studyProfile,
    revision: 1,
    fields: const {},
  );
  final emptyPreferences = SettingsSnapshot(
    group: SettingsGroup.preferences,
    revision: 1,
    fields: const {},
  );
  test('incomplete when any server completeness flag is missing', () {
    expect(
      profileGuideIncomplete({
        'display_name': true,
        'explanation_language': true,
        'target_language': false,
        'timezone': true,
      }),
      isTrue,
    );
    expect(profileGuideIncomplete(null), isTrue);
    expect(
      profileGuideIncomplete({
        'display_name': true,
        'explanation_language': true,
        'target_language': true,
        'timezone': true,
      }),
      isFalse,
    );
  });

  test('guide patches include only fields the user chose', () {
    expect(profileGuidePatches(const ProfileGuideInput()), isEmpty);
    final patches = profileGuidePatches(
      const ProfileGuideInput(
        displayName: ' 遥 ',
        explanationLanguage: 'zh-Hans',
        targetLanguage: 'ja',
        timezone: 'Asia/Tokyo',
      ),
    );
    expect(patches[SettingsGroup.profile], {'display_name': '遥'});
    expect(patches[SettingsGroup.studyProfile]?['explanation_language'], 'zh-Hans');
    expect(patches[SettingsGroup.studyProfile]?['active_target_language'], 'ja');
    expect(patches[SettingsGroup.preferences], {'timezone': 'Asia/Tokyo'});
    expect(patches.containsKey(SettingsGroup.profile), isTrue);
  });

  test('guide fills a missing name without overwriting existing languages or goals', () {
    final profile = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 3,
      fields: const {'display_name': null},
    );
    final study = SettingsSnapshot(
      group: SettingsGroup.studyProfile,
      revision: 4,
      fields: const {
        'native_languages': ['zh-Hans', 'en'],
        'explanation_language': 'zh-Hans',
        'active_target_language': 'ja',
        'target_languages': [
          {
            'language_tag': 'ja',
            'self_assessed_level': 'advanced',
            'learning_goals': ['conversation'],
          },
          {
            'language_tag': 'en',
            'self_assessed_level': 'intermediate',
            'learning_goals': ['reading'],
          },
        ],
      },
    );
    final preferences = SettingsSnapshot(
      group: SettingsGroup.preferences,
      revision: 2,
      fields: const {'timezone': 'Europe/Berlin'},
    );
    final patches = profileGuidePatches(
      const ProfileGuideInput(
        displayName: '遥',
        nativeLanguage: 'zh-Hans',
        explanationLanguage: 'zh-Hans',
        targetLanguage: 'ja',
        timezone: 'Europe/Berlin',
      ),
      profile: profile,
      studyProfile: study,
      preferences: preferences,
    );
    expect(patches, {
      SettingsGroup.profile: {'display_name': '遥'},
    });
  });

  testWidgets('skip leaves without saving', (tester) async {
    var saved = 0;
    var skipped = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: LanguageCapabilitiesScope(
          value: const LanguageCapabilities(version: 1, languages: []),
          failed: false,
          retry: () {},
          child: Scaffold(
            body: ProfileGuidePage(
              onSave: (_) async => saved++,
              onSkip: () => skipped++,
              profile: emptyProfile,
              study: emptyStudy,
              preferences: emptyPreferences,
              canSave: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(saved, 0);
    expect(skipped, 1);
  });

  testWidgets('an empty save does not call the writer', (tester) async {
    var saved = 0;
    var skipped = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: LanguageCapabilitiesScope(
          value: const LanguageCapabilities(version: 1, languages: []),
          failed: false,
          retry: () {},
          child: Scaffold(
            body: ProfileGuidePage(
              onSave: (_) async => saved++,
              onSkip: () => skipped++,
              profile: emptyProfile,
              study: emptyStudy,
              preferences: emptyPreferences,
              canSave: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pump();
    expect(saved, 0);
    expect(skipped, 1);
  });
}

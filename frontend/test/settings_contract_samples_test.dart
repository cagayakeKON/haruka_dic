import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/features/settings/data/http_settings_source.dart';
import 'package:haruka/features/settings/data/language_capabilities.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/avatar_upload.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';

void main() {
  final samples = wireObject(
    jsonDecode(File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync()),
  );

  Map<String, Object?> data(String key) => wireObject(wireObject(samples[key])['data']);

  test('Python profile and study responses keep optional values and revisions', () {
    final emptyProfile = settingsSnapshotFromApi(
      SettingsGroup.profile,
      data('settings_profile_empty'),
    );
    final presentProfile = settingsSnapshotFromApi(
      SettingsGroup.profile,
      data('settings_profile_present'),
    );
    final emptyStudy = settingsSnapshotFromApi(
      SettingsGroup.studyProfile,
      data('settings_study_empty'),
    );
    final presentStudy = settingsSnapshotFromApi(
      SettingsGroup.studyProfile,
      data('settings_study_present'),
    );

    expect(emptyProfile.revision, 1);
    expect(emptyProfile.fields['birth_year'], isNull);
    expect(emptyProfile.fields['avatar_asset_id'], isNull);
    expect(emptyProfile.fields['avatar_revision'], 0);
    expect(presentProfile.revision, 2);
    expect(presentProfile.fields['display_name'], '遥');
    expect(presentProfile.fields['avatar_asset_id'], isA<String>());
    expect(emptyStudy.fields['target_languages'], isEmpty);
    expect(presentStudy.fields['active_target_language'], 'ja');
    expect((presentStudy.fields['target_languages'] as List).single, {
      'language_tag': 'ja',
      'self_assessed_level': 'beginner',
      'learning_goals': ['reading', 'listening'],
    });
  });

  test('Python preference decimals and explicit-null masks survive the Dart adapters', () {
    final empty = settingsSnapshotFromApi(
      SettingsGroup.preferences,
      data('settings_preferences_empty'),
    );
    final present = settingsSnapshotFromApi(
      SettingsGroup.preferences,
      data('settings_preferences_present'),
    );
    expect(empty.fields['reading_font_size'], isNull);
    expect(empty.fields['playback_speed'], 1.0);
    expect(present.fields['reading_font_size'], 18);
    expect(present.fields['reading_line_height'], 1.5);
    expect(present.fields['playback_speed'], 1.25);

    final profilePatch = settingsPatchBody(
      SettingsGroup.profile,
      SettingsPatch(expectedRevision: 2, fields: {'birth_year': null}),
    );
    expect(profilePatch, wireObject(samples['settings_profile_patch_null']));
    expect((profilePatch['fields'] as Map).keys, ['birth_year']);

    final studyPatch = settingsPatchBody(
      SettingsGroup.studyProfile,
      SettingsPatch(
        expectedRevision: 1,
        fields: {
          'native_languages': ['zh-Hans'],
          'explanation_language': 'zh-Hans',
          'active_target_language': 'ja',
          'target_languages': [
            {
              'language_tag': 'ja',
              'self_assessed_level': 'beginner',
              'learning_goals': ['reading', 'listening'],
            },
          ],
        },
      ),
    );
    expect(studyPatch, wireObject(samples['settings_study_patch']));

    final preferencePatch = settingsPatchBody(
      SettingsGroup.preferences,
      SettingsPatch(
        expectedRevision: 1,
        fields: {'timezone': null, 'reading_font_size': 18, 'playback_speed': 1.25},
      ),
    );
    expect(preferencePatch, wireObject(samples['settings_preferences_patch']));
  });

  test('versioned language catalogue and avatar wire shapes match Python samples', () async {
    final languages = LanguageCapabilities.decode(data('settings_language_capabilities'));
    expect(languages.version, 1);
    expect(languages.codes((item) => item.learning), ['ja', 'en']);
    expect(languages.label('zh-Hans'), '简体中文');

    final avatarBytes = Uint8List.fromList((samples['settings_avatar_bytes'] as List).cast<int>());
    expect(avatarIntentBody(avatarBytes), wireObject(samples['settings_avatar_create']));
    expect(
      avatarCompleteBody(expectedRevision: 1, bytes: avatarBytes),
      wireObject(samples['settings_avatar_complete']),
    );
    expect(wireObject(samples['settings_avatar_delete']), {'expected_revision': 2});
    final intent = data('settings_avatar_intent');
    final calls = <String>[];
    await publishAvatarBytes(
      bytes: avatarBytes,
      expectedRevision: 1,
      post: (path, body) async {
        calls.add(path);
        return intent;
      },
    );
    expect(calls, [
      '/api/v1/users/me/avatar-upload-intents',
      '/api/v1/users/me/avatar-upload-intents/${intent['id']}/complete',
    ]);
  });

  test('Python 409 revision detail becomes a draft-preserving conflict', () {
    final error = ApiFailure.fromJson(samples['settings_revision_conflict']);
    expect(error.code, 'REVISION_CONFLICT');
    expect(error.currentRevision, 2);
    expect(translateSettingsError(error), isA<SettingsRevisionConflict>());
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/settings/data/http_settings_source.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';

void main() {
  test('preference decimals become the int and double values the draft expects', () {
    final snapshot = settingsSnapshotFromApi(SettingsGroup.preferences, {
      'revision': 3,
      'ui_locale': 'zh-Hans',
      'timezone': 'Asia/Tokyo',
      'theme_mode': 'system',
      'reduce_motion': 'system',
      'reading_font_family': 'serif',
      'reading_font_size': '18.00',
      'reading_line_height': '1.80',
      'reading_theme': 'light',
      'playback_speed': '1.00',
      'query_context_budget_tokens': 10000,
    });

    expect(snapshot.fields['reading_font_size'], 18);
    expect(snapshot.fields['reading_line_height'], 1.8);
    expect(snapshot.fields['playback_speed'], 1.0);
    expect(snapshot.fields['reading_font_size'], isA<int>());
    expect(snapshot.fields['reading_line_height'], isA<double>());
    expect(snapshot.fields['playback_speed'], isA<double>());
  });

  test('profile completeness and api gender codes stay on the snapshot', () {
    final snapshot = settingsSnapshotFromApi(SettingsGroup.profile, {
      'revision': 1,
      'display_name': '遥',
      'birth_year': null,
      'age_band': null,
      'gender_code': 'unspecified',
      'gender_self_description': null,
      'use_optional_demographics_for_ai': false,
      'avatar_asset_id': null,
      'avatar_revision': 0,
      'profile_completeness': {
        'display_name': true,
        'explanation_language': false,
        'target_language': false,
        'timezone': false,
      },
    });

    expect(snapshot.fields['gender_code'], 'unspecified');
    expect((snapshot.fields['profile_completeness'] as Map)['display_name'], isTrue);
  });

  test('a preference patch keeps playback speed and drops model and voice fields', () {
    final fields = settingsPatchFields(SettingsGroup.preferences, {
      'playback_speed': 1.25,
      'model_provider': 'openrouter',
      'text_model': 'default',
      'vision_model': 'default',
      'tts_model': 'gemini',
      'speech_voice': 'japaneseClear',
      'speech_format': 'wav',
      'speech_style': 'natural',
    });

    expect(fields, {'playback_speed': '1.25'});
  });

  test('a model-only patch does not invent a successful write', () {
    expect(
      () => settingsPatchFields(SettingsGroup.preferences, {
        'model_provider': 'openrouter',
        'text_model': 'default',
      }),
      throwsArgumentError,
    );
  });

  test('nullable reading sizes can be cleared without changing playback speed', () {
    expect(
      settingsPatchFields(SettingsGroup.preferences, {
        'reading_font_size': null,
        'reading_line_height': null,
      }),
      {'reading_font_size': null, 'reading_line_height': null},
    );
    expect(
      () => settingsPatchFields(SettingsGroup.preferences, {'playback_speed': null}),
      throwsFormatException,
    );
  });

  test('study language aliases and an empty active language match the api', () {
    final fields = settingsPatchFields(SettingsGroup.studyProfile, {
      'native_languages': ['zh-Hans'],
      'explanation_language': '',
      'active_target_language': '',
      'target_languages': [
        {
          'language_tag': 'ja',
          'self_assessed_level': 'elementary',
          'learning_goals': ['reading'],
        },
      ],
    });

    expect(fields['explanation_language'], isNull);
    expect(fields['active_target_language'], isNull);
    expect(fields['target_languages'], [
      {
        'language_tag': 'ja',
        'self_assessed_level': 'elementary',
        'learning_goals': ['reading'],
      },
    ]);
  });

  test('profile gender aliases are translated before the request', () {
    final fields = settingsPatchFields(SettingsGroup.profile, {
      'gender_code': 'unset',
      'display_name': '遥',
    });
    expect(fields['gender_code'], 'unspecified');
  });

  test('a revision conflict becomes the draft-preserving settings exception', () {
    final error = translateSettingsError(
      const ApiFailure(code: 'REVISION_CONFLICT', currentRevision: 4),
    );
    expect(error, isA<SettingsRevisionConflict>());
    expect(translateSettingsError(const ApiFailure(code: 'INPUT_INVALID')), isA<ApiFailure>());
  });

  test('profile read and write forward the session guard headers', () async {
    final seen = <Map<String, dynamic>>[];
    final api = ApiClient(
      AppConfig.parse(platform: AppPlatform.windows, environment: 'dev'),
      adapter: _HeaderAdapter(seen),
    );
    final source = HttpSettingsSource(
      api,
      read: <T>(action) => action({'Authorization': 'Bearer secret'}),
      write: <T>(action) => action({'X-CSRF-Token': 'csrf'}),
    );
    await source.fetch(SettingsGroup.profile, CancelToken());
    await source.patch(
      SettingsGroup.profile,
      SettingsPatch(expectedRevision: 1, fields: {'display_name': '遥'}),
    );
    expect(seen, hasLength(2));
    expect(seen[0].keys.map((key) => key.toString().toLowerCase()), contains('authorization'));
    expect(seen[1].keys.map((key) => key.toString().toLowerCase()), contains('x-csrf-token'));
    api.close();
  });
}

final class _HeaderAdapter implements HttpClientAdapter {
  _HeaderAdapter(this.seen);
  final List<Map<String, dynamic>> seen;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.headers);
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'revision': options.method == 'PATCH' ? 2 : 1,
          'display_name': '遥',
          'birth_year': null,
          'age_band': null,
          'gender_code': 'unspecified',
          'gender_self_description': null,
          'use_optional_demographics_for_ai': false,
          'avatar_asset_id': null,
          'avatar_revision': 0,
          'profile_completeness': {
            'display_name': true,
            'explanation_language': false,
            'target_language': false,
            'timezone': false,
          },
        },
        'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

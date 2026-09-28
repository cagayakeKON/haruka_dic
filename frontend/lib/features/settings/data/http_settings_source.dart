import 'package:dio/dio.dart';

import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';

import '../domain/settings_snapshot.dart';
import 'settings_source.dart';

const _genderToApi = {
  'unset': 'unspecified',
  'self_describe': 'self_described',
  'prefer_not': 'prefer_not_to_say',
};

const _profileFields = {
  'display_name',
  'birth_year',
  'gender_code',
  'gender_self_description',
  'use_optional_demographics_for_ai',
};

const _studyFields = {
  'native_languages',
  'explanation_language',
  'active_target_language',
  'target_languages',
};

const _preferenceFields = {
  'timezone',
  'theme_mode',
  'reduce_motion',
  'reading_font_family',
  'reading_font_size',
  'reading_line_height',
  'reading_theme',
  'playback_speed',
  'query_context_budget_tokens',
};

const _decimalFields = {'reading_font_size', 'reading_line_height', 'playback_speed'};

String settingsResourcePath(SettingsGroup group) => switch (group) {
  SettingsGroup.profile => '/api/v1/users/me/profile',
  SettingsGroup.studyProfile => '/api/v1/users/me/study-profile',
  SettingsGroup.preferences => '/api/v1/users/me/settings',
};

/// Turns a revision conflict into the settings-page exception and leaves every
/// other failure unchanged for the page's existing error snackbar.
Object translateSettingsError(Object error) =>
    error is ApiFailure && error.code == 'REVISION_CONFLICT'
    ? const SettingsRevisionConflict()
    : error;

SettingsSnapshot settingsSnapshotFromApi(SettingsGroup group, Object? data) {
  final json = _object(data);
  final revision = json['revision'];
  if (revision is! int || revision < 1) {
    throw const FormatException('settings revision');
  }
  return SettingsSnapshot(group: group, revision: revision, fields: _snapshotFields(group, json));
}

Map<String, Object?> settingsPatchBody(SettingsGroup group, SettingsPatch patch) => {
  'expected_revision': patch.expectedRevision,
  'fields': settingsPatchFields(group, patch.fields),
};

/// Keeps only the fields this slice's endpoints accept. Model and voice keys
/// belong to a later slice; an empty mask is rejected instead of pretending
/// the revision advanced.
Map<String, Object?> settingsPatchFields(SettingsGroup group, Map<String, Object?> fields) {
  final allowed = switch (group) {
    SettingsGroup.profile => _profileFields,
    SettingsGroup.studyProfile => _studyFields,
    SettingsGroup.preferences => _preferenceFields,
  };
  final next = <String, Object?>{};
  for (final entry in fields.entries) {
    if (!allowed.contains(entry.key)) continue;
    next[entry.key] = _wireValue(group, entry.key, entry.value);
  }
  if (next.isEmpty) {
    throw ArgumentError.value(fields, 'fields', 'field mask is empty');
  }
  return next;
}

final class HttpSettingsSource implements SettingsSource {
  HttpSettingsSource(this.api, {this.read, this.write});

  final ApiClient api;
  final Future<T> Function<T>(Future<T> Function(Map<String, String> headers) action)? read;
  final Future<T> Function<T>(Future<T> Function(Map<String, String> headers) action)? write;

  @override
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel) {
    return _guard(read, (headers) async {
      try {
        final response = await api.getJson(
          settingsResourcePath(group),
          (data) => settingsSnapshotFromApi(group, data),
          cancelToken: cancel,
          headers: headers,
        );
        return response.data;
      } on ApiFailure catch (error) {
        throw translateSettingsError(error);
      }
    });
  }

  @override
  Future<SettingsSnapshot> patch(SettingsGroup group, SettingsPatch patch) {
    return _guard(write, (headers) async {
      try {
        final response = await api.patchJson(
          settingsResourcePath(group),
          settingsPatchBody(group, patch),
          (data) => settingsSnapshotFromApi(group, data),
          headers: headers,
        );
        return response.data;
      } on ApiFailure catch (error) {
        throw translateSettingsError(error);
      }
    });
  }
}

Future<T> _guard<T>(
  Future<R> Function<R>(Future<R> Function(Map<String, String> headers) action)? guard,
  Future<T> Function(Map<String, String> headers) action,
) {
  final protected = guard;
  if (protected == null) return action(const {});
  return protected(action);
}

Map<String, Object?> _snapshotFields(SettingsGroup group, Map<String, Object?> json) =>
    switch (group) {
      SettingsGroup.profile => {
        'display_name': json['display_name'],
        'birth_year': json['birth_year'],
        'age_band': json['age_band'],
        'gender_code': json['gender_code'],
        'gender_self_description': json['gender_self_description'],
        'use_optional_demographics_for_ai': json['use_optional_demographics_for_ai'],
        'avatar_asset_id': json['avatar_asset_id'],
        'avatar_revision': json['avatar_revision'],
        'profile_completeness': _object(json['profile_completeness']),
      },
      SettingsGroup.studyProfile => {
        'native_languages': _stringList(json['native_languages']),
        'explanation_language': json['explanation_language'],
        'active_target_language': json['active_target_language'],
        'target_languages': [for (final row in _list(json['target_languages'])) _targetRow(row)],
      },
      SettingsGroup.preferences => {
        'ui_locale': json['ui_locale'],
        'timezone': json['timezone'],
        'theme_mode': json['theme_mode'],
        'reduce_motion': json['reduce_motion'],
        'reading_font_family': json['reading_font_family'],
        'reading_font_size': _wholeDecimal(json['reading_font_size']),
        'reading_line_height': _decimal(json['reading_line_height']),
        'reading_theme': json['reading_theme'],
        'playback_speed': _requiredDecimal(json['playback_speed']),
        'query_context_budget_tokens': json['query_context_budget_tokens'],
      },
    };

Object? _wireValue(SettingsGroup group, String key, Object? value) {
  if (group == SettingsGroup.profile && key == 'gender_code' && value is String) {
    return _genderToApi[value] ?? value;
  }
  if (group == SettingsGroup.studyProfile &&
      (key == 'active_target_language' || key == 'explanation_language')) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }
  if (group == SettingsGroup.studyProfile && key == 'target_languages') {
    return [for (final row in _list(value)) _targetInput(row)];
  }
  if (_decimalFields.contains(key)) {
    if (value == null && key != 'playback_speed') return null;
    return _decimalText(value);
  }
  return value;
}

Map<String, Object?> _targetRow(Object? value) {
  final row = _object(value);
  return {
    'language_tag': row['language_tag'],
    'self_assessed_level': row['self_assessed_level'],
    'learning_goals': _stringList(row['learning_goals']),
  };
}

Map<String, Object?> _targetInput(Object? value) {
  final row = _object(value);
  return {
    'language_tag': row['language_tag'],
    'self_assessed_level': row['self_assessed_level'],
    'learning_goals': _stringList(row['learning_goals']),
  };
}

String _decimalText(Object? value) {
  final parsed = _requiredDecimal(value);
  return parsed.toStringAsFixed(2);
}

double _requiredDecimal(Object? value) {
  final parsed = _decimal(value);
  if (parsed == null) throw const FormatException('decimal preference');
  return parsed;
}

double? _decimal(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw const FormatException('decimal preference');
}

int? _wholeDecimal(Object? value) {
  final parsed = _decimal(value);
  if (parsed == null) return null;
  return parsed.round();
}

List<String> _stringList(Object? value) {
  final items = _list(value);
  return [
    for (final item in items)
      if (item is String) item else throw const FormatException('string list'),
  ];
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('settings list');
  return List<Object?>.from(value);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('settings object');
  return Map<String, Object?>.from(value);
}

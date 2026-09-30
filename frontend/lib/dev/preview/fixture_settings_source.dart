import 'package:dio/dio.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';

import 'fixture_store.dart';

/// Process-local stand-in for the three independently revised me endpoints.
/// It applies a field mask only after the asynchronous source boundary.
final class FixtureSettingsSource implements SettingsSource {
  FixtureSettingsSource(this.store, this.cache);

  final PreviewFixtureStore store;
  final CacheCoordinator cache;
  String? _genderDescription;
  final _revisions = <SettingsGroup, int>{for (final group in SettingsGroup.values) group: 1};
  late List<Map<String, Object?>> _targetLanguages = [
    for (final language in store.learningLanguages)
      {
        'language_tag': language,
        'self_assessed_level': language == store.activeLanguage ? store.learningLevel : 'unknown',
        'learning_goals': language == store.activeLanguage
            ? store.learningGoals.toList()
            : <String>[],
      },
  ];

  @override
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel) async {
    _requirePreviewScope();
    if (cancel.isCancelled) throw const CacheBlocked('cancelled');
    return _snapshot(group);
  }

  @override
  Future<SettingsSnapshot> patch(SettingsGroup group, SettingsPatch patch) async {
    _requirePreviewScope();
    if (patch.expectedRevision != _revisions[group]) {
      throw const SettingsRevisionConflict();
    }
    if (patch.fields.isEmpty) throw ArgumentError.value(patch.fields, 'fields');
    final allowed = switch (group) {
      SettingsGroup.profile => {
        'display_name',
        'birth_year',
        'gender_code',
        'gender_self_description',
        'use_optional_demographics_for_ai',
      },
      SettingsGroup.studyProfile => {
        'native_languages',
        'target_languages',
        'active_target_language',
        'explanation_language',
      },
      SettingsGroup.preferences => {
        'timezone',
        'reading_font_family',
        'reading_font_size',
        'reading_line_height',
        'reading_theme',
        'query_context_budget_tokens',
        'model_provider',
        'text_model',
        'vision_model',
        'tts_model',
        'speech_voice',
        'speech_format',
        'speech_style',
        'playback_speed',
        'theme_mode',
        'reduce_motion',
      },
    };
    if (!allowed.containsAll(patch.fields.keys)) {
      throw ArgumentError.value(patch.fields.keys.toList(), 'fields');
    }
    final next = {..._snapshot(group).fields, ...patch.fields};
    switch (group) {
      case SettingsGroup.profile:
        final name = next['display_name'] as String;
        final birthYear = next['birth_year'] as int?;
        if (birthYear != null && (birthYear < 1900 || birthYear > DateTime.now().year)) {
          throw ArgumentError.value(birthYear, 'birth_year');
        }
        final genderCode = next['gender_code'] as String;
        if (!const {
          'unset',
          'unspecified',
          'female',
          'male',
          'non_binary',
          'self_described',
          'prefer_not_to_say',
        }.contains(genderCode)) {
          throw ArgumentError.value(genderCode, 'gender_code');
        }
        final gender = genderCode == 'unspecified' ? 'unset' : genderCode;
        _genderDescription = next['gender_self_description'] as String?;
        final consent = next['use_optional_demographics_for_ai'] as bool;
        store.updateProfileDetails(
          name: name,
          birthYear: birthYear,
          gender: gender,
          timezone: store.timezone,
          allowProfileForAi: consent,
        );
      case SettingsGroup.studyProfile:
        final nativeLanguages = _strings(next['native_languages']);
        final targetLanguages = _validatedTargets(next['target_languages']);
        final learningLanguages = {
          for (final row in targetLanguages) row['language_tag'] as String,
        };
        final activeLanguage = next['active_target_language'] as String;
        final explanationLanguage = next['explanation_language'] as String;
        if (!const {'ja', 'en'}.containsAll(learningLanguages) ||
            (activeLanguage.isNotEmpty && !learningLanguages.contains(activeLanguage))) {
          throw ArgumentError.value(learningLanguages, 'target_languages');
        }
        final activeRow = targetLanguages
            .where((row) => row['language_tag'] == activeLanguage)
            .firstOrNull;
        final learningLevel = activeRow?['self_assessed_level'] as String? ?? 'unknown';
        final learningGoals = activeRow == null
            ? <String>{}
            : _strings(activeRow['learning_goals']);
        _targetLanguages = targetLanguages;
        store.nativeLanguages = nativeLanguages;
        store.learningLanguages = learningLanguages;
        store.activeLanguage = activeLanguage;
        store.explanationLanguage = explanationLanguage;
        store.learningLevel = learningLevel;
        store.learningGoals = learningGoals;
        store.editSettingsDraft((_) {});
      case SettingsGroup.preferences:
        final timezone = next['timezone'] as String;
        final readingFont = next['reading_font_family'] as String;
        final readingFontSize = next['reading_font_size'] as int;
        final readingLineHeight = next['reading_line_height'] as double;
        final readingTheme = next['reading_theme'] as String;
        final queryContextBudget = next['query_context_budget_tokens'] as int;
        final modelProvider = next['model_provider'] as String;
        final textModel = next['text_model'] as String;
        final visionModel = next['vision_model'] as String;
        final ttsModel = next['tts_model'] as String;
        final speechVoice = next['speech_voice'] as String;
        final speechFormat = next['speech_format'] as String;
        final speechStyle = next['speech_style'] as String;
        final speechSpeed = next['playback_speed'] as double;
        final themeMode = next['theme_mode'] as String;
        final reduceMotion = next['reduce_motion'] as String;
        if (reduceMotion != 'on' && reduceMotion != 'system') {
          throw ArgumentError.value(reduceMotion, 'reduce_motion');
        }
        final reducedMotion = reduceMotion == 'on';
        if (queryContextBudget < 1000 || queryContextBudget > 64000) {
          throw ArgumentError.value(queryContextBudget, 'query_context_budget_tokens');
        }
        if (speechSpeed < 0.7 || speechSpeed > 1.5) {
          throw ArgumentError.value(speechSpeed, 'playback_speed');
        }
        store.timezone = timezone;
        store.readingFont = readingFont;
        store.readingFontSize = readingFontSize;
        store.readingLineHeight = readingLineHeight;
        store.readingTheme = readingTheme;
        store.queryContextBudget = queryContextBudget;
        store.modelProvider = modelProvider;
        store.textModel = textModel;
        store.visionModel = visionModel;
        store.ttsModel = ttsModel;
        store.speechVoice = speechVoice;
        store.speechFormat = speechFormat;
        store.speechStyle = speechStyle;
        store.speechSpeed = speechSpeed;
        store.editSettingsDraft((_) {});
        if (patch.fields.containsKey('theme_mode') || patch.fields.containsKey('reduce_motion')) {
          store.updateAppearance(themeMode, reducedMotion);
        }
    }
    _revisions[group] = _revisions[group]! + 1;
    return _snapshot(group);
  }

  Set<String> _strings(Object? value) => (value as List).cast<String>().toSet();

  List<Map<String, Object?>> _validatedTargets(Object? value) {
    final rows = (value as List).map((row) => (row as Map).cast<String, Object?>()).toList();
    final seen = <String>{};
    for (final row in rows) {
      if (row.keys.toSet().difference({
        'language_tag',
        'self_assessed_level',
        'learning_goals',
      }).isNotEmpty) {
        throw ArgumentError.value(row, 'target_languages');
      }
      final tag = row['language_tag'] as String;
      final level = row['self_assessed_level'] as String;
      final goals = (row['learning_goals'] as List).cast<String>().toList();
      if (!seen.add(tag) ||
          !const {'ja', 'en'}.contains(tag) ||
          !const {
            'unknown',
            'beginner',
            'elementary',
            'intermediate',
            'advanced',
          }.contains(level) ||
          goals.toSet().length != goals.length) {
        throw ArgumentError.value(row, 'target_languages');
      }
    }
    return rows;
  }

  void _requirePreviewScope() {
    final scope = cache.scope;
    if (!cache.accessReady ||
        scope?.endpointKey != 'http://127.0.0.1/mock-preview' ||
        scope?.instanceId != 'preview-fixtures' ||
        scope?.userId != 'preview-user' ||
        scope?.audience != 'client') {
      throw const CacheBlocked('scope_changed');
    }
  }

  SettingsSnapshot _snapshot(SettingsGroup group) => SettingsSnapshot(
    group: group,
    revision: _revisions[group]!,
    fields: switch (group) {
      SettingsGroup.profile => {
        'display_name': store.displayName,
        'birth_year': store.birthYear,
        'gender_code': store.gender == 'unset' ? 'unspecified' : store.gender,
        'gender_self_description': _genderDescription,
        'use_optional_demographics_for_ai': store.allowProfileForAi,
      },
      SettingsGroup.studyProfile => {
        'native_languages': store.nativeLanguages.toList(),
        'target_languages': [for (final row in _targetLanguages) Map.of(row)],
        'active_target_language': store.activeLanguage,
        'explanation_language': store.explanationLanguage,
      },
      SettingsGroup.preferences => {
        'timezone': store.timezone,
        'reading_font_family': store.readingFont,
        'reading_font_size': store.readingFontSize,
        'reading_line_height': store.readingLineHeight,
        'reading_theme': store.readingTheme,
        'query_context_budget_tokens': store.queryContextBudget,
        'model_provider': store.modelProvider,
        'text_model': store.textModel,
        'vision_model': store.visionModel,
        'tts_model': store.ttsModel,
        'speech_voice': store.speechVoice,
        'speech_format': store.speechFormat,
        'speech_style': store.speechStyle,
        'playback_speed': store.speechSpeed,
        'theme_mode': store.themeMode,
        'reduce_motion': store.reducedMotion ? 'on' : 'system',
      },
    },
  );
}

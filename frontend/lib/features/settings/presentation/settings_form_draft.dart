import 'package:flutter/foundation.dart';
import 'package:haruka/dev/preview/fixture_store.dart';

import '../data/cached_settings_repository.dart';
import '../domain/settings_snapshot.dart';

final class _DraftBaseline {
  _DraftBaseline(this.scope, this.revision, this.values);
  final int scope;
  final int revision;
  final Map<String, Object> values;
  bool conflict = false;
}

/// Keep local edits through route/layout changes. Merge later revisions into
/// untouched fields and require a reload for edits that conflict with source.
final Expando<Map<SettingsGroup, _DraftBaseline>> _baselines = Expando('settings form baselines');
final Expando<Map<String, ({String level, Set<String> goals})>> _languageEdits = Expando(
  'settings language edits',
);

bool settingsFormDraftHasConflict(PreviewFixtureStore store, SettingsGroup group) =>
    _baselines[store]?[group]?.conflict ?? false;

void resetSettingsFormDraft(PreviewFixtureStore store, SettingsGroup group) {
  _baselines[store]?.remove(group);
  if (group == SettingsGroup.studyProfile) _languageEdits[store] = {};
  store.editSettingsDraft((_) {});
}

void hydrateSettingsFormDraft(
  PreviewFixtureStore store,
  CachedSettingsRepository repository,
  SettingsGroup group,
) {
  final snapshot = repository.snapshot(group);
  if (snapshot == null || group == SettingsGroup.profile) return;
  final values = _normalized(group, snapshot.fields);
  final baselines = _baselines[store] ??= {};
  final previous = baselines[group];
  final scope = repository.scopeGeneration;
  if (previous?.scope == scope && previous?.revision == snapshot.revision) return;
  final freshScope = previous == null || previous.scope != scope;
  if (freshScope && group == SettingsGroup.studyProfile) _languageEdits[store] = {};
  final next = _DraftBaseline(scope, snapshot.revision, values);
  if (!freshScope) next.conflict = previous.conflict;
  final draft = store.settingsDraft;
  for (final entry in values.entries) {
    final old = previous?.values[entry.key];
    final current = _draftValue(draft, entry.key);
    if (freshScope || _same(current, old)) {
      _setDraftValue(draft, entry.key, entry.value);
    } else if (!_same(old, entry.value) && !_same(current, entry.value)) {
      next.conflict = true;
    }
  }
  baselines[group] = next;
}

Map<String, Object> _normalized(SettingsGroup group, Map<String, Object?> fields) {
  switch (group) {
    case SettingsGroup.profile:
      return const {};
    case SettingsGroup.studyProfile:
      final targets = ((fields['target_languages'] as List?) ?? const [])
          .cast<Map<String, Object?>>();
      final active = fields['active_target_language'] as String? ?? '';
      final activeRow = targets.where((row) => row['language_tag'] == active).firstOrNull;
      return {
        'nativeLanguages': ((fields['native_languages'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        'learningLanguages': {for (final row in targets) row['language_tag'] as String},
        'activeLanguage': active,
        'explanationLanguage': fields['explanation_language'] as String? ?? 'zh-Hans',
        'learningLevel': switch (activeRow?['self_assessed_level']) {
          'unknown' => 'unset',
          'elementary' => 'basic',
          final String level => level,
          _ => 'unset',
        },
        'learningGoals': ((activeRow?['learning_goals'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      };
    case SettingsGroup.preferences:
      return {
        'readingFont': fields['reading_font_family'] as String? ?? 'serif',
        'readingFontSize': fields['reading_font_size'] as int? ?? 18,
        'readingLineHeight': fields['reading_line_height'] as double? ?? 1.8,
        'readingTheme': fields['reading_theme'] as String? ?? 'light',
        'queryContextBudget': fields['query_context_budget_tokens'] as int? ?? 10000,
        'queryBudgetText': (fields['query_context_budget_tokens'] as int? ?? 10000).toString(),
        'modelProvider': fields['model_provider'] as String? ?? 'openrouter',
        'textModel': fields['text_model'] as String? ?? 'default',
        'visionModel': fields['vision_model'] as String? ?? 'default',
        'ttsModel': fields['tts_model'] as String? ?? 'gemini',
        'speechVoice': fields['speech_voice'] as String? ?? 'japaneseClear',
        'speechFormat': fields['speech_format'] as String? ?? 'wav',
        'speechStyle': fields['speech_style'] as String? ?? 'natural',
        'speechSpeed': fields['playback_speed'] as double? ?? 1.0,
      };
  }
}

bool _same(Object? a, Object? b) => a is Set && b is Set ? setEquals(a, b) : a == b;

Object _draftValue(SettingsDraft draft, String key) => switch (key) {
  'nativeLanguages' => draft.nativeLanguages,
  'learningLanguages' => draft.learningLanguages,
  'activeLanguage' => draft.activeLanguage,
  'explanationLanguage' => draft.explanationLanguage,
  'learningLevel' => draft.learningLevel,
  'learningGoals' => draft.learningGoals,
  'readingFont' => draft.readingFont,
  'readingFontSize' => draft.readingFontSize,
  'readingLineHeight' => draft.readingLineHeight,
  'readingTheme' => draft.readingTheme,
  'queryContextBudget' => draft.queryContextBudget,
  'queryBudgetText' => draft.queryBudgetText,
  'modelProvider' => draft.modelProvider,
  'textModel' => draft.textModel,
  'visionModel' => draft.visionModel,
  'ttsModel' => draft.ttsModel,
  'speechVoice' => draft.speechVoice,
  'speechFormat' => draft.speechFormat,
  'speechStyle' => draft.speechStyle,
  'speechSpeed' => draft.speechSpeed,
  _ => throw ArgumentError.value(key, 'key'),
};

void _setDraftValue(SettingsDraft draft, String key, Object value) {
  switch (key) {
    case 'nativeLanguages':
      draft.nativeLanguages = (value as Set<String>).toSet();
    case 'learningLanguages':
      draft.learningLanguages = (value as Set<String>).toSet();
    case 'activeLanguage':
      draft.activeLanguage = value as String;
    case 'explanationLanguage':
      draft.explanationLanguage = value as String;
    case 'learningLevel':
      draft.learningLevel = value as String;
    case 'learningGoals':
      draft.learningGoals = (value as Set<String>).toSet();
    case 'readingFont':
      draft.readingFont = value as String;
    case 'readingFontSize':
      draft.readingFontSize = value as int;
    case 'readingLineHeight':
      draft.readingLineHeight = value as double;
    case 'readingTheme':
      draft.readingTheme = value as String;
    case 'queryContextBudget':
      draft.queryContextBudget = value as int;
    case 'queryBudgetText':
      draft.queryBudgetText = value as String;
    case 'modelProvider':
      draft.modelProvider = value as String;
    case 'textModel':
      draft.textModel = value as String;
    case 'visionModel':
      draft.visionModel = value as String;
    case 'ttsModel':
      draft.ttsModel = value as String;
    case 'speechVoice':
      draft.speechVoice = value as String;
    case 'speechFormat':
      draft.speechFormat = value as String;
    case 'speechStyle':
      draft.speechStyle = value as String;
    case 'speechSpeed':
      draft.speechSpeed = value as double;
    default:
      throw ArgumentError.value(key, 'key');
  }
}

void selectSettingsTargetLanguage(
  PreviewFixtureStore store,
  CachedSettingsRepository repository,
  String language,
) {
  final draft = store.settingsDraft;
  if (draft.activeLanguage == language) return;
  final edits = _languageEdits[store] ??= {};
  if (draft.activeLanguage.isNotEmpty) {
    edits[draft.activeLanguage] = (level: draft.learningLevel, goals: {...draft.learningGoals});
  }
  final saved =
      (repository.snapshot(SettingsGroup.studyProfile)?.fields['target_languages'] as List?)
          ?.cast<Map<String, Object?>>()
          .where((row) => row['language_tag'] == language)
          .firstOrNull;
  final edit = edits[language];
  draft.activeLanguage = language;
  draft.learningLevel =
      edit?.level ??
      switch (saved?['self_assessed_level']) {
        'unknown' => 'unset',
        'elementary' => 'basic',
        final String level => level,
        _ => 'unset',
      };
  draft.learningGoals =
      edit?.goals ?? ((saved?['learning_goals'] as List?) ?? const []).cast<String>().toSet();
}

import 'settings_snapshot.dart';

const profileGuideCompletenessFields = [
  'display_name',
  'explanation_language',
  'target_language',
  'timezone',
];

/// Completion is the server field projection. A skipped guide does not count.
bool profileGuideIncomplete(Object? completeness) {
  if (completeness is! Map) return true;
  final flags = Map<String, Object?>.from(completeness);
  for (final field in profileGuideCompletenessFields) {
    if (flags[field] != true) return true;
  }
  return false;
}

final class ProfileGuideInput {
  const ProfileGuideInput({
    this.displayName = '',
    this.nativeLanguage,
    this.explanationLanguage,
    this.targetLanguage,
    this.timezone,
  });

  final String displayName;
  final String? nativeLanguage;
  final String? explanationLanguage;
  final String? targetLanguage;
  final String? timezone;
}

/// Only fields the user actually chose. An empty result must not be patched.
Map<SettingsGroup, Map<String, Object?>> profileGuidePatches(
  ProfileGuideInput input, {
  SettingsSnapshot? profile,
  SettingsSnapshot? studyProfile,
  SettingsSnapshot? preferences,
}) {
  final patches = <SettingsGroup, Map<String, Object?>>{};
  final name = input.displayName.trim();
  if (name.isNotEmpty && name != profile?.fields['display_name']) {
    patches[SettingsGroup.profile] = {'display_name': name};
  }
  final study = <String, Object?>{};
  final native = input.nativeLanguage;
  final existingNative =
      (studyProfile?.fields['native_languages'] as List?)?.whereType<String>().toList() ??
      <String>[];
  if (native != null && native.isNotEmpty && !existingNative.contains(native)) {
    study['native_languages'] = [...existingNative, native];
  }
  final explanation = input.explanationLanguage;
  if (explanation != null &&
      explanation.isNotEmpty &&
      explanation != studyProfile?.fields['explanation_language']) {
    study['explanation_language'] = explanation;
  }
  final target = input.targetLanguage;
  if (target != null && target.isNotEmpty) {
    final existingTargets =
        (studyProfile?.fields['target_languages'] as List?)
            ?.whereType<Map<String, Object?>>()
            .toList() ??
        <Map<String, Object?>>[];
    if (!existingTargets.any((row) => row['language_tag'] == target)) {
      study['target_languages'] = [
        ...existingTargets,
        {'language_tag': target, 'self_assessed_level': 'unknown', 'learning_goals': <String>[]},
      ];
    }
    if (target != studyProfile?.fields['active_target_language']) {
      study['active_target_language'] = target;
    }
  }
  if (study.isNotEmpty) patches[SettingsGroup.studyProfile] = study;
  final timezone = input.timezone;
  if (timezone != null && timezone.isNotEmpty && timezone != preferences?.fields['timezone']) {
    patches[SettingsGroup.preferences] = {'timezone': timezone};
  }
  return patches;
}

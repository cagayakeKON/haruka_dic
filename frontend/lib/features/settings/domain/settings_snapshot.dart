enum SettingsGroup { profile, studyProfile, preferences }

extension SettingsGroupCacheKey on SettingsGroup {
  String get dependency => switch (this) {
    SettingsGroup.profile => 'settings:profile',
    SettingsGroup.studyProfile => 'settings:study-profile',
    SettingsGroup.preferences => 'settings:preferences',
  };

  String get sourceId => switch (this) {
    SettingsGroup.profile => 'profile',
    SettingsGroup.studyProfile => 'study-profile',
    SettingsGroup.preferences => 'settings',
  };
}

/// The three user_extensions revisions remain independent even when the
/// server stores their fields in one row.
final class SettingsSnapshot {
  SettingsSnapshot({
    required this.group,
    required this.revision,
    required Map<String, Object?> fields,
  }) : fields = Map.unmodifiable(fields);

  final SettingsGroup group;
  final int revision;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {
    'group': group.sourceId,
    'revision': revision,
    'fields': fields,
  };

  factory SettingsSnapshot.fromJson(Map<String, Object?> json) {
    final group = SettingsGroup.values.singleWhere(
      (candidate) => candidate.sourceId == json['group'],
    );
    return SettingsSnapshot(
      group: group,
      revision: json['revision'] as int,
      fields: (json['fields'] as Map).cast<String, Object?>(),
    );
  }
}

/// A masked domain update. An API adapter maps the preview's compact language
/// controls to the per-target language rows of the study-profile contract.
final class SettingsPatch {
  SettingsPatch({required this.expectedRevision, required Map<String, Object?> fields})
    : fields = Map.unmodifiable(fields);

  final int expectedRevision;
  final Map<String, Object?> fields;
}

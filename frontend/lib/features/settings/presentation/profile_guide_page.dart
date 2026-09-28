import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';

import '../data/settings_source.dart';
import '../data/language_capabilities.dart';
import '../domain/profile_guide.dart';
import '../domain/settings_snapshot.dart';

/// Opens the guide only after an explicit login when the server projection is
/// incomplete. Session restore does not call this, and skip stores nothing.
Future<String> profileGuideLocation({
  required bool canReadProfile,
  required SettingsSource? source,
}) async {
  if (!canReadProfile || source == null) return AppRoutes.account;
  final cancel = CancelToken();
  try {
    final profile = await source.fetch(SettingsGroup.profile, cancel);
    if (profileGuideIncomplete(profile.fields['profile_completeness'])) {
      return AppRoutes.guide;
    }
  } on Object {
    return AppRoutes.account;
  } finally {
    cancel.cancel();
  }
  return AppRoutes.account;
}

class ProfileGuidePage extends StatefulWidget {
  const ProfileGuidePage({
    required this.onSave,
    required this.onSkip,
    required this.profile,
    required this.study,
    required this.preferences,
    required this.canSave,
    super.key,
  });

  final Future<void> Function(ProfileGuideInput input) onSave;
  final VoidCallback onSkip;
  final SettingsSnapshot profile;
  final SettingsSnapshot study;
  final SettingsSnapshot preferences;
  final bool canSave;

  @override
  State<ProfileGuidePage> createState() => _ProfileGuidePageState();
}

class _ProfileGuidePageState extends State<ProfileGuidePage> {
  final _name = TextEditingController();
  String? _native;
  String? _explanation;
  String? _target;
  String? _timezone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.profile.fields['display_name'] as String? ?? '';
    _native =
        ((widget.study.fields['native_languages'] as List?) ?? const []).firstOrNull as String?;
    _explanation = widget.study.fields['explanation_language'] as String?;
    _target = widget.study.fields['active_target_language'] as String?;
    _timezone = widget.preferences.fields['timezone'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ProfileGuideInput get _input => ProfileGuideInput(
    displayName: _name.text,
    nativeLanguage: _native,
    explanationLanguage: _explanation,
    targetLanguage: _target,
    timezone: _timezone,
  );

  Future<void> _save() async {
    if (_saving) return;
    if (profileGuidePatches(
      _input,
      profile: widget.profile,
      studyProfile: widget.study,
      preferences: widget.preferences,
    ).isEmpty) {
      widget.onSkip();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_input);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).apiUnknownError)));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogue = LanguageCapabilitiesScope.maybeOf(context);
    final native = {
      for (final option in catalogue?.languages ?? const <LanguageOption>[])
        if (option.native) option.code: option.label,
    };
    final explanation = {
      for (final option in catalogue?.languages ?? const <LanguageOption>[])
        if (option.explanation) option.code: option.label,
    };
    final targets = {
      for (final option in catalogue?.languages ?? const <LanguageOption>[])
        if (option.learning) option.code: option.label,
    };
    final timezones = {
      'Asia/Tokyo': l10n.mockProfileTimezoneTokyo,
      'Asia/Shanghai': l10n.mockProfileTimezoneShanghai,
      'UTC': l10n.mockProfileTimezoneUtc,
      if (_timezone != null && !{'Asia/Tokyo', 'Asia/Shanghai', 'UTC'}.contains(_timezone))
        _timezone!: _timezone!,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Text(l10n.profileGuideTitle, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(l10n.profileGuideBody),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: l10n.mockSettingDisplayName,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _choice(
          label: l10n.mockSettingNativeLanguages,
          value: _native,
          options: native,
          onChanged: (value) => setState(() => _native = value),
        ),
        const SizedBox(height: 16),
        _choice(
          label: l10n.mockSettingExplanationLanguage,
          value: _explanation,
          options: explanation,
          onChanged: (value) => setState(() => _explanation = value),
        ),
        const SizedBox(height: 16),
        _choice(
          label: l10n.mockSettingTargetLanguages,
          value: _target,
          options: targets,
          onChanged: (value) => setState(() => _target = value),
        ),
        const SizedBox(height: 16),
        _choice(
          label: l10n.mockProfileTimezone,
          value: _timezone,
          options: timezones,
          onChanged: (value) => setState(() => _timezone = value),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey(UiTestIds.settingsGuideSave),
          onPressed:
              _saving || !widget.canSave || LanguageCapabilitiesScope.maybeOf(context) == null
              ? null
              : _save,
          child: Text(l10n.mockSettingSaveProfile),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey(UiTestIds.settingsGuideSkip),
          onPressed: _saving ? null : widget.onSkip,
          child: Text(l10n.profileGuideSkip),
        ),
      ],
    );
  }
}

class _GuideChoice extends StatelessWidget {
  const _GuideChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final option in options.entries)
          DropdownMenuItem(value: option.key, child: Text(option.value)),
      ],
      onChanged: onChanged,
    );
  }
}

Widget _choice({
  required String label,
  required String? value,
  required Map<String, String> options,
  required ValueChanged<String?> onChanged,
}) => _GuideChoice(label: label, value: value, options: options, onChanged: onChanged);

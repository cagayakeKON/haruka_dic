import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/data/http_settings_source.dart';
import 'package:haruka/features/settings/presentation/avatar_row.dart';
import 'package:haruka/features/settings/presentation/settings_chrome.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_snapshot_gate.dart';

class ProfileDetailPage extends StatefulWidget {
  const ProfileDetailPage({this.framed = true, super.key});

  final bool framed;

  @override
  State<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  final name = TextEditingController();
  final birthYear = TextEditingController();
  final genderDescription = TextEditingController();
  String gender = 'unset';
  String? timezone;
  int? _loadedScopeGeneration;
  int? _profileRevision;
  int? _preferencesRevision;
  String? _nameBaseline;
  String? _birthYearBaseline;
  String? _genderBaseline;
  String? _genderDescriptionBaseline;
  String? _timezoneBaseline;
  bool _profileConflict = false;
  bool _preferencesConflict = false;

  @override
  void dispose() {
    name.dispose();
    birthYear.dispose();
    genderDescription.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final auth = sessionAuth(context);
    if (!settingsUsePreviewAvatar(context) &&
        !(auth?.access?.allows('client.profile.update') ?? false)) {
      return;
    }
    if (_profileConflict || _preferencesConflict) {
      if (!mounted) return;
      _showRevisionConflict();
      return;
    }
    final normalizedName = name.text.trim();
    final birthInput = birthYear.text.trim();
    final year = birthInput.isEmpty ? null : int.tryParse(birthInput);
    if (birthInput.isNotEmpty && (year == null || year < 1900 || year > DateTime.now().year)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).mockProfileBirthYearInvalid)),
      );
      return;
    }
    final repository = SettingsRepositoryScope.of(context);
    final epoch = auth?.actionEpoch;
    final instance = auth?.boundInstanceId;
    final user = auth?.access?.userId;
    final scope = repository.scopeGeneration;
    bool stillOwned() =>
        mounted &&
        repository.scopeGeneration == scope &&
        (auth == null ||
            (auth.isAuthenticated &&
                auth.actionEpoch == epoch &&
                auth.boundInstanceId == instance &&
                auth.access?.userId == user));
    final profile = repository.snapshot(SettingsGroup.profile)!;
    final apiGender = switch (gender) {
      'unset' => 'unspecified',
      'self_describe' => 'self_described',
      'prefer_not' => 'prefer_not_to_say',
      _ => gender,
    };
    final profileChanged =
        normalizedName != profile.fields['display_name'] ||
        year != profile.fields['birth_year'] ||
        apiGender != profile.fields['gender_code'] ||
        (gender == 'self_describe' ? genderDescription.text.trim() : null) !=
            profile.fields['gender_self_description'];
    var profileCommitted = false;
    if (profileChanged) {
      try {
        await repository.save(SettingsGroup.profile, {
          'display_name': normalizedName,
          'birth_year': year,
          'gender_code': apiGender,
          'gender_self_description': gender == 'self_describe'
              ? genderDescription.text.trim()
              : null,
        });
        if (!mounted || !stillOwned()) return;
        profileCommitted = true;
        trackSettingsMutation(context, 'profile.updated');
      } on SettingsRevisionConflict {
        if (!stillOwned()) return;
        await repository.refresh(SettingsGroup.profile, force: true);
        if (stillOwned()) _showRevisionConflict();
        return;
      } on Object {
        if (!mounted || !stillOwned()) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).apiUnknownError)));
        return;
      }
    }
    if (!stillOwned()) return;
    if (timezone != repository.snapshot(SettingsGroup.preferences)?.fields['timezone']) {
      try {
        await repository.save(SettingsGroup.preferences, {'timezone': timezone});
        if (!mounted || !stillOwned()) return;
        trackSettingsMutation(context, 'settings.updated');
      } on SettingsRevisionConflict {
        if (!stillOwned()) return;
        await repository.refresh(SettingsGroup.preferences, force: true);
        if (stillOwned()) _showRevisionConflict(partial: profileCommitted);
        return;
      } on Object {
        if (!mounted || !stillOwned()) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                profileCommitted
                    ? AppLocalizations.of(context).mockProfileSavedTimezoneFailed
                    : AppLocalizations.of(context).apiUnknownError,
              ),
            ),
          );
        return;
      }
    }
    if (!mounted || !stillOwned()) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).mockSettingSettingsSaved)));
  }

  void _showRevisionConflict({bool partial = false}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(partial ? l10n.mockProfileSavedTimezoneFailed : l10n.apiRevisionConflict),
          action: SnackBarAction(
            label: l10n.referenceRetry,
            onPressed: () => setState(() {
              _profileConflict = false;
              _preferencesConflict = false;
            }),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => SettingsSnapshotGate(
    groups: const {SettingsGroup.profile, SettingsGroup.preferences},
    builder: _buildLoaded,
  );

  Widget _buildLoaded(BuildContext context) {
    final repository = SettingsRepositoryScope.of(context);
    final canEdit =
        settingsUsePreviewAvatar(context) ||
        (sessionAuth(context)?.access?.allows('client.profile.update') ?? false);
    final profile = repository.snapshot(SettingsGroup.profile)!;
    final preferences = repository.snapshot(SettingsGroup.preferences)!;
    final nextName = profile.fields['display_name'] as String? ?? '';
    final nextBirthYear = profile.fields['birth_year']?.toString() ?? '';
    final genderCode = profile.fields['gender_code'] as String?;
    final nextGender = switch (genderCode) {
      'unspecified' => 'unset',
      'self_described' => 'self_describe',
      'prefer_not_to_say' => 'prefer_not',
      _ => genderCode ?? 'unset',
    };
    final nextGenderDescription = profile.fields['gender_self_description'] as String? ?? '';
    final nextTimezone = preferences.fields['timezone'] as String?;
    if (_loadedScopeGeneration != repository.scopeGeneration) {
      name.text = nextName;
      birthYear.text = nextBirthYear;
      gender = nextGender;
      genderDescription.text = nextGenderDescription;
      timezone = nextTimezone;
      _loadedScopeGeneration = repository.scopeGeneration;
      _profileConflict = false;
      _preferencesConflict = false;
    } else {
      if (_profileRevision != profile.revision) {
        if (name.text.trim() == _nameBaseline) {
          name.text = nextName;
        } else if (_nameBaseline != nextName && name.text.trim() != nextName) {
          _profileConflict = true;
        } else if (name.text.trim() == nextName) {
          name.text = nextName;
        }
        if (birthYear.text == _birthYearBaseline) {
          birthYear.text = nextBirthYear;
        } else if (_birthYearBaseline != nextBirthYear && birthYear.text != nextBirthYear) {
          _profileConflict = true;
        }
        if (gender == _genderBaseline) {
          gender = nextGender;
        } else if (_genderBaseline != nextGender && gender != nextGender) {
          _profileConflict = true;
        }
        if (genderDescription.text == _genderDescriptionBaseline) {
          genderDescription.text = nextGenderDescription;
        } else if (_genderDescriptionBaseline != nextGenderDescription &&
            genderDescription.text != nextGenderDescription) {
          _profileConflict = true;
        }
      }
      if (_preferencesRevision != preferences.revision) {
        if (timezone == _timezoneBaseline) {
          timezone = nextTimezone;
        } else if (_timezoneBaseline != nextTimezone && timezone != nextTimezone) {
          _preferencesConflict = true;
        }
      }
    }
    _profileRevision = profile.revision;
    _preferencesRevision = preferences.revision;
    _nameBaseline = nextName;
    _birthYearBaseline = nextBirthYear;
    _genderBaseline = nextGender;
    _genderDescriptionBaseline = nextGenderDescription;
    _timezoneBaseline = nextTimezone;
    return settingsChrome(
      context: context,
      framed: widget.framed,
      location: settingsSectionPath(context, 'profile'),
      title: AppLocalizations.of(context).mockSettingProfile,
      detail: true,
      detailNotifications: false,
      desktopBackLabel: AppLocalizations.of(context).mockSettingMyTitle,
      onBack: () => context.go(settingsHome(context)),
      mobile: MobileProfileView(
        canEdit: canEdit,
        name: name,
        birthYear: birthYear,
        genderDescription: genderDescription,
        gender: gender,
        timezone: timezone,
        onGenderChanged: (value) {
          if (value != null) setState(() => gender = value);
        },
        onTimezoneChanged: (value) => setState(() => timezone = value),
        onSave: save,
      ),
      desktop: DesktopProfileView(
        canEdit: canEdit,
        name: name,
        birthYear: birthYear,
        genderDescription: genderDescription,
        gender: gender,
        timezone: timezone,
        onGenderChanged: (value) {
          if (value != null) setState(() => gender = value);
        },
        onTimezoneChanged: (value) => setState(() => timezone = value),
        onSave: save,
      ),
    );
  }
}

typedef ProfileSelection = void Function(String? value);

class MobileProfileView extends StatelessWidget {
  const MobileProfileView({
    required this.canEdit,
    required this.name,
    required this.birthYear,
    required this.genderDescription,
    required this.gender,
    required this.timezone,
    required this.onGenderChanged,
    required this.onTimezoneChanged,
    required this.onSave,
    super.key,
  });

  final TextEditingController name;
  final bool canEdit;
  final TextEditingController birthYear;
  final TextEditingController genderDescription;
  final String gender;
  final String? timezone;
  final ProfileSelection onGenderChanged;
  final ProfileSelection onTimezoneChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      children: [
        Text(
          l10n.mockProfileGreeting(
            displayNameOrFallback(
              context,
              SettingsRepositoryScope.of(context)
                          .snapshot(SettingsGroup.profile)
                          ?.fields['display_name']
                      as String? ??
                  '',
            ),
          ),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.mockProfileAvatarTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const ProfileAvatarPrivacy(mobile: true, showConsent: false),
        const SizedBox(height: 14),
        HarukaSurface(
          child: ProfileFields(
            canEdit: canEdit,
            name: name,
            birthYear: birthYear,
            genderDescription: genderDescription,
            gender: gender,
            timezone: timezone,
            onGenderChanged: onGenderChanged,
            onTimezoneChanged: onTimezoneChanged,
            onSave: onSave,
            showSave: false,
          ),
        ),
        const SizedBox(height: 14),
        const ProfileAvatarPrivacy(mobile: true, showAvatar: false),
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey(UiTestIds.settingsProfileSave),
          onPressed: canEdit ? onSave : null,
          child: Text(l10n.mockSettingSaveProfile),
        ),
      ],
    );
  }
}

class DesktopProfileView extends StatelessWidget {
  const DesktopProfileView({
    required this.canEdit,
    required this.name,
    required this.birthYear,
    required this.genderDescription,
    required this.gender,
    required this.timezone,
    required this.onGenderChanged,
    required this.onTimezoneChanged,
    required this.onSave,
    super.key,
  });

  final TextEditingController name;
  final bool canEdit;
  final TextEditingController birthYear;
  final TextEditingController genderDescription;
  final String gender;
  final String? timezone;
  final ProfileSelection onGenderChanged;
  final ProfileSelection onTimezoneChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final sections = <(String, String, IconData)>[
      ('profile', l10n.mockSettingProfile, Icons.person_outline),
      ('languages', l10n.mockSettingLanguageOptions, Icons.language_outlined),
      ('appearance', l10n.mockSettingAppearance, Icons.light_mode_outlined),
      ('readingPrefs', l10n.mockSettingReadingPreferences, Icons.menu_book_outlined),
      ('queryPreferences', l10n.mockSettingQueryContext, Icons.chat_bubble_outline),
      if (!settingsUsePreviewAvatar(context))
        ('cache', l10n.mockSettingLocalCache, Icons.storage_outlined),
      if (settingsUsePreviewAvatar(context)) ...[
        ('model', l10n.mockSettingPersonalModel, Icons.auto_awesome_outlined),
        ('speech', l10n.mockSettingSpeech, Icons.headphones_outlined),
        ('usage', l10n.mockSettingModelUsage, Icons.grid_view_outlined),
        ('cache', l10n.mockSettingLocalCache, Icons.storage_outlined),
      ],
      ('connection', l10n.mockSettingServiceConnection, Icons.language_outlined),
      ('security', l10n.mockSettingSecurityAccount, Icons.shield_outlined),
    ];
    return ListView(
      children: [
        Text(l10n.mockSettingProfile, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: HarukaSurface(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    for (final section in sections)
                      TextButton.icon(
                        onPressed: () => context.go(settingsSectionPath(context, section.$1)),
                        icon: Icon(section.$3, size: 18),
                        label: Align(alignment: Alignment.centerLeft, child: Text(section.$2)),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          backgroundColor: section.$1 == 'profile' ? roles.selected : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: HarukaContentWidth(
                maxWidth: HarukaLayout.formMaxWidth,
                horizontalPadding: 0,
                child: HarukaSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.mockProfileAvatarTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      const ProfileAvatarPrivacy(mobile: false, showConsent: false),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),
                      ProfileFields(
                        canEdit: canEdit,
                        name: name,
                        birthYear: birthYear,
                        genderDescription: genderDescription,
                        gender: gender,
                        timezone: timezone,
                        onGenderChanged: onGenderChanged,
                        onTimezoneChanged: onTimezoneChanged,
                        onSave: onSave,
                        showSave: false,
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const ProfileAvatarPrivacy(mobile: false, showAvatar: false),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const ValueKey(UiTestIds.settingsProfileSave),
                          onPressed: canEdit ? onSave : null,
                          child: Text(l10n.mockSettingSaveProfile),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfileFields extends StatelessWidget {
  const ProfileFields({
    required this.canEdit,
    required this.name,
    required this.birthYear,
    required this.genderDescription,
    required this.gender,
    required this.timezone,
    required this.onGenderChanged,
    required this.onTimezoneChanged,
    required this.onSave,
    this.showSave = true,
    super.key,
  });

  final TextEditingController name;
  final bool canEdit;
  final TextEditingController birthYear;
  final TextEditingController genderDescription;
  final String gender;
  final String? timezone;
  final ProfileSelection onGenderChanged;
  final ProfileSelection onTimezoneChanged;
  final VoidCallback onSave;
  final bool showSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final genders = <String, String>{
      'unset': l10n.mockProfileGenderUnset,
      'female': l10n.mockProfileGenderFemale,
      'male': l10n.mockProfileGenderMale,
      'non_binary': l10n.mockProfileGenderNonBinary,
      'self_describe': l10n.mockProfileGenderSelfDescribe,
      'prefer_not': l10n.mockProfileGenderPreferNot,
    };
    final timezones = <String, String>{
      'Asia/Tokyo': l10n.mockProfileTimezoneTokyo,
      'Asia/Shanghai': l10n.mockProfileTimezoneShanghai,
      'UTC': l10n.mockProfileTimezoneUtc,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.mockSettingDisplayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: name,
          readOnly: !canEdit,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 27),
        Text(
          l10n.mockSettingBirthYearOptional,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: birthYear,
          readOnly: !canEdit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 27),
        Text(l10n.mockProfileGenderOptional, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('profile-gender:$gender'),
          initialValue: gender,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final entry in genders.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: canEdit
              ? (value) {
                  if (value != null) onGenderChanged(value);
                }
              : null,
        ),
        if (gender == 'self_describe') ...[
          const SizedBox(height: 12),
          TextField(
            controller: genderDescription,
            readOnly: !canEdit,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '自我描述（可选）', border: OutlineInputBorder()),
          ),
        ],
        const SizedBox(height: 27),
        Text(l10n.mockProfileTimezone, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: ValueKey('profile-timezone:$timezone'),
          initialValue: timezone,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('未填写')),
            if (timezone != null && !timezones.containsKey(timezone))
              DropdownMenuItem(value: timezone, child: Text(timezone!)),
            for (final entry in timezones.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: canEdit ? onTimezoneChanged : null,
        ),
        if (showSave) ...[
          const SizedBox(height: 21),
          FilledButton(
            onPressed: canEdit ? onSave : null,
            child: Text(l10n.mockSettingSaveProfile),
          ),
        ],
      ],
    );
  }
}

class ProfileAvatarPrivacy extends StatelessWidget {
  const ProfileAvatarPrivacy({
    required this.mobile,
    this.showAvatar = true,
    this.showConsent = true,
    super.key,
  });
  final bool mobile;
  final bool showAvatar;
  final bool showConsent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final store = PreviewStoreScope.of(context);
    final content = Column(
      children: [
        if (showAvatar) _avatarRow(context, l10n, roles, store),
        if (showAvatar && showConsent) const SizedBox(height: 18),
        if (showConsent)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value:
                SettingsRepositoryScope.of(context)
                    .snapshot(SettingsGroup.profile)
                    ?.fields['use_optional_demographics_for_ai'] ==
                true,
            onChanged:
                !settingsUsePreviewAvatar(context) &&
                    !(sessionAuth(context)?.access?.allows('client.profile.update') ?? false)
                ? null
                : (value) async {
                    try {
                      await SettingsRepositoryScope.of(context)
                          .save(SettingsGroup.profile, {'use_optional_demographics_for_ai': value});
                    } on Object {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(l10n.apiUnknownError)));
                    }
                  },
            title: Text(l10n.mockProfileAiConsent),
          ),
      ],
    );
    return mobile ? HarukaSurface(child: content) : content;
  }

  Widget _avatarRow(
    BuildContext context,
    AppLocalizations l10n,
    HarukaColors roles,
    PreviewFixtureStore store,
  ) {
    final repository = SettingsRepositoryScope.of(context);
    final source = repository.source;
    final auth = sessionAuth(context);
    if (!settingsUsePreviewAvatar(context) && source is HttpSettingsSource && auth != null) {
      return OwnerAvatarRow(api: source.api, repository: repository, auth: auth);
    }
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: roles.signal,
          child: Text(store.avatarGlyph, style: TextStyle(color: roles.onSignal)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(l10n.mockProfileCurrentAvatar)),
        if (settingsUsePreviewAvatar(context))
          TextButton(
            onPressed: () {
              store.selectSampleAvatar();
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.mockProfileAvatarUpdated)));
            },
            child: Text(l10n.mockProfileChangeAvatar),
          ),
      ],
    );
  }
}

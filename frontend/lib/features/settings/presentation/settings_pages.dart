import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/motion.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/language_capabilities.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_chrome.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_snapshot_gate.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/features/settings/presentation/profile_page.dart';
import 'package:haruka/features/settings/presentation/avatar_row.dart';
import 'package:haruka/features/settings/presentation/service_endpoint_form.dart';
import 'package:haruka/features/settings/presentation/settings_form_draft.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/data/http_settings_source.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/auth/account_pages.dart';
import 'package:haruka/core/api/request_ids.dart';
import 'package:haruka/core/telemetry/telemetry.dart';

import 'model_configuration_content.dart';
import 'model_usage_content.dart';

String mockLanguageOptionsSummary(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final study = SettingsRepositoryScope.of(context).snapshot(SettingsGroup.studyProfile);
  if (study == null) return l10n.mockSettingLanguageOptions;
  final learning = study.fields['active_target_language'] == 'ja'
      ? l10n.mockShellJapanese
      : l10n.mockShellEnglish;
  final explanation = switch (study.fields['explanation_language']) {
    'ja' => l10n.mockShellJapanese,
    'en' => l10n.mockShellEnglish,
    _ => l10n.mockSettingSimplifiedChinese,
  };
  return l10n.mockSettingLanguageOptionsSubtitle(learning, explanation);
}

String? mockLearningLevelSummary(BuildContext context) {
  final study = SettingsRepositoryScope.of(context).snapshot(SettingsGroup.studyProfile);
  if (study == null) return null;
  final l10n = AppLocalizations.of(context);
  final language = switch (study.fields['active_target_language']) {
    'ja' => l10n.mockSettingJapanese,
    'en' => l10n.mockSettingEnglish,
    _ => null,
  };
  final targets = (study.fields['target_languages'] as List?) ?? const [];
  final active = study.fields['active_target_language'];
  final activeTarget = targets
      .cast<Map<String, Object?>>()
      .where((row) => row['language_tag'] == active)
      .firstOrNull;
  final level = switch (activeTarget?['self_assessed_level']) {
    'beginner' => l10n.mockSettingLevelBeginner,
    'intermediate' => l10n.mockSettingLevelIntermediate,
    'advanced' => l10n.mockSettingLevelAdvanced,
    _ => null,
  };
  if (language == null || level == null) return null;
  return l10n.mockSettingLanguageLevelSummary(language, level);
}

Map<String, List<(String, String, IconData, String)>> mockSettingGroups(BuildContext context) {
  final groups = <String, List<(String, String, IconData, String)>>{
    AppLocalizations.of(context).mockSettingAccountLanguageGroup: [
      (
        'profile',
        AppLocalizations.of(context).mockSettingProfile,
        Icons.person_outline,
        AppLocalizations.of(context).mockSettingProfileSubtitle,
      ),
      (
        'languages',
        AppLocalizations.of(context).mockSettingLanguageOptions,
        Icons.language_outlined,
        mockLanguageOptionsSummary(context),
      ),
      (
        'security',
        AppLocalizations.of(context).mockSettingSecurityAccount,
        Icons.shield_outlined,
        AppLocalizations.of(context).mockSettingSecurityAccountSubtitle,
      ),
    ],
    AppLocalizations.of(context).mockSettingReadingDisplayGroup: [
      (
        'appearance',
        AppLocalizations.of(context).mockSettingAppearance,
        Icons.light_mode_outlined,
        AppLocalizations.of(context).mockSettingAppearanceSubtitle,
      ),
      (
        'readingPrefs',
        AppLocalizations.of(context).mockSettingReadingPreferences,
        Icons.menu_book_outlined,
        AppLocalizations.of(context).mockSettingReadingPreferencesSubtitle,
      ),
      (
        'speech',
        AppLocalizations.of(context).mockSettingSpeech,
        Icons.headphones_outlined,
        AppLocalizations.of(context).mockSettingSpeechSubtitle,
      ),
    ],
    AppLocalizations.of(context).mockSettingModelDeviceGroup: [
      (
        'queryPreferences',
        AppLocalizations.of(context).mockSettingQueryContext,
        Icons.chat_bubble_outline,
        AppLocalizations.of(context).mockSettingQueryContextSubtitle,
      ),
      (
        'model',
        AppLocalizations.of(context).mockSettingPersonalModel,
        Icons.auto_awesome_outlined,
        AppLocalizations.of(context).mockSettingPersonalModelSubtitle,
      ),
      (
        'usage',
        AppLocalizations.of(context).mockSettingModelUsage,
        Icons.grid_view_outlined,
        AppLocalizations.of(context).mockSettingModelUsageSubtitle,
      ),
      (
        'cache',
        AppLocalizations.of(context).mockSettingLocalCache,
        Icons.storage_outlined,
        AppLocalizations.of(context).mockSettingLocalCacheSubtitle,
      ),
      (
        'connection',
        AppLocalizations.of(context).mockSettingServiceConnection,
        Icons.language_outlined,
        AppLocalizations.of(context).mockSettingServiceConnectionSubtitle,
      ),
    ],
  };
  if (settingsUsePreviewAvatar(context)) return groups;
  const previewOnly = {'speech'};
  final canReadCredentials =
      sessionAuth(context)?.access?.allows('client.credential.read') ?? false;
  return {
    for (final group in groups.entries)
      group.key: [
        for (final item in group.value)
          if (!previewOnly.contains(item.$1) &&
              (canReadCredentials || !{'model', 'usage'}.contains(item.$1)))
            item,
      ],
  };
}

String mockSettingTitle(BuildContext context, String key) {
  for (final group in mockSettingGroups(context).values) {
    for (final item in group) {
      if (item.$1 == key) return item.$2;
    }
  }
  return AppLocalizations.of(context).mockSettingMyTitle;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.framed = true, super.key});

  final bool framed;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: _syncVisibility,
    onReturned: _syncVisibility,
  );
  CachedSettingsRepository? _repository;
  int? _scopeGeneration;
  final Set<SettingsGroup> _requested = {};
  bool _foreground = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageActivity.bind(context);
    final repository = SettingsRepositoryScope.of(context);
    if (identical(repository, _repository) && _scopeGeneration == repository.scopeGeneration) {
      _syncVisibility();
      return;
    }
    _repository = repository;
    _scopeGeneration = repository.scopeGeneration;
    _requested.clear();
    _syncVisibility(force: true);
  }

  Future<void> _refreshMissing(CachedSettingsRepository repository) async {
    final scope = repository.scopeGeneration;
    try {
      await repository.waitForReadiness?.call();
    } on Object {
      return;
    }
    if (!mounted ||
        !_foreground ||
        !_pageActivity.isCurrent ||
        !identical(repository, _repository) ||
        scope != repository.scopeGeneration) {
      return;
    }
    for (final group in [SettingsGroup.profile, SettingsGroup.studyProfile]) {
      if (_requested.contains(group) ||
          repository.snapshot(group) != null ||
          repository.status(group) == SettingsReadStatus.loading ||
          repository.status(group) == SettingsReadStatus.refreshing) {
        continue;
      }
      _requested.add(group);
      unawaited(repository.refresh(group));
    }
  }

  void _syncVisibility({bool force = false}) {
    final visible = _pageActivity.isCurrent;
    if (!force && visible == _active) return;
    _active = visible;
    if (!visible) return;
    final repository = _repository;
    if (repository == null) return;
    scheduleMicrotask(() => _refreshMissing(repository));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageActivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => settingsChrome(
    context: context,
    framed: widget.framed,
    location: settingsHome(context),
    title: AppLocalizations.of(context).mockSettingMyTitle,
    mobile: const MobileSettingsView(),
    desktop: const DesktopSettingsView(),
  );
}

Widget _settingsAvatar(BuildContext context, HarukaColors roles) {
  final repository = SettingsRepositoryScope.of(context);
  final auth = sessionAuth(context);
  final source = repository.source;
  if (!settingsUsePreviewAvatar(context) && auth != null && source is HttpSettingsSource) {
    return OwnerAvatarRow(api: source.api, repository: repository, auth: auth, badgeOnly: true);
  }
  return CircleAvatar(
    radius: 26,
    backgroundColor: roles.signal,
    child: Text(
      AppLocalizations.of(context).mockSettingAvatarGlyph,
      style: TextStyle(color: roles.onSignal),
    ),
  );
}

class MobileSettingsView extends StatelessWidget {
  const MobileSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = SettingsRepositoryScope.of(context).snapshot(SettingsGroup.profile);
    final roles = HarukaColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        HarukaSurface(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
            leading: _settingsAvatar(context, roles),
            title: Text(
              displayNameOrFallback(context, profile?.fields['display_name'] as String? ?? ''),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(settingsSectionPath(context, 'profile')),
          ),
        ),
        const SizedBox(height: 18),
        for (final group in [
          (
            AppLocalizations.of(context).mockSettingLearningPreferencesGroup,
            settingsUsePreviewAvatar(context)
                ? ['languages', 'appearance', 'readingPrefs', 'speech']
                : ['languages', 'appearance', 'readingPrefs'],
          ),
          (
            AppLocalizations.of(context).mockSettingModelDataGroup,
            settingsUsePreviewAvatar(context)
                ? ['queryPreferences', 'model', 'usage', 'cache']
                : [
                    'queryPreferences',
                    if (sessionAuth(context)?.access?.allows('client.credential.read') ??
                        false) ...[
                      'model',
                      'usage',
                    ],
                    'cache',
                  ],
          ),
          (
            AppLocalizations.of(context).mockSettingAccountUpdatesGroup,
            settingsUsePreviewAvatar(context)
                ? ['notifications', 'jobs', 'security']
                : [
                    if (sessionAuth(context)?.access?.allows('client.job.read') ?? false) 'jobs',
                    'security',
                  ],
          ),
          (AppLocalizations.of(context).mockSettingMoreGroup, ['connection']),
        ]) ...[
          Text(group.$1, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          HarukaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.$2.length; i++) ...[
                  _settingRow(context, group.$2[i]),
                  if (i < group.$2.length - 1) Divider(height: 1, color: scheme.outline),
                ],
              ],
            ),
          ),
          const SizedBox(height: 19),
        ],
      ],
    );
  }
}

Widget _settingRow(BuildContext context, String key) {
  final data = [for (final group in mockSettingGroups(context).values) ...group]
      .where((item) => item.$1 == key)
      .firstOrNull;
  final title =
      data?.$2 ??
      (key == 'notifications'
          ? AppLocalizations.of(context).mockSettingNotifications
          : AppLocalizations.of(context).mockSettingJobs);
  final subtitle =
      data?.$4 ??
      (key == 'notifications'
          ? AppLocalizations.of(context).mockSettingNotificationsSubtitle
          : AppLocalizations.of(context).mockSettingJobsSubtitle);
  final icon = data?.$3 ?? (key == 'notifications' ? Icons.notifications_none : Icons.schedule);
  return ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: () => context.push(
      key == 'notifications'
          ? AppRoutes.mockNotifications
          : key == 'jobs'
          ? settingsUsePreviewAvatar(context)
                ? AppRoutes.mockJobs
                : AppRoutes.jobs
          : settingsSectionPath(context, key),
    ),
  );
}

class DesktopSettingsView extends StatelessWidget {
  const DesktopSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = SettingsRepositoryScope.of(context).snapshot(SettingsGroup.profile);
    final roles = HarukaColors.of(context);
    final groups = mockSettingGroups(context).entries.toList();
    return ListView(
      children: [
        Text(
          AppLocalizations.of(context).mockSettingMyTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: HarukaLayout.pageMaxWidth),
            child: HarukaSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: _settingsAvatar(context, roles),
                title: Text(
                  displayNameOrFallback(context, profile?.fields['display_name'] as String? ?? ''),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: switch (mockLearningLevelSummary(context)) {
                  final summary? => Text(summary),
                  null => null,
                },
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(settingsSectionPath(context, 'profile')),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920 ? 3 : 2;
            final groupWidth = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 22,
              children: [
                for (final group in groups)
                  SizedBox(
                    width: groupWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.key, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        HarukaSurface(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < group.value.length; i++) ...[
                                SizedBox(
                                  height: 62,
                                  child: Center(
                                    child: ListTile(
                                      leading: Container(
                                        width: 39,
                                        height: 39,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: roles.selected,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          group.value[i].$3,
                                          color: Theme.of(context).colorScheme.primary,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(group.value[i].$2),
                                      trailing: const Icon(Icons.chevron_right, size: 18),
                                      onTap: () => context.push(
                                        settingsSectionPath(context, group.value[i].$1),
                                      ),
                                    ),
                                  ),
                                ),
                                if (i < group.value.length - 1) const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class SettingsDetailPage extends StatefulWidget {
  const SettingsDetailPage({required this.section, this.framed = true, super.key});
  final String section;
  final bool framed;

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  final queryBudget = TextEditingController();
  final serviceAddress = TextEditingController();
  bool initialized = false;
  int? _budgetScopeGeneration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final draft = PreviewStoreScope.of(context).settingsDraft;
    serviceAddress.text = draft.serviceAddress;
    initialized = true;
  }

  @override
  void dispose() {
    queryBudget.dispose();
    serviceAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.section == 'profile') return ProfileDetailPage(framed: widget.framed);
    final known = mockSettingGroups(context).values
        .any((group) => group.any((item) => item.$1 == widget.section));
    if (!known) {
      final message = Center(child: Text(AppLocalizations.of(context).notFoundDescription));
      return settingsChrome(
        context: context,
        framed: widget.framed,
        location: settingsSectionPath(context, widget.section),
        title: AppLocalizations.of(context).notFoundTitle,
        detail: true,
        onBack: () => context.go(settingsHome(context)),
        mobile: message,
        desktop: message,
      );
    }
    final title = mockSettingTitle(context, widget.section);
    final logic = SettingsLogic(
      context,
      PreviewStoreScope.of(context),
      PreviewSettingsCacheScope.of(context),
      SettingsRepositoryScope.of(context),
      queryBudget,
      serviceAddress,
    );
    final groups = switch (widget.section) {
      'languages' || 'goals' => {SettingsGroup.studyProfile},
      'appearance' ||
      'readingPrefs' ||
      'speech' ||
      'queryPreferences' => {SettingsGroup.preferences},
      'model' =>
        settingsUsePreviewAvatar(context) ? {SettingsGroup.preferences} : <SettingsGroup>{},
      _ => <SettingsGroup>{},
    };
    Widget frame(BuildContext context) {
      for (final group in groups) {
        hydrateSettingsFormDraft(logic.store, logic.settings, group);
      }
      if (widget.section == 'queryPreferences' &&
          (_budgetScopeGeneration != logic.settings.scopeGeneration ||
              queryBudget.text != logic.draft.queryBudgetText)) {
        queryBudget.text = logic.draft.queryBudgetText;
        _budgetScopeGeneration = logic.settings.scopeGeneration;
      }
      final canWrite =
          settingsUsePreviewAvatar(context) ||
          (sessionAuth(context)?.access?.allows('client.profile.update') ?? false);
      final canUseLanguage = widget.section != 'languages' || logic.languageDirectoryReady;
      final editable = groups.isEmpty || (canWrite && canUseLanguage);
      final notice = !canWrite ? '此账号仅可查看设置。' : '语言目录暂不可用。';
      final retry =
          canWrite &&
              !canUseLanguage &&
              (LanguageCapabilitiesScope.scopeOf(context)?.failed ?? false)
          ? LanguageCapabilitiesScope.scopeOf(context)?.retry
          : null;
      return settingsChrome(
        context: context,
        framed: widget.framed,
        location: settingsSectionPath(context, widget.section),
        title: title,
        detail: true,
        detailNotifications: false,
        desktopBackLabel: AppLocalizations.of(context).mockSettingMyTitle,
        onBack: () => context.go(settingsHome(context)),
        mobile: MobileSettingsDetail(
          section: widget.section,
          logic: logic,
          editable: editable,
          notice: notice,
          retry: retry,
        ),
        desktop: DesktopSettingsDetail(
          section: widget.section,
          title: title,
          logic: logic,
          editable: editable,
          notice: notice,
          retry: retry,
        ),
      );
    }

    return groups.isEmpty ? frame(context) : SettingsSnapshotGate(groups: groups, builder: frame);
  }
}

class MobileSettingsDetail extends StatelessWidget {
  const MobileSettingsDetail({
    required this.section,
    required this.logic,
    this.editable = true,
    this.notice = '',
    this.retry,
    super.key,
  });
  final String section;
  final SettingsLogic logic;
  final bool editable;
  final String notice;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 9, 20, 30),
    children: [
      if (!editable) _settingsEditNotice(context, notice, retry),
      AbsorbPointer(
        absorbing: !editable,
        child: _MobileSettingsContent(section: section, logic: logic),
      ),
    ],
  );
}

class DesktopSettingsDetail extends StatelessWidget {
  const DesktopSettingsDetail({
    required this.section,
    required this.title,
    required this.logic,
    this.editable = true,
    this.notice = '',
    this.retry,
    super.key,
  });
  final String section;
  final String title;
  final SettingsLogic logic;
  final bool editable;
  final String notice;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final group in mockSettingGroups(context).values)
        for (final item in group)
          if (item.$1 != 'security') item,
      for (final group in mockSettingGroups(context).values)
        for (final item in group)
          if (item.$1 == 'security') item,
    ];
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 190,
              child: HarukaSurface(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    for (final item in items)
                      TextButton.icon(
                        onPressed: () => context.go(settingsSectionPath(context, item.$1)),
                        icon: Icon(item.$3, size: 17),
                        label: Align(alignment: Alignment.centerLeft, child: Text(item.$2)),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(double.infinity, 43),
                          foregroundColor: section == item.$1
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          backgroundColor: section == item.$1
                              ? HarukaColors.of(context).selected
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 21),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: HarukaLayout.formMaxWidth),
                  child: SizedBox(
                    width: HarukaLayout.formMaxWidth,
                    child: Column(
                      children: [
                        if (!editable) _settingsEditNotice(context, notice, retry),
                        AbsorbPointer(
                          absorbing: !editable,
                          child: _DesktopSettingsContent(section: section, logic: logic),
                        ),
                      ],
                    ),
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

Widget _settingsEditNotice(BuildContext context, String notice, VoidCallback? retry) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Row(
    children: [
      Expanded(child: Text(notice)),
      if (retry != null)
        TextButton(onPressed: retry, child: Text(AppLocalizations.of(context).referenceRetry)),
    ],
  ),
);

class SettingsLogic {
  SettingsLogic(
    this.context,
    this.store,
    this.cache,
    this.settings,
    this.queryBudget,
    this.serviceAddress,
  );
  final BuildContext context;
  final PreviewFixtureStore store;
  final PreviewSettingsCacheAdapter cache;
  final CachedSettingsRepository settings;
  final TextEditingController queryBudget;
  final TextEditingController serviceAddress;

  AppLocalizations get l10n => AppLocalizations.of(context);
  SettingsDraft get draft => store.settingsDraft;
  String get themeMode =>
      settings.snapshot(SettingsGroup.preferences)?.fields['theme_mode'] as String? ?? 'system';
  bool get reducedMotion =>
      settings.snapshot(SettingsGroup.preferences)?.fields['reduce_motion'] == 'on';
  LanguageCapabilities? get languageCapabilities => LanguageCapabilitiesScope.maybeOf(context);
  bool get languageDirectoryReady =>
      settingsUsePreviewAvatar(context) || languageCapabilities != null;
  List<String> get nativeOptions => settingsUsePreviewAvatar(context)
      ? const ['zh-Hans', 'ja', 'en']
      : languageCapabilities?.codes((item) => item.native) ?? const [];
  List<String> get explanationOptions => settingsUsePreviewAvatar(context)
      ? const ['zh-Hans', 'ja', 'en']
      : languageCapabilities?.codes((item) => item.explanation) ?? const [];
  List<String> get learningOptions => settingsUsePreviewAvatar(context)
      ? const ['ja', 'en']
      : languageCapabilities?.codes((item) => item.learning) ?? const [];

  void edit(void Function(SettingsDraft) change) => store.editSettingsDraft(change);

  void selectTargetLanguage(String language) =>
      edit((_) => selectSettingsTargetLanguage(store, settings, language));

  void saved() =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockSettingSettingsSaved)));

  void checkModel() =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockSettingModelConfigChecked)));

  Future<void> viewSession() => showHarukaDialog<void>(
    context: context,
    animationStyle: HarukaMotion.dialogStyle(context, reducedMotion: store.reducedMotion),
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.mockSettingCurrentSession),
      content: Text(l10n.mockSettingSessionActive),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.mockSettingClose),
        ),
      ],
    ),
  );

  void openSessions() {
    if (!settingsUsePreviewAvatar(context)) {
      unawaited(showDeviceSessionsDialog(context));
      return;
    }
    unawaited(viewSession());
  }

  Future<void> signOut() async {
    if (settingsUsePreviewAvatar(context)) {
      context.go(AppRoutes.mockLogin);
      return;
    }
    final router = GoRouter.of(context);
    final auth = sessionAuth(context);
    if (auth == null) return;
    final epoch = auth.actionEpoch;
    final sessionRef = auth.access?.sessionRef;
    final operationId = newRequestId();
    var confirmed = true;
    try {
      final telemetry = ProviderScope.containerOf(context, listen: false).read(telemetryProvider);
      telemetry?.track('auth.logout.requested', operationId: operationId);
      if (telemetry != null) unawaited(telemetry.flush());
      await auth.signOut(operationId: operationId);
    } on Object {
      confirmed = false;
    }
    if (sessionRef != null && auth.wasLocallySignedOutBy(epoch, sessionRef)) {
      router.go(confirmed ? AppRoutes.login : AppRoutes.signedOutLocally);
    }
  }

  Future<void> _save(SettingsGroup group, Map<String, Object?> fields) async {
    if (!settingsUsePreviewAvatar(context) &&
        !(sessionAuth(context)?.access?.allows('client.profile.update') ?? false)) {
      return;
    }
    if (group == SettingsGroup.studyProfile && !languageDirectoryReady) return;
    if (settingsFormDraftHasConflict(store, group)) {
      _showRevisionConflict(group);
      return;
    }
    try {
      await settings.save(group, fields);
      if (context.mounted) {
        trackSettingsMutation(context, switch (group) {
          SettingsGroup.profile => 'profile.updated',
          SettingsGroup.studyProfile => 'study_profile.updated',
          SettingsGroup.preferences => 'settings.updated',
        });
        saved();
      }
    } on SettingsRevisionConflict {
      await settings.refresh(group, force: true);
      if (context.mounted) _showRevisionConflict(group);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.apiUnknownError)));
      }
    }
  }

  void _showRevisionConflict(SettingsGroup group) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.apiRevisionConflict),
          action: SnackBarAction(
            label: l10n.referenceRetry,
            onPressed: () => rebaseSettingsFormDraft(store, settings, group),
          ),
        ),
      );
  }

  List<Map<String, Object?>> _savedTargets() {
    final rows = settings.snapshot(SettingsGroup.studyProfile)?.fields['target_languages'] as List?;
    if (rows == null) return const [];
    return [for (final row in rows) Map<String, Object?>.of((row as Map).cast<String, Object?>())];
  }

  Future<void> saveLanguage() {
    final byTag = {for (final row in _savedTargets()) row['language_tag'] as String: row};
    final targets = <Map<String, Object?>>[
      for (final language in draft.learningLanguages)
        {
          'language_tag': language,
          'self_assessed_level': language == draft.activeLanguage
              ? switch (draft.learningLevel) {
                  'unset' => 'unknown',
                  'basic' => 'elementary',
                  final String level => level,
                }
              : byTag[language]?['self_assessed_level'] ?? 'unknown',
          'learning_goals': byTag[language]?['learning_goals'] ?? <String>[],
        },
    ];
    return _save(SettingsGroup.studyProfile, {
      'native_languages': draft.nativeLanguages.toList(),
      'target_languages': targets,
      'active_target_language': draft.activeLanguage,
      'explanation_language': draft.explanationLanguage,
    });
  }

  Future<void> saveGoals() {
    final active = draft.activeLanguage;
    if (active.isEmpty) return Future.value();
    final targets = [
      for (final row in _savedTargets())
        if (row['language_tag'] == active)
          {...row, 'learning_goals': draft.learningGoals.toList()}
        else
          row,
    ];
    if (!targets.any((row) => row['language_tag'] == active)) {
      targets.add({
        'language_tag': active,
        'self_assessed_level': switch (draft.learningLevel) {
          'unset' => 'unknown',
          'basic' => 'elementary',
          final String level => level,
        },
        'learning_goals': draft.learningGoals.toList(),
      });
    }
    return _save(SettingsGroup.studyProfile, {
      'target_languages': targets,
      'active_target_language': active,
    });
  }

  Future<void> saveReading() => _save(SettingsGroup.preferences, {
    'reading_font_family': draft.readingFont,
    'reading_font_size': draft.readingFontSize,
    'reading_line_height': draft.readingLineHeight,
    'reading_theme': draft.readingTheme,
  });

  Future<void> saveModel() => _save(SettingsGroup.preferences, {
    'model_provider': draft.modelProvider,
    'text_model': draft.textModel,
    'vision_model': draft.visionModel,
  });

  Future<void> saveSpeech() => _save(SettingsGroup.preferences, {
    'tts_model': draft.ttsModel,
    'speech_voice': draft.speechVoice,
    'speech_format': draft.speechFormat,
    'speech_style': draft.speechStyle,
    'playback_speed': draft.speechSpeed,
  });

  Future<void> saveAppearance(String themeMode, bool reducedMotion) => _save(
    SettingsGroup.preferences,
    {'theme_mode': themeMode, 'reduce_motion': reducedMotion ? 'on' : 'system'},
  );

  Future<void> saveCache() async {
    final textMb = draft.textLimitMb;
    final audioMb = draft.audioLimitMb;
    final succeeded = await cache.saveLimits(textMb: textMb, audioMb: audioMb);
    if (!context.mounted) return;
    if (succeeded) {
      store.saveCacheLimits(textMb, audioMb);
      saved();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockSettingCacheOperationFailed)));
    }
  }

  Future<void> saveQuery() async {
    final parsed = int.tryParse(queryBudget.text.trim());
    if (parsed == null || parsed < 1000 || parsed > 64000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockSettingBudgetInvalid)));
      return;
    }
    edit((draft) {
      draft.queryContextBudget = parsed;
      draft.queryBudgetText = queryBudget.text.trim();
    });
    await _save(SettingsGroup.preferences, {'query_context_budget_tokens': parsed});
  }

  void setBudget(int value) {
    queryBudget.text = value.toString();
    edit((draft) {
      draft.queryContextBudget = value;
      draft.queryBudgetText = queryBudget.text;
    });
  }

  void probeAddress() {
    edit((draft) => draft.serviceAddress = serviceAddress.text);
    store.validateServiceAddress();
  }

  Future<void> clearCache() async {
    final confirmed = await showHarukaDialog<bool>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context, reducedMotion: store.reducedMotion),
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(l10n.mockSettingClearCacheConfirmTitle)),
            IconButton(
              tooltip: l10n.mockSettingClose,
              onPressed: () => Navigator.pop(dialogContext, false),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(width: 480, child: Text(l10n.mockSettingClearCacheConfirmMessage)),
        actionsAlignment: MainAxisAlignment.start,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.mockSettingCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.errorContainer,
              foregroundColor: Theme.of(dialogContext).colorScheme.onErrorContainer,
            ),
            child: Text(l10n.mockSettingClear),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final result = await cache.clear();
      if (!context.mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.mockSettingCacheOperationFailed)));
      } else {
        store.clearLocalCache();
        final message = result.pendingAudio == 0
            ? l10n.mockSettingCacheCleared
            : l10n.mockSettingCacheClearPartial(result.pendingAudio);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> configureKey() async {
    var key = '';
    String? error;
    final configured = await showHarukaDialog<bool>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context, reducedMotion: store.reducedMotion),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.mockSettingConfigureKey),
          content: TextField(
            onChanged: (value) => key = value,
            obscureText: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.mockSettingPersonalApiKey,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.mockSettingCancel),
            ),
            FilledButton(
              onPressed: () {
                if (key.trim().isEmpty) {
                  setDialogState(() => error = l10n.mockSettingKeyRequired);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(l10n.mockSettingSaveKey),
            ),
          ],
        ),
      ),
    );
    if (configured == true && context.mounted) {
      store.setPersonalApiKeyConfigured(true);
      saved();
    }
  }

  Future<void> changePassword() async {
    if (!settingsUsePreviewAvatar(context)) {
      await showPasswordChangeDialog(context);
      return;
    }
    var current = '';
    var next = '';
    var confirm = '';
    String? error;
    final changed = await showHarukaDialog<bool>(
      context: context,
      animationStyle: HarukaMotion.dialogStyle(context, reducedMotion: store.reducedMotion),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.mockSettingChangePassword),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => current = value,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l10n.mockSettingCurrentPassword),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => next = value,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l10n.mockSettingNewPassword),
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => confirm = value,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.mockSettingConfirmPassword,
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.mockSettingCancel),
            ),
            FilledButton(
              onPressed: () {
                if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
                  setDialogState(() => error = l10n.mockSettingPasswordRequired);
                  return;
                }
                if (next.length < 8) {
                  setDialogState(() => error = l10n.mockSettingPasswordTooShort);
                  return;
                }
                if (next != confirm) {
                  setDialogState(() => error = l10n.mockSettingPasswordMismatch);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(l10n.mockSettingChangePassword),
            ),
          ],
        ),
      ),
    );
    if (changed == true && context.mounted) {
      store.markPasswordChanged();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockSettingPasswordUpdated)));
    }
  }

  String languageLabel(String value) => value.isEmpty
      ? '未填写'
      : (!settingsUsePreviewAvatar(context) && languageCapabilities != null)
      ? languageCapabilities!.label(value)
      : switch (value) {
          'ja' => l10n.mockSettingJapanese,
          'en' => l10n.mockSettingEnglish,
          _ => l10n.mockSettingSimplifiedChinese,
        };

  String themeLabel(String value) => switch (value) {
    'light' => l10n.mockSettingLightMode,
    'dark' => l10n.mockSettingDarkMode,
    'sepia' => l10n.mockSettingSepiaTheme,
    _ => l10n.mockSettingFollowSystem,
  };

  String levelLabel(String value) => switch (value) {
    'beginner' => l10n.mockSettingLevelBeginner,
    'basic' => l10n.mockSettingLevelBasic,
    'intermediate' => l10n.mockSettingLevelIntermediate,
    'advanced' => l10n.mockSettingLevelAdvanced,
    _ => l10n.mockSettingLevelUnset,
  };

  String goalLabel(String value) => switch (value) {
    'reading' => l10n.mockSettingGoalReading,
    'textbook' => l10n.mockSettingGoalTextbook,
    'exam' => l10n.mockSettingGoalExam,
    'listening' => l10n.mockSettingGoalListening,
    'speaking' => l10n.mockSettingGoalSpeaking,
    'writing' => l10n.mockSettingGoalWriting,
    'vocabulary' => l10n.mockSettingGoalVocabulary,
    _ => l10n.mockSettingGoalGrammar,
  };
}

Widget _settingSelect(
  String label,
  String value,
  List<String> choices,
  String Function(String) text,
  ValueChanged<String> onChanged, {
  bool enabled = true,
}) => DropdownButtonFormField<String>(
  key: ValueKey('$label:$value'),
  initialValue: choices.contains(value) ? value : null,
  isExpanded: true,
  decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  items: [for (final choice in choices) DropdownMenuItem(value: choice, child: Text(text(choice)))],
  onChanged: enabled && choices.isNotEmpty
      ? (selected) {
          if (selected != null) onChanged(selected);
        }
      : null,
);

Widget _settingChecks(
  List<String> values,
  Set<String> selected,
  String Function(String) label,
  ValueChanged<String> onToggle,
) => Column(
  children: [
    for (final value in values)
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: selected.contains(value),
        title: Text(label(value)),
        onChanged: (_) => onToggle(value),
      ),
  ],
);

Widget _settingCard(BuildContext context, String title, List<Widget> children) => HarukaSurface(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 13),
      ...children,
    ],
  ),
);

Widget _settingAction(String title, VoidCallback? onPressed) => SizedBox(
  width: double.infinity,
  child: FilledButton(onPressed: onPressed, child: Text(title)),
);

Widget _readingPreview(BuildContext context, SettingsLogic logic) {
  final scheme = Theme.of(context).colorScheme;
  final dark = logic.draft.readingTheme == 'dark';
  final background = switch (logic.draft.readingTheme) {
    'dark' => scheme.inverseSurface,
    'sepia' => HarukaColors.of(context).selected,
    _ => scheme.surfaceContainerLow,
  };
  final foreground = dark ? scheme.onInverseSurface : scheme.onSurface;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
    child: Text(
      logic.l10n.mockSettingReadingPreviewSentence,
      style: TextStyle(
        color: foreground,
        fontSize: logic.draft.readingFontSize.toDouble(),
        height: logic.draft.readingLineHeight,
        fontFamily: logic.draft.readingFont == 'serif' ? 'Yu Mincho' : 'NotoSansJP',
        fontFamilyFallback: const ['NotoSansJP'],
      ),
    ),
  );
}

Widget _queryInput(SettingsLogic logic) => TextField(
  controller: logic.queryBudget,
  keyboardType: TextInputType.number,
  decoration: InputDecoration(
    labelText: logic.l10n.mockSettingContextBudget,
    border: const OutlineInputBorder(),
  ),
  onChanged: (value) => logic.edit((draft) => draft.queryBudgetText = value),
);

Widget _queryPresets(SettingsLogic logic) => Wrap(
  spacing: 8,
  children: [
    for (final amount in [5000, 10000, 20000])
      ChoiceChip(
        label: Text(amount.toString()),
        selected: logic.queryBudget.text == amount.toString(),
        onSelected: (_) => logic.setBudget(amount),
      ),
  ],
);

Widget _usagePeriods(SettingsLogic logic) => SegmentedButton<int>(
  segments: [
    ButtonSegment(value: 7, label: Text(logic.l10n.mockSettingLastSevenDays)),
    ButtonSegment(value: 30, label: Text(logic.l10n.mockSettingLastThirtyDays)),
    ButtonSegment(value: 90, label: Text(logic.l10n.mockSettingLastNinetyDays)),
  ],
  selected: {logic.draft.usageDays},
  onSelectionChanged: (value) => logic.edit((draft) => draft.usageDays = value.first),
);

(int, int, int) _usageValues(int days) => switch (days) {
  7 => (4, 1, 1),
  90 => (28, 5, 6),
  _ => (12, 2, 3),
};

Widget _usageStat(BuildContext context, String value, String label) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(value, style: Theme.of(context).textTheme.headlineSmall),
    Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ],
);

Widget _modelCapability(BuildContext context, IconData icon, String title, String value) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.outline),
    ),
    child: Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(value, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _speedControl(BuildContext context, SettingsLogic logic) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(logic.l10n.mockSettingPlaybackSpeed),
    Row(
      children: [
        Expanded(
          child: Slider(
            value: logic.draft.speechSpeed,
            min: .7,
            max: 1.5,
            divisions: 8,
            onChanged: (value) =>
                logic.edit((draft) => draft.speechSpeed = double.parse(value.toStringAsFixed(1))),
          ),
        ),
        Text(logic.l10n.mockSettingPlaybackRate(logic.draft.speechSpeed.toStringAsFixed(1))),
      ],
    ),
  ],
);

Widget _cacheLimits(SettingsLogic logic) => Column(
  children: [
    _settingSelect(
      logic.l10n.mockSettingTextCacheLimit,
      logic.draft.textLimitMb.toString(),
      ['50', '100', '250'],
      (value) => logic.l10n.mockSettingMegabytes(value),
      (value) => logic.edit((draft) => draft.textLimitMb = int.parse(value)),
      enabled: logic.cache.ready && !logic.cache.busy,
    ),
    const SizedBox(height: 12),
    _settingSelect(
      logic.l10n.mockSettingAudioCacheLimit,
      logic.draft.audioLimitMb.toString(),
      ['250', '500', '1000', '2000'],
      (value) => logic.l10n.mockSettingMegabytes(value),
      (value) => logic.edit((draft) => draft.audioLimitMb = int.parse(value)),
      enabled: logic.cache.ready && !logic.cache.busy,
    ),
  ],
);

Widget _localCacheCounts(SettingsLogic logic) {
  if (logic.cache.blockingReason == 'cache_update_required') {
    return Text(logic.l10n.mockSettingCacheUpdateRequired);
  }
  if (logic.cache.blockingReason == 'cache_writer_unavailable') {
    return Text(logic.l10n.mockSettingCacheWriterUnavailable);
  }
  final usage = logic.cache.usage;
  if (usage != null) {
    return Text(logic.l10n.mockSettingCacheCounts(usage.textEntries, usage.audioAssets));
  }
  if (logic.cache.lastError != null) {
    return TextButton.icon(
      onPressed: logic.cache.retry,
      icon: const Icon(Icons.refresh),
      label: Text(logic.l10n.mockSettingCacheOperationFailed),
    );
  }
  return const Center(child: CircularProgressIndicator());
}

class _MobileSettingsContent extends StatelessWidget {
  const _MobileSettingsContent({required this.section, required this.logic});
  final String section;
  final SettingsLogic logic;

  @override
  Widget build(BuildContext context) => switch (section) {
    'languages' => _languages(context),
    'appearance' => _appearance(context),
    'readingPrefs' => _reading(context),
    'queryPreferences' => _query(context),
    'model' =>
      settingsUsePreviewAvatar(context) ? _model(context) : const ModelConfigurationContent(),
    'speech' => _speech(context),
    'usage' => settingsUsePreviewAvatar(context) ? _usage(context) : const ModelUsageContent(),
    'cache' => _cache(context),
    'connection' => _connection(context),
    'security' => _security(context),
    _ => const SizedBox.shrink(),
  };

  Widget _stack(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final card in cards) ...[card, const SizedBox(height: 14)],
    ],
  );

  void _toggleNative(String value) => logic.edit((draft) {
    draft.nativeLanguages.contains(value)
        ? draft.nativeLanguages.remove(value)
        : draft.nativeLanguages.add(value);
  });

  void _toggleTarget(String value) {
    logic.edit((draft) {
      if (draft.learningLanguages.contains(value)) {
        if (draft.learningLanguages.length > 1) draft.learningLanguages.remove(value);
      } else {
        draft.learningLanguages.add(value);
      }
    });
    if (!logic.draft.learningLanguages.contains(logic.draft.activeLanguage)) {
      logic.selectTargetLanguage(logic.draft.learningLanguages.first);
    }
  }

  void _toggleGoal(String value) => logic.edit((draft) {
    draft.learningGoals.contains(value)
        ? draft.learningGoals.remove(value)
        : draft.learningGoals.add(value);
  });

  Widget _languages(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingInterfaceLanguage, [
      _settingSelect(
        logic.l10n.mockSettingInterfaceLanguage,
        'zh-Hans',
        ['zh-Hans'],
        logic.languageLabel,
        (_) {},
        enabled: false,
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingNativeLanguages, [
      _settingChecks(
        logic.nativeOptions,
        logic.draft.nativeLanguages,
        logic.languageLabel,
        _toggleNative,
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingExplanationLanguage, [
      _settingSelect(
        logic.l10n.mockSettingExplanationLanguage,
        logic.draft.explanationLanguage,
        ['', ...logic.explanationOptions],
        logic.languageLabel,
        (value) => logic.edit((draft) => draft.explanationLanguage = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingTargetLanguages, [
      _settingChecks(
        logic.learningOptions,
        logic.draft.learningLanguages,
        logic.languageLabel,
        _toggleTarget,
      ),
      const SizedBox(height: 12),
      _settingSelect(
        logic.l10n.mockSettingCurrentLearningLanguage,
        logic.draft.activeLanguage,
        ['', ...logic.draft.learningLanguages],
        logic.languageLabel,
        logic.selectTargetLanguage,
      ),
      const SizedBox(height: 12),
      _settingSelect(
        logic.l10n.mockSettingLearningLevel,
        logic.draft.learningLevel,
        ['unset', 'beginner', 'basic', 'intermediate', 'advanced'],
        logic.levelLabel,
        (value) => logic.edit((draft) => draft.learningLevel = value),
      ),
      const SizedBox(height: 14),
      _settingAction(logic.l10n.mockSettingSaveLanguageOptions, logic.saveLanguage),
    ]),
    _settingCard(context, logic.l10n.mockSettingLearningGoals, [
      _settingChecks(
        [
          'reading',
          'textbook',
          'exam',
          'listening',
          'speaking',
          'writing',
          'vocabulary',
          'grammar',
        ],
        logic.draft.learningGoals,
        logic.goalLabel,
        _toggleGoal,
      ),
      const SizedBox(height: 12),
      _settingAction(logic.l10n.mockSettingSaveGoals, logic.saveGoals),
    ]),
  ]);

  Widget _appearance(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingTheme, [
      _settingSelect(
        logic.l10n.mockSettingTheme,
        logic.themeMode,
        ['system', 'light', 'dark'],
        logic.themeLabel,
        (value) => logic.saveAppearance(value, logic.reducedMotion),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingReduceMotion, [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(logic.l10n.mockSettingReduceMotion),
        value: logic.reducedMotion,
        onChanged: (value) => logic.saveAppearance(logic.themeMode, value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingReadingPreview, [_readingPreview(context, logic)]),
  ]);

  Widget _reading(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingReadingFont, [
      _settingSelect(
        logic.l10n.mockSettingReadingFont,
        logic.draft.readingFont,
        ['serif', 'sans'],
        (value) =>
            value == 'serif' ? logic.l10n.mockSettingSerifFont : logic.l10n.mockSettingSansFont,
        (value) => logic.edit((draft) => draft.readingFont = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingFontSize, [
      Text('${logic.draft.readingFontSize}'),
      Slider(
        value: logic.draft.readingFontSize.toDouble(),
        min: 16,
        max: 24,
        divisions: 8,
        onChanged: (value) => logic.edit((draft) => draft.readingFontSize = value.round()),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingLineHeight, [
      Text(logic.draft.readingLineHeight.toStringAsFixed(1)),
      Slider(
        value: logic.draft.readingLineHeight,
        min: 1.6,
        max: 2.4,
        divisions: 8,
        onChanged: (value) =>
            logic.edit((draft) => draft.readingLineHeight = double.parse(value.toStringAsFixed(1))),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingReadingTheme, [
      _settingSelect(
        logic.l10n.mockSettingReadingTheme,
        logic.draft.readingTheme,
        ['light', 'dark', 'sepia'],
        logic.themeLabel,
        (value) => logic.edit((draft) => draft.readingTheme = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingReadingPreview, [
      _readingPreview(context, logic),
      const SizedBox(height: 14),
      _settingAction(logic.l10n.mockSettingSaveReading, logic.saveReading),
    ]),
  ]);

  Widget _query(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingQueryContext, [
      _queryInput(logic),
      const SizedBox(height: 12),
      _queryPresets(logic),
      const SizedBox(height: 16),
      _settingAction(logic.l10n.mockSettingSaveQuery, logic.saveQuery),
    ]),
  ]);

  Widget _model(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingProvider, [
      _settingSelect(
        logic.l10n.mockSettingProvider,
        logic.draft.modelProvider,
        ['openrouter', 'gemini'],
        (value) =>
            value == 'gemini' ? logic.l10n.mockSettingGemini : logic.l10n.mockSettingOpenRouter,
        (value) => logic.edit((draft) => draft.modelProvider = value),
      ),
      const SizedBox(height: 14),
      Text(
        logic.store.hasPersonalApiKey
            ? logic.l10n.mockSettingKeyConfigured
            : logic.l10n.mockSettingKeyUnconfigured,
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: logic.configureKey,
        child: Text(logic.l10n.mockSettingConfigureKey),
      ),
      if (logic.store.hasPersonalApiKey)
        TextButton(
          onPressed: () => logic.store.setPersonalApiKeyConfigured(false),
          child: Text(logic.l10n.mockSettingRemoveKey),
        ),
    ]),
    _settingCard(context, logic.l10n.mockSettingPersonalModel, [
      _modelCapability(
        context,
        Icons.text_fields,
        logic.l10n.mockSettingTextCapability,
        logic.l10n.mockSettingDefaultModel,
      ),
      const SizedBox(height: 10),
      _modelCapability(
        context,
        Icons.visibility_outlined,
        logic.l10n.mockSettingVisionCapability,
        logic.l10n.mockSettingDefaultModel,
      ),
      const SizedBox(height: 10),
      _modelCapability(
        context,
        Icons.graphic_eq,
        logic.l10n.mockSettingSpeechCapability,
        logic.l10n.mockSettingDefaultModel,
      ),
      const SizedBox(height: 14),
      _settingAction(logic.l10n.mockSettingSaveModel, logic.saveModel),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: logic.store.hasPersonalApiKey ? logic.checkModel : null,
        child: Text(logic.l10n.mockSettingTestTextModel),
      ),
    ]),
  ]);

  Widget _speech(BuildContext context) => _stack([
    _settingCard(context, logic.l10n.mockSettingSpeechModel, [
      _settingSelect(
        logic.l10n.mockSettingSpeechModel,
        logic.draft.ttsModel,
        ['gemini', 'openrouterDedicated', 'openrouterAudio'],
        (value) => switch (value) {
          'openrouterDedicated' => logic.l10n.mockSettingOpenRouterDedicated,
          'openrouterAudio' => logic.l10n.mockSettingOpenRouterAudio,
          _ => logic.l10n.mockSettingGeminiNatural,
        },
        (value) => logic.edit((draft) => draft.ttsModel = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingDefaultVoice, [
      _settingSelect(
        logic.l10n.mockSettingDefaultVoice,
        logic.draft.speechVoice,
        ['japaneseClear', 'englishNatural'],
        (value) => value == 'japaneseClear'
            ? logic.l10n.mockSettingJapaneseClear
            : logic.l10n.mockSettingEnglishNatural,
        (value) => logic.edit((draft) => draft.speechVoice = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingAudioFormat, [
      _settingSelect(
        logic.l10n.mockSettingAudioFormat,
        logic.draft.speechFormat,
        ['wav'],
        (_) => logic.l10n.mockSettingAudioWav,
        (value) => logic.edit((draft) => draft.speechFormat = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingVoiceStyle, [
      _settingSelect(
        logic.l10n.mockSettingVoiceStyle,
        logic.draft.speechStyle,
        ['natural', 'soft'],
        (value) =>
            value == 'soft' ? logic.l10n.mockSettingSoftStyle : logic.l10n.mockSettingNaturalStyle,
        (value) => logic.edit((draft) => draft.speechStyle = value),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingPlaybackSpeed, [
      _speedControl(context, logic),
      const SizedBox(height: 14),
      _settingAction(logic.l10n.mockSettingSaveSpeech, logic.saveSpeech),
    ]),
  ]);

  Widget _usage(BuildContext context) {
    final (calls, reuse, unknown) = _usageValues(logic.draft.usageDays);
    return _stack([
      _settingCard(context, logic.l10n.mockSettingModelUsage, [_usagePeriods(logic)]),
      _settingCard(context, logic.l10n.mockSettingCallCount, [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _usageStat(context, '$calls', logic.l10n.mockSettingCallCount),
            _usageStat(context, '$reuse', logic.l10n.mockSettingReuseCount),
            _usageStat(context, '$unknown', logic.l10n.mockSettingUnknownUsage),
          ],
        ),
      ]),
      _settingCard(context, logic.l10n.mockSettingTextCapability, [
        _usageStat(context, '${calls - unknown - 1}', logic.l10n.mockSettingCallCount),
        const Divider(),
        Text('${logic.l10n.mockSettingInputTokens}: 12,480'),
        Text('${logic.l10n.mockSettingOutputTokens}: 3,240'),
        Text('${logic.l10n.mockSettingCacheReadTokens}: 1,800'),
      ]),
      _settingCard(context, logic.l10n.mockSettingSpeechCapability, [
        _usageStat(context, '$unknown', logic.l10n.mockSettingCallCount),
        Text(logic.l10n.mockSettingUnknownUsage),
      ]),
      _settingCard(context, logic.l10n.mockSettingVisionCapability, [
        _usageStat(context, '1', logic.l10n.mockSettingCallCount),
        Text('${logic.l10n.mockSettingInputTokens}: 1,520'),
        Text('${logic.l10n.mockSettingOutputTokens}: 480'),
      ]),
    ]);
  }

  Widget _cache(BuildContext context) {
    if (!settingsUsePreviewAvatar(context)) {
      return _stack([
        _settingCard(context, logic.l10n.mockSettingLocalAvailable, [
          _localCacheCounts(logic),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey(UiTestIds.settingsCacheClear),
            onPressed: logic.cache.ready && !logic.cache.busy ? logic.clearCache : null,
            icon: const Icon(Icons.delete_outline),
            label: Text(logic.l10n.mockSettingClearAccountLocalCache),
          ),
        ]),
      ]);
    }
    return _stack([
      _settingCard(context, logic.l10n.mockSettingLocalAvailable, [
        _localCacheCounts(logic),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: logic.cache.ready && !logic.cache.busy ? logic.clearCache : null,
            style: FilledButton.styleFrom(
              backgroundColor: HarukaColors.of(context).bookPeach,
              foregroundColor: HarukaColors.of(context).danger,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(logic.l10n.mockSettingClearAccountLocalCache),
          ),
        ),
      ]),
      _settingCard(context, logic.l10n.mockSettingSavedResults, [
        Text(
          logic.l10n.mockSettingCacheCounts(
            logic.store.savedExplanationCount,
            logic.store.savedAudioCount,
          ),
        ),
      ]),
      _settingCard(context, logic.l10n.mockSettingLocalSpace, [
        _cacheLimits(logic),
        const SizedBox(height: 15),
        _settingAction(
          logic.l10n.mockSettingSaveCacheLimits,
          logic.cache.ready && !logic.cache.busy ? logic.saveCache : null,
        ),
      ]),
    ]);
  }

  Widget _connection(BuildContext context) {
    final live = ServiceEndpointScope.maybeOf(context);
    if (live != null) {
      return _stack([
        _settingCard(context, logic.l10n.mockSettingServiceConnection, [
          ServiceEndpointForm(
            controller: live,
            onAdopted: () {
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ]),
      ]);
    }
    return _stack([
      _settingCard(context, logic.l10n.mockSettingServiceConnection, [
        TextField(
          controller: logic.serviceAddress,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: logic.l10n.mockSettingServiceAddress,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => logic.edit((draft) => draft.serviceAddress = value),
        ),
        const SizedBox(height: 15),
        _settingAction(logic.l10n.mockSettingProbeConnection, logic.probeAddress),
        const SizedBox(height: 10),
        if (logic.store.serviceProbeAttempted)
          Text(
            logic.store.serviceAddressValidated
                ? logic.l10n.mockSettingAddressValid
                : logic.l10n.mockSettingAddressInvalid,
          ),
      ]),
    ]);
  }

  Widget _security(BuildContext context) => _stack([
    if (!settingsUsePreviewAvatar(context)) const AccountIdentitySummary(compact: true),
    _settingCard(context, logic.l10n.mockSettingProfile, [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(logic.l10n.mockSettingProfile),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(settingsSectionPath(context, 'profile')),
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingChangePassword, [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(logic.l10n.mockSettingChangePassword),
        trailing: const Icon(Icons.chevron_right),
        onTap: logic.changePassword,
      ),
    ]),
    _settingCard(context, logic.l10n.mockSettingCurrentSession, [
      Text(logic.l10n.mockSettingSessionActive),
      const SizedBox(height: 13),
      OutlinedButton(onPressed: logic.openSessions, child: Text(logic.l10n.mockSettingViewSession)),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: logic.signOut, child: Text(logic.l10n.mockSettingLogout)),
    ]),
  ]);
}

class _DesktopSettingsContent extends StatelessWidget {
  const _DesktopSettingsContent({required this.section, required this.logic});
  final String section;
  final SettingsLogic logic;

  Widget _panel(BuildContext context, String title, List<Widget> children) => HarukaSurface(
    padding: const EdgeInsets.all(25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section != 'languages' &&
            section != 'cache' &&
            title != mockSettingTitle(context, section)) ...[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 22),
        ],
        ...children,
      ],
    ),
  );

  Widget _button(String label, VoidCallback? onPressed, {bool fillWidth = false}) => SizedBox(
    width: fillWidth ? double.infinity : null,
    child: FilledButton(onPressed: onPressed, child: Text(label)),
  );

  Widget _desktopChecks(
    BuildContext context,
    List<String> choices,
    Set<String> selected,
    String Function(String) label,
    ValueChanged<String> toggle,
  ) => Wrap(
    spacing: 12,
    runSpacing: 2,
    children: [
      for (final choice in choices)
        SizedBox(
          width: 170,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(label(choice)),
            value: selected.contains(choice),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (_) => toggle(choice),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => switch (section) {
    'languages' => _languages(context),
    'appearance' => _appearance(context),
    'readingPrefs' => _reading(context),
    'queryPreferences' => _query(context),
    'model' =>
      settingsUsePreviewAvatar(context)
          ? _model(context)
          : const ModelConfigurationContent(wide: true),
    'speech' => _speech(context),
    'usage' =>
      settingsUsePreviewAvatar(context) ? _usage(context) : const ModelUsageContent(wide: true),
    'cache' => _cache(context),
    'connection' => _connection(context),
    'security' => _security(context),
    _ => const SizedBox.shrink(),
  };

  Widget _languages(BuildContext context) =>
      _panel(context, logic.l10n.mockSettingLanguageOptions, [
        _settingSelect(
          logic.l10n.mockSettingInterfaceLanguage,
          'zh-Hans',
          ['zh-Hans'],
          logic.languageLabel,
          (_) {},
          enabled: false,
        ),
        const SizedBox(height: 20),
        Text(logic.l10n.mockSettingNativeLanguages, style: Theme.of(context).textTheme.titleMedium),
        _desktopChecks(
          context,
          logic.nativeOptions,
          logic.draft.nativeLanguages,
          logic.languageLabel,
          (value) => logic.edit(
            (draft) => draft.nativeLanguages.contains(value)
                ? draft.nativeLanguages.remove(value)
                : draft.nativeLanguages.add(value),
          ),
        ),
        const SizedBox(height: 20),
        _settingSelect(
          logic.l10n.mockSettingExplanationLanguage,
          logic.draft.explanationLanguage,
          ['', ...logic.explanationOptions],
          logic.languageLabel,
          (value) => logic.edit((draft) => draft.explanationLanguage = value),
        ),
        const SizedBox(height: 20),
        Text(logic.l10n.mockSettingTargetLanguages, style: Theme.of(context).textTheme.titleMedium),
        _desktopChecks(
          context,
          logic.learningOptions,
          logic.draft.learningLanguages,
          logic.languageLabel,
          (value) {
            logic.edit((draft) {
              if (draft.learningLanguages.contains(value)) {
                if (draft.learningLanguages.length > 1) draft.learningLanguages.remove(value);
              } else {
                draft.learningLanguages.add(value);
              }
            });
            if (!logic.draft.learningLanguages.contains(logic.draft.activeLanguage)) {
              logic.selectTargetLanguage(logic.draft.learningLanguages.first);
            }
          },
        ),
        const SizedBox(height: 12),
        _settingSelect(
          logic.l10n.mockSettingCurrentLearningLanguage,
          logic.draft.activeLanguage,
          ['', ...logic.draft.learningLanguages],
          logic.languageLabel,
          logic.selectTargetLanguage,
        ),
        const SizedBox(height: 16),
        _settingSelect(
          logic.l10n.mockSettingLearningLevel,
          logic.draft.learningLevel,
          ['unset', 'beginner', 'basic', 'intermediate', 'advanced'],
          logic.levelLabel,
          (value) => logic.edit((draft) => draft.learningLevel = value),
        ),
        const SizedBox(height: 16),
        _button(logic.l10n.mockSettingSaveLanguageOptions, logic.saveLanguage),
        const SizedBox(height: 25),
        const Divider(),
        const SizedBox(height: 15),
        Text(logic.l10n.mockSettingLearningGoals, style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: 18,
          children: [
            for (final goal in [
              'reading',
              'textbook',
              'exam',
              'listening',
              'speaking',
              'writing',
              'vocabulary',
              'grammar',
            ])
              SizedBox(
                width: 170,
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(logic.goalLabel(goal)),
                  value: logic.draft.learningGoals.contains(goal),
                  onChanged: (_) => logic.edit(
                    (draft) => draft.learningGoals.contains(goal)
                        ? draft.learningGoals.remove(goal)
                        : draft.learningGoals.add(goal),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _button(logic.l10n.mockSettingSaveGoals, logic.saveGoals),
      ]);

  Widget _appearance(BuildContext context) => _panel(context, logic.l10n.mockSettingAppearance, [
    _settingSelect(
      logic.l10n.mockSettingTheme,
      logic.themeMode,
      ['system', 'light', 'dark'],
      logic.themeLabel,
      (value) => logic.saveAppearance(value, logic.reducedMotion),
    ),
    const SizedBox(height: 20),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(logic.l10n.mockSettingReduceMotion),
      value: logic.reducedMotion,
      onChanged: (value) => logic.saveAppearance(logic.themeMode, value),
    ),
    const SizedBox(height: 21),
    Text(logic.l10n.mockSettingReadingPreview, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 10),
    _readingPreview(context, logic),
  ]);

  Widget _reading(BuildContext context) => _panel(
    context,
    logic.l10n.mockSettingReadingPreferences,
    [
      _settingSelect(
        logic.l10n.mockSettingReadingFont,
        logic.draft.readingFont,
        ['serif', 'sans'],
        (value) =>
            value == 'serif' ? logic.l10n.mockSettingSerifFont : logic.l10n.mockSettingSansFont,
        (value) => logic.edit((draft) => draft.readingFont = value),
      ),
      const SizedBox(height: 17),
      Text('${logic.l10n.mockSettingFontSize} · ${logic.draft.readingFontSize}'),
      Slider(
        value: logic.draft.readingFontSize.toDouble(),
        min: 16,
        max: 24,
        divisions: 8,
        onChanged: (value) => logic.edit((draft) => draft.readingFontSize = value.round()),
      ),
      Text(
        '${logic.l10n.mockSettingLineHeight} · ${logic.draft.readingLineHeight.toStringAsFixed(1)}',
      ),
      Slider(
        value: logic.draft.readingLineHeight,
        min: 1.6,
        max: 2.4,
        divisions: 8,
        onChanged: (value) =>
            logic.edit((draft) => draft.readingLineHeight = double.parse(value.toStringAsFixed(1))),
      ),
      const SizedBox(height: 12),
      _settingSelect(
        logic.l10n.mockSettingReadingTheme,
        logic.draft.readingTheme,
        ['light', 'dark', 'sepia'],
        logic.themeLabel,
        (value) => logic.edit((draft) => draft.readingTheme = value),
      ),
      const SizedBox(height: 20),
      Text(logic.l10n.mockSettingReadingPreview, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      _readingPreview(context, logic),
      const SizedBox(height: 18),
      _button(logic.l10n.mockSettingSaveReading, logic.saveReading),
    ],
  );

  Widget _query(BuildContext context) => _panel(context, logic.l10n.mockSettingQueryContext, [
    _queryInput(logic),
    const SizedBox(height: 15),
    _queryPresets(logic),
    const SizedBox(height: 20),
    _button(logic.l10n.mockSettingSaveQuery, logic.saveQuery),
  ]);

  Widget _model(BuildContext context) => _panel(context, logic.l10n.mockSettingPersonalModel, [
    _settingSelect(
      logic.l10n.mockSettingProvider,
      logic.draft.modelProvider,
      ['openrouter', 'gemini'],
      (value) =>
          value == 'gemini' ? logic.l10n.mockSettingGemini : logic.l10n.mockSettingOpenRouter,
      (value) => logic.edit((draft) => draft.modelProvider = value),
    ),
    const SizedBox(height: 19),
    Text(
      logic.store.hasPersonalApiKey
          ? logic.l10n.mockSettingKeyConfigured
          : logic.l10n.mockSettingKeyUnconfigured,
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 10,
      children: [
        OutlinedButton(
          onPressed: logic.configureKey,
          child: Text(logic.l10n.mockSettingConfigureKey),
        ),
        if (logic.store.hasPersonalApiKey)
          TextButton(
            onPressed: () => logic.store.setPersonalApiKeyConfigured(false),
            child: Text(logic.l10n.mockSettingRemoveKey),
          ),
      ],
    ),
    const SizedBox(height: 22),
    Row(
      children: [
        Expanded(
          child: _modelCapability(
            context,
            Icons.text_fields,
            logic.l10n.mockSettingTextCapability,
            logic.l10n.mockSettingDefaultModel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _modelCapability(
            context,
            Icons.visibility_outlined,
            logic.l10n.mockSettingVisionCapability,
            logic.l10n.mockSettingDefaultModel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _modelCapability(
            context,
            Icons.graphic_eq,
            logic.l10n.mockSettingSpeechCapability,
            logic.l10n.mockSettingDefaultModel,
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Wrap(
      spacing: 10,
      children: [
        _button(logic.l10n.mockSettingSaveModel, logic.saveModel, fillWidth: false),
        OutlinedButton(
          onPressed: logic.store.hasPersonalApiKey ? logic.checkModel : null,
          child: Text(logic.l10n.mockSettingTestTextModel),
        ),
      ],
    ),
  ]);

  Widget _speech(BuildContext context) => _panel(context, logic.l10n.mockSettingSpeech, [
    _settingSelect(
      logic.l10n.mockSettingSpeechModel,
      logic.draft.ttsModel,
      ['gemini', 'openrouterDedicated', 'openrouterAudio'],
      (value) => switch (value) {
        'openrouterDedicated' => logic.l10n.mockSettingOpenRouterDedicated,
        'openrouterAudio' => logic.l10n.mockSettingOpenRouterAudio,
        _ => logic.l10n.mockSettingGeminiNatural,
      },
      (value) => logic.edit((draft) => draft.ttsModel = value),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: _settingSelect(
            logic.l10n.mockSettingDefaultVoice,
            logic.draft.speechVoice,
            ['japaneseClear', 'englishNatural'],
            (value) => value == 'japaneseClear'
                ? logic.l10n.mockSettingJapaneseClear
                : logic.l10n.mockSettingEnglishNatural,
            (value) => logic.edit((draft) => draft.speechVoice = value),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _settingSelect(
            logic.l10n.mockSettingAudioFormat,
            logic.draft.speechFormat,
            ['wav'],
            (_) => logic.l10n.mockSettingAudioWav,
            (value) => logic.edit((draft) => draft.speechFormat = value),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    _settingSelect(
      logic.l10n.mockSettingVoiceStyle,
      logic.draft.speechStyle,
      ['natural', 'soft'],
      (value) =>
          value == 'soft' ? logic.l10n.mockSettingSoftStyle : logic.l10n.mockSettingNaturalStyle,
      (value) => logic.edit((draft) => draft.speechStyle = value),
    ),
    const SizedBox(height: 17),
    _speedControl(context, logic),
    const SizedBox(height: 18),
    _button(logic.l10n.mockSettingSaveSpeech, logic.saveSpeech),
  ]);

  Widget _usage(BuildContext context) {
    final (calls, reuse, unknown) = _usageValues(logic.draft.usageDays);
    return _panel(context, logic.l10n.mockSettingModelUsage, [
      _usagePeriods(logic),
      const SizedBox(height: 25),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _usageStat(context, '$calls', logic.l10n.mockSettingCallCount),
          _usageStat(context, '$reuse', logic.l10n.mockSettingReuseCount),
          _usageStat(context, '$unknown', logic.l10n.mockSettingUnknownUsage),
        ],
      ),
      const SizedBox(height: 23),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(logic.l10n.mockSettingPersonalModel)),
            DataColumn(label: Text(logic.l10n.mockSettingCallCount)),
            DataColumn(label: Text(logic.l10n.mockSettingInputTokens)),
            DataColumn(label: Text(logic.l10n.mockSettingOutputTokens)),
            DataColumn(label: Text(logic.l10n.mockSettingCacheReadTokens)),
          ],
          rows: [
            DataRow(
              cells: [
                DataCell(Text(logic.l10n.mockSettingTextCapability)),
                DataCell(Text('${calls - unknown - 1}')),
                const DataCell(Text('12,480')),
                const DataCell(Text('3,240')),
                const DataCell(Text('1,800')),
              ],
            ),
            DataRow(
              cells: [
                DataCell(Text(logic.l10n.mockSettingSpeechCapability)),
                DataCell(Text('$unknown')),
                DataCell(Text(logic.l10n.mockSettingUnknownUsage)),
                DataCell(Text(logic.l10n.mockSettingUnknownUsage)),
                DataCell(Text(logic.l10n.mockSettingUnknownUsage)),
              ],
            ),
            DataRow(
              cells: [
                DataCell(Text(logic.l10n.mockSettingVisionCapability)),
                const DataCell(Text('1')),
                const DataCell(Text('1,520')),
                const DataCell(Text('480')),
                const DataCell(Text('0')),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _cache(BuildContext context) {
    if (!settingsUsePreviewAvatar(context)) {
      return _panel(context, logic.l10n.mockSettingLocalCache, [
        _localCacheCounts(logic),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey(UiTestIds.settingsCacheClear),
          onPressed: logic.cache.ready && !logic.cache.busy ? logic.clearCache : null,
          icon: const Icon(Icons.delete_outline),
          label: Text(logic.l10n.mockSettingClearAccountLocalCache),
        ),
      ]);
    }
    return _panel(context, logic.l10n.mockSettingLocalCache, [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logic.l10n.mockSettingLocalAvailable,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                _localCacheCounts(logic),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: logic.cache.ready && !logic.cache.busy ? logic.clearCache : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: HarukaColors.of(context).bookPeach,
                      foregroundColor: HarukaColors.of(context).danger,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(logic.l10n.mockSettingClearAccountLocalCache),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 50),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logic.l10n.mockSettingSavedResults,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                Text(
                  logic.l10n.mockSettingCacheCounts(
                    logic.store.savedExplanationCount,
                    logic.store.savedAudioCount,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 50),
      Text(logic.l10n.mockSettingLocalSpace, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 13),
      _cacheLimits(logic),
      const SizedBox(height: 16),
      _button(
        logic.l10n.mockSettingSaveCacheLimits,
        logic.cache.ready && !logic.cache.busy ? logic.saveCache : null,
      ),
    ]);
  }

  Widget _connection(BuildContext context) {
    final live = ServiceEndpointScope.maybeOf(context);
    if (live != null) {
      return _panel(context, logic.l10n.mockSettingServiceConnection, [
        ServiceEndpointForm(
          controller: live,
          onAdopted: () {
            if (context.mounted) context.go(AppRoutes.login);
          },
        ),
      ]);
    }
    return _panel(context, logic.l10n.mockSettingServiceConnection, [
      TextField(
        controller: logic.serviceAddress,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: logic.l10n.mockSettingServiceAddress,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => logic.edit((draft) => draft.serviceAddress = value),
      ),
      const SizedBox(height: 17),
      _button(logic.l10n.mockSettingProbeConnection, logic.probeAddress),
      const SizedBox(height: 13),
      if (logic.store.serviceProbeAttempted)
        Text(
          logic.store.serviceAddressValidated
              ? logic.l10n.mockSettingAddressValid
              : logic.l10n.mockSettingAddressInvalid,
        ),
    ]);
  }

  Widget _security(BuildContext context) => _panel(context, logic.l10n.mockSettingSecurityAccount, [
    if (!settingsUsePreviewAvatar(context)) ...[
      const AccountIdentitySummary(),
      const SizedBox(height: 16),
      const Divider(),
    ],
    ListTile(
      title: Text(logic.l10n.mockSettingProfile),
      leading: const Icon(Icons.person_outline),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(settingsSectionPath(context, 'profile')),
    ),
    const Divider(),
    ListTile(
      title: Text(logic.l10n.mockSettingChangePassword),
      leading: const Icon(Icons.lock_outline),
      trailing: const Icon(Icons.chevron_right),
      onTap: logic.changePassword,
    ),
    const Divider(),
    ListTile(
      title: Text(logic.l10n.mockSettingCurrentSession),
      subtitle: Text(logic.l10n.mockSettingSessionActive),
      leading: const Icon(Icons.devices_outlined),
      trailing: const Icon(Icons.chevron_right),
      onTap: logic.openSessions,
    ),
    const SizedBox(height: 17),
    OutlinedButton(onPressed: logic.signOut, child: Text(logic.l10n.mockSettingLogout)),
  ]);
}

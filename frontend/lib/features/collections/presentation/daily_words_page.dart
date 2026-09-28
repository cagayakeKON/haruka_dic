import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_repository_scope.dart';
import 'package:haruka/features/settings/presentation/settings_snapshot_gate.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/collections/presentation/notebook_pages.dart';
import 'package:haruka/features/collections/presentation/word_detail_page.dart';

import 'collection_catalog_access.dart';
import '../data/collection_catalog.dart';
import '../domain/account_calendar.dart';

EdgeInsets _desktopContentInset(BuildContext context, double maxWidth) {
  // The persistent shell already constrains and centers its routed content.
  return EdgeInsets.zero;
}

class DailyWordsPage extends StatefulWidget {
  const DailyWordsPage({this.clock = DateTime.now, super.key});

  final DateTime Function() clock;

  @override
  State<DailyWordsPage> createState() => _DailyWordsPageState();
}

class _DailyWordsPageState extends State<DailyWordsPage> with WidgetsBindingObserver {
  late DateTime date;
  AccountCalendar? _calendar;
  String? _accountTimeZone;
  int? _settingsScopeGeneration;
  CachedSettingsRepository? _settingsRepository;
  Future<void>? _settingsReady;
  bool _foreground = true;
  int _calendarGeneration = 0;
  BuildContext? _datePickerContext;
  bool _followingToday = true;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsRepositoryScope.of(context);
    if (!identical(_settingsRepository, settings) ||
        _settingsScopeGeneration != settings.scopeGeneration) {
      _settingsRepository = settings;
      _settingsScopeGeneration = settings.scopeGeneration;
      // A direct route can mount before the preview account has attached its
      // cache scope. Let that first attachment finish before the gate reads.
      _settingsReady = settings.waitForReadiness?.call() ?? Future<void>.value();
      _followingToday = true;
      _clearCalendar();
    }
    final value = settings.snapshot(SettingsGroup.preferences)?.fields['timezone'];
    final timeZone = value is String && value.isNotEmpty ? value : null;
    if (timeZone == null) {
      _clearCalendar();
      return;
    }
    if (_accountTimeZone == timeZone && _calendar != null) return;
    _clearCalendar();
    try {
      _calendar = AccountCalendar(timeZone, clock: widget.clock);
    } on Object {
      return;
    }
    _accountTimeZone = timeZone;
    if (_followingToday) date = _calendar!.today;
    _scheduleMidnight();
  }

  void _clearCalendar() {
    if (_calendar == null && _datePickerContext == null) return;
    _calendarGeneration++;
    _calendar = null;
    _accountTimeZone = null;
    _midnightTimer?.cancel();
    final pickerContext = _datePickerContext;
    if (pickerContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!pickerContext.mounted || ModalRoute.of(pickerContext)?.isCurrent != true) return;
        Navigator.of(pickerContext).pop();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DailyWordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.clock, widget.clock) || _accountTimeZone == null) return;
    _calendar = AccountCalendar(_accountTimeZone!, clock: widget.clock);
    _calendarGeneration++;
    if (_followingToday) date = _calendar!.today;
    _scheduleMidnight();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = foregroundAfterLifecycle(state, wasForeground: wasForeground);
    if (wasForeground || !_foreground || !_followingToday || _calendar == null) return;
    setState(() => date = _calendar!.today);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    if (!_followingToday || _calendar == null) return;
    _midnightTimer = Timer(_calendar!.untilNextMidnight(), () {
      if (!mounted) return;
      setState(() => date = _calendar!.today);
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final calendar = _calendar;
    if (calendar == null) return;
    final generation = _calendarGeneration;
    final chosen = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1970),
      lastDate: calendar.today,
      barrierColor: HarukaColors.of(context).scrim,
      builder: (pickerContext, child) {
        _datePickerContext = pickerContext;
        return Theme(
          data: Theme.of(pickerContext).copyWith(
            datePickerTheme: DatePickerThemeData(
              headerHeadlineStyle: Theme.of(pickerContext).textTheme.titleMedium
                  ?.copyWith(fontSize: 18, height: 1.2),
              headerBackgroundColor: Theme.of(pickerContext).colorScheme.surface,
              headerForegroundColor: Theme.of(pickerContext).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    _datePickerContext = null;
    if (chosen != null &&
        mounted &&
        generation == _calendarGeneration &&
        identical(calendar, _calendar)) {
      setState(() {
        date = chosen;
        final today = calendar.today;
        _followingToday =
            chosen.year == today.year && chosen.month == today.month && chosen.day == today.day;
      });
      _scheduleMidnight();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _settingsReady,
    builder: (context, readiness) {
      if (readiness.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return SettingsSnapshotGate(
        groups: const {SettingsGroup.preferences},
        builder: (context) => _calendar == null
            ? Center(child: Text(AppLocalizations.of(context).authUnavailableShort))
            : CollectionCatalogAccess(
                allCollections: true,
                builder: (context, catalog) => _buildContent(context, catalog),
              ),
      );
    },
  );

  Widget _buildContent(BuildContext context, CollectionCatalog catalog) {
    final calendar = _calendar!;
    final timeZone = _accountTimeZone!;
    final items = catalog.allCollections.where((item) {
      return item.kind == CollectionKind.word && calendar.isOnDate(item.createdAt, date);
    }).toList();
    final strings = AppLocalizations.of(context);
    return PreviewPageFrame(
      location: AppRoutes.mockDailyWords,
      title: strings.mockSupportDailyWordsTitle,
      detail: true,
      detailNotifications: false,
      mobile: MobileDailyWordsView(
        items: items,
        date: date,
        timezone: timeZone,
        onDate: chooseDate,
      ),
      desktop: DesktopDailyWordsView(
        items: items,
        date: date,
        timezone: timeZone,
        onDate: chooseDate,
      ),
    );
  }
}

class MobileDailyWordsView extends StatelessWidget {
  const MobileDailyWordsView({
    required this.items,
    required this.date,
    required this.timezone,
    required this.onDate,
    super.key,
  });
  final List<CollectionEntry> items;
  final DateTime date;
  final String timezone;
  final VoidCallback onDate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(strings.mockSupportDailyWordsTitle, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        HarukaSurface(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.mockSupportDailyWordsAddedToday,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    _DailyWordCount(count: items.length),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: _DailyDateField(date: date, onDate: onDate, buttonHeight: 48),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          strings.mockSupportDailyWordsScopeDescription(timezone),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          HarukaSurface(
            child: SizedBox(
              height: 142,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.mockSupportDailyWordsEmptyTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.mockSupportDailyWordsEmptyHint,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          HarukaSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _DailyMobileRow(item: items[i]),
                  if (i < items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DailyMobileRow extends StatelessWidget {
  const _DailyMobileRow({required this.item});
  final CollectionEntry item;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => showWordDetail(context, item.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: HarukaColors.of(context).selected,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.menu_book_outlined, color: colors.primary, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.displayText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (item.reading != null) ...[
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  item.reading!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          item.meaning,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outline),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      strings.mockNotebookKindWord,
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(Icons.chevron_right, size: 18, color: colors.primary),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: strings.mockNotebookReadNamed(item.displayText),
          onPressed: () =>
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(strings.mockNotebookAudioUnavailable))),
          icon: Icon(Icons.volume_up_outlined, color: colors.primary, size: 18),
        ),
      ],
    );
  }
}

class DesktopDailyWordsView extends StatelessWidget {
  const DesktopDailyWordsView({
    required this.items,
    required this.date,
    required this.timezone,
    required this.onDate,
    super.key,
  });
  final List<CollectionEntry> items;
  final DateTime date;
  final String timezone;
  final VoidCallback onDate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListView(
      padding: _desktopContentInset(
        context,
        MediaQuery.sizeOf(context).width <= 1600 ? 1044 : 1120,
      ).copyWith(top: 0),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width <= 1600 ? 1044 : 1120,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.mockSupportDailyWordsTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              HarukaSurface(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(strings.mockSupportDailyWordsAddedToday),
                          _DailyWordCount(count: items.length),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: _DailyDateField(date: date, onDate: onDate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.mockSupportDailyWordsScopeDescription(timezone),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                HarukaSurface(
                  child: SizedBox(
                    height: 150,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.mockSupportDailyWordsEmptyTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.mockSupportDailyWordsEmptyHint,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                HarukaSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        DesktopCollectionRow(item: items[i]),
                        if (i < items.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyWordCount extends StatelessWidget {
  const _DailyWordCount({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$count',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
        ),
        TextSpan(text: ' ${AppLocalizations.of(context).mockSupportDailyWordsWordCountUnit}'),
      ],
    ),
  );
}

class _DailyDateField extends StatelessWidget {
  const _DailyDateField({required this.date, required this.onDate, this.buttonHeight = 52});
  final DateTime date;
  final VoidCallback onDate;
  final double buttonHeight;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppLocalizations.of(context).mockSupportDailyWordsDate,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          ),
          style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(buttonHeight)),
        ),
      ),
    ],
  );
}

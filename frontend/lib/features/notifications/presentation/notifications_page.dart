import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';

import '../data/notification_repository.dart';
import '../domain/notification_record.dart';
import '../domain/notification_target.dart';
import 'notification_repository_scope.dart';

EdgeInsets _desktopContentInset(BuildContext context, double maxWidth) {
  final contentWidth = MediaQuery.sizeOf(context).width - 324;
  final inset = ((contentWidth - maxWidth) / 2).clamp(0.0, double.infinity);
  return EdgeInsets.symmetric(horizontal: inset);
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: () => _routeCurrent = false,
    onReturned: _onPageReturned,
  );
  NotificationRepository? _repository;
  Timer? _visibleRefresh;
  bool _foreground = true;
  bool _routeCurrent = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _revalidationGate = false;
  int _visibilityEpoch = 0;

  void _onPageReturned() {
    if (!mounted) return;
    _routeCurrent = true;
    _visibilityEpoch++;
    setState(() => _revalidationGate = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground && _routeCurrent) _refresh(queueIfBusy: true);
    });
  }

  void _refresh({bool preserveCurrent = false, bool queueIfBusy = false}) {
    final repository = _repository;
    if (repository == null || !mounted || !_foreground || !_routeCurrent) return;
    if (_refreshing) {
      if (queueIfBusy) _refreshQueued = true;
      return;
    }
    _refreshing = true;
    final epoch = _visibilityEpoch;
    unawaited(() async {
      try {
        await repository.refresh(force: true, preserveCurrent: preserveCurrent);
      } on Object {
        // The repository exposes its own failed/blocked state to the page.
      } finally {
        _refreshing = false;
        if (_refreshQueued) {
          _refreshQueued = false;
          _refresh();
        } else if (mounted && _revalidationGate && epoch == _visibilityEpoch) {
          setState(() => _revalidationGate = false);
        }
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibleRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      _refresh(preserveCurrent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void dispose() {
    _visibleRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageActivity.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = NotificationRepositoryScope.of(context);
    _pageActivity.bind(context);
    final routeCurrent = _pageActivity.isCurrent;
    final becameVisible = !_routeCurrent && routeCurrent;
    _routeCurrent = routeCurrent;
    if (!identical(_repository, repository)) {
      _repository = repository;
      _visibilityEpoch++;
      _revalidationGate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _foreground && _routeCurrent && identical(_repository, repository)) {
          _refresh(preserveCurrent: false, queueIfBusy: true);
        }
      });
    } else if (becameVisible && _foreground) {
      _visibilityEpoch++;
      _revalidationGate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _foreground && _routeCurrent) _refresh(queueIfBusy: true);
      });
    }
  }

  void _showFailure() {
    if (!mounted) return;
    final strings = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.mockSupportNotificationsReadFailed)));
  }

  Future<void> _open(NotificationRecord item) async {
    final repository = _repository;
    if (repository == null || repository.busy) return;
    try {
      await repository.markRead(item.id);
    } on Object {
      _showFailure();
      return;
    }
    if (!mounted || !identical(_repository, repository)) return;
    final targetType = notificationMaterialType(item.route);
    final resourceId = item.resourceId;
    if (targetType == null || resourceId == null) {
      _showUnavailable();
      return;
    }
    final catalog = MaterialCatalogScope.of(context);
    try {
      await catalog.refresh(force: true);
    } on Object {
      _showUnavailable();
      return;
    }
    if (!mounted || !identical(_repository, repository)) return;
    final target = catalog.status == MaterialCatalogStatus.ready
        ? catalog.findById(resourceId)
        : null;
    if (target == null || !notificationTargetMatches(item, target)) {
      _showUnavailable();
      return;
    }
    context.go(AppRoutes.mockMaterialPath(resourceId));
  }

  void _showUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).mockMaterialUnavailableMessage)),
    );
  }

  Future<void> _readAll() async {
    if (_repository!.busy) return;
    try {
      await _repository!.markAllRead();
    } on Object {
      _showFailure();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = NotificationRepositoryScope.of(context);
    final strings = AppLocalizations.of(context);
    final content = _revalidationGate
        ? const Center(child: CircularProgressIndicator())
        : switch (repository.status) {
            NotificationListStatus.initial ||
            NotificationListStatus.loading => const Center(child: CircularProgressIndicator()),
            NotificationListStatus.blocked || NotificationListStatus.failed => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.apiUnknownError),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => repository.refresh(force: true),
                    child: Text(strings.authRetry),
                  ),
                ],
              ),
            ),
            NotificationListStatus.ready || NotificationListStatus.stale => null,
          };

    Widget readOnlyIfStale(Widget child) {
      return Stack(
        children: [
          child,
          if (repository.status == NotificationListStatus.stale)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                child: Row(
                  children: [
                    Expanded(child: Text(strings.apiUnknownError)),
                    TextButton(
                      onPressed: () => unawaited(repository.refresh(force: true)),
                      child: Text(strings.authRetry),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return PreviewPageFrame(
      location: AppRoutes.mockNotifications,
      title: AppLocalizations.of(context).mockSupportNotificationsTitle,
      detail: true,
      detailNotifications: false,
      mobile:
          content ??
          readOnlyIfStale(
            MobileNotificationsView(
              items: repository.items,
              unreadCount: repository.unreadCount,
              busy: repository.busy,
              onReadAll: _readAll,
              onOpen: _open,
            ),
          ),
      desktop:
          content ??
          readOnlyIfStale(
            DesktopNotificationsView(
              items: repository.items,
              unreadCount: repository.unreadCount,
              busy: repository.busy,
              onReadAll: _readAll,
              onOpen: _open,
            ),
          ),
    );
  }
}

String _notificationTime(BuildContext context, NotificationRecord item) {
  final strings = AppLocalizations.of(context);
  final value = item.createdAt.toUtc();
  final now = DateTime.now();
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(value.year, value.month, value.day)).inDays;
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  if (days == 0) return strings.mockSupportNotificationTodayTime(time);
  if (days == 1) return strings.mockSupportNotificationYesterdayTime(time);
  return strings.mockSupportNotificationMonthDay(value.month, value.day);
}

bool _materialTargetUnavailable(NotificationRecord item) =>
    item.resourceId == null ||
    item.resourceRevision == null ||
    notificationMaterialType(item.route) == null;

String _notificationTitle(BuildContext context, NotificationRecord item) =>
    _materialTargetUnavailable(item)
    ? AppLocalizations.of(context).mockMaterialUnavailableTitle
    : item.title;

String _notificationDetail(BuildContext context, NotificationRecord item) =>
    _materialTargetUnavailable(item)
    ? AppLocalizations.of(context).mockMaterialUnavailableMessage
    : item.detail;

class MobileNotificationsView extends StatelessWidget {
  const MobileNotificationsView({
    required this.items,
    required this.unreadCount,
    required this.busy,
    required this.onReadAll,
    required this.onOpen,
    super.key,
  });
  final List<NotificationRecord> items;
  final int unreadCount;
  final bool busy;
  final VoidCallback onReadAll;
  final ValueChanged<NotificationRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      children: [
        Text(
          strings.mockSupportUpdatesEyebrow,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, letterSpacing: 1),
        ),
        const SizedBox(height: 41),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.mockSupportNotificationsHeading,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: unreadCount > 0 && !busy ? onReadAll : null,
              child: Text(strings.mockSupportNotificationsMarkAllRead),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(child: Text(strings.mockSupportNotificationsEmpty)),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HarukaSurface(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: busy ? null : () => onOpen(item),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.readAt == null) ...[
                            Container(
                              width: 20,
                              height: 6,
                              decoration: BoxDecoration(
                                color: HarukaColors.of(context).signal,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              item.readAt == null
                                  ? strings.mockSupportUnread
                                  : strings.mockSupportRead,
                              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                            ),
                          ),
                          Text(
                            _notificationTime(context, item),
                            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _notificationTitle(context, item),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: item.readAt == null ? colors.primary : colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _notificationDetail(context, item),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DesktopNotificationsView extends StatelessWidget {
  const DesktopNotificationsView({
    required this.items,
    required this.unreadCount,
    required this.busy,
    required this.onReadAll,
    required this.onOpen,
    super.key,
  });
  final List<NotificationRecord> items;
  final int unreadCount;
  final bool busy;
  final VoidCallback onReadAll;
  final ValueChanged<NotificationRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: _desktopContentInset(context, 1320),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.mockSupportNotificationsTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text(
                    strings.mockSupportNotificationsHeading,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    strings.mockSupportNotificationsUnreadCount(unreadCount),
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: unreadCount > 0 && !busy ? onReadAll : null,
                    child: Text(strings.mockSupportNotificationsMarkAllRead),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              HarukaSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(strings.mockSupportNotificationsEmpty),
                      ),
                    for (var i = 0; i < items.length; i++) ...[
                      InkWell(
                        onTap: busy ? null : () => onOpen(items[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          child: Row(
                            children: [
                              Container(
                                width: 21,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: items[i].readAt == null
                                      ? HarukaColors.of(context).signal
                                      : HarukaColors.of(context).selected,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 17),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _notificationTitle(context, items[i]),
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: items[i].readAt == null
                                            ? colors.primary
                                            : colors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _notificationDetail(context, items[i]),
                                      style: TextStyle(color: colors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _notificationTime(context, items[i]),
                                style: TextStyle(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(width: 16),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
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

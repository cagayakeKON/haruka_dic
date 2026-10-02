import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/shared/presentation/components.dart';
import 'package:haruka/app/preview_shell.dart';
import 'package:haruka/features/library/presentation/material_catalog_scope.dart';

import '../../../generated/ui_test_ids.dart';
import '../../../shared/identified.dart';

import '../data/notification_repository.dart';
import '../data/cached_notification_repository.dart';
import '../../../core/api/responses.dart';
import '../../library/data/http_material_catalog.dart';
import '../../library/domain/material_summary.dart';
import '../../library/presentation/library_pages.dart';
import '../../library/presentation/material_management_controls.dart';
import '../domain/notification_record.dart';
import '../domain/notification_target.dart';
import 'notification_repository_scope.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  NotificationRepository? _repository;
  bool _opening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = NotificationRepositoryScope.of(context);
    if (identical(_repository, repository)) return;
    _repository = repository;
    // Navigation, dialogs and foreground transitions have no read semantics.
    if (repository.status == NotificationListStatus.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(_repository, repository) &&
            repository.status == NotificationListStatus.initial) {
          unawaited(repository.refresh());
        }
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
    if (repository == null || repository.busy || _opening) return;
    final cached = repository is CachedNotificationRepository ? repository : null;
    final scope = cached?.scopeIdentity;
    bool owned() =>
        mounted &&
        identical(_repository, repository) &&
        (cached == null || cached.isCurrent(scope!));
    setState(() => _opening = true);
    try {
      if (item.readAt == null && (cached?.canUpdate ?? true)) {
        await repository.markRead(item.id);
      }
      if (!mounted || !owned()) return;
      final resourceId = item.resourceId;
      if (resourceId == null || item.resourceRevision == null) {
        _showUnavailable();
        return;
      }
      final catalog = MaterialCatalogScope.of(context);
      if (item.serverRecord) {
        if (catalog is! HttpMaterialCatalog ||
            item.route != 'material' ||
            !catalog.allows('client.material.read')) {
          _showUnavailable();
          return;
        }
        final catalogScope = catalog.scopeIdentity;
        final row = await (() async {
          try {
            return await catalog.detail(resourceId, fresh: true);
          } on ApiFailure catch (error) {
            if (const {'RESOURCE_NOT_FOUND', 'PERMISSION_DENIED'}.contains(error.code)) {
              if (owned() && catalog.isCurrent(catalogScope)) _showUnavailable();
              return null;
            }
            rethrow;
          }
        })();
        if (row == null) return;
        if (!mounted || !owned() || !catalog.isCurrent(catalogScope)) return;
        if (!notificationMetadataTargetMatches(item, row) ||
            (row.type == LearningMaterialType.exam && !catalog.allows('client.exam.read'))) {
          _showUnavailable();
          return;
        }
        final summary = catalog.findById(resourceId)!;
        if (materialCanOpen(context, summary)) {
          await context.push(AppRoutes.materialPath(resourceId));
        } else if (MediaQuery.sizeOf(context).width < 600) {
          await showLiveMaterialDialog(
            context,
            catalog,
            resourceId,
            onOpenMaterial: () {
              if (context.mounted && catalog.isCurrent(catalogScope)) {
                unawaited(context.push(AppRoutes.materialPath(resourceId)));
              }
            },
          );
        } else {
          await context.push(AppRoutes.materialDetailsPath(resourceId));
        }
      } else {
        // Preview pointers retain their original type-specific mock routes.
        final target = catalog.findById(resourceId);
        if (target == null || !notificationTargetMatches(item, target)) {
          _showUnavailable();
          return;
        }
        context.go(AppRoutes.mockMaterialPath(resourceId));
      }
    } on Object {
      if (owned()) _showFailure();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
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

  Widget? _tools(NotificationRepository repository) {
    if (liveMaterialCatalog(context) == null || repository is! CachedNotificationRepository) {
      return null;
    }
    final strings = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Identified(
          id: UiTestIds.notificationsUnreadFilter,
          child: FilterChip(
            label: Text(strings.notificationUnreadOnly),
            selected: repository.activeQuery.unreadOnly,
            onSelected: repository.busy
                ? null
                : (selected) =>
                      repository.refresh(query: NotificationListQuery(unreadOnly: selected)),
          ),
        ),
        Identified(
          id: UiTestIds.notificationsRefresh,
          child: TextButton(
            onPressed: repository.busy
                ? null
                : () => repository.refresh(
                    query: NotificationListQuery(unreadOnly: repository.activeQuery.unreadOnly),
                    force: true,
                    preserveCurrent: true,
                  ),
            child: Text(strings.notificationRefresh),
          ),
        ),
        if (repository.nextCursor != null)
          Identified(
            id: UiTestIds.notificationsMore,
            child: TextButton(
              onPressed: repository.busy
                  ? null
                  : () async {
                      try {
                        await repository.loadMore();
                      } on Object {
                        _showFailure();
                      }
                    },
              child: Text(strings.materialMore),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = NotificationRepositoryScope.of(context);
    final strings = AppLocalizations.of(context);
    final content = switch (repository.status) {
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

    return Identified(
      id: UiTestIds.notificationsPage,
      child: PreviewPageFrame(
        location: liveMaterialCatalog(context) == null
            ? AppRoutes.mockNotifications
            : AppRoutes.notifications,
        title: AppLocalizations.of(context).mockSupportNotificationsTitle,
        detail: true,
        detailNotifications: false,
        mobile: readOnlyIfStale(
          MobileNotificationsView(
            items: repository.items,
            unreadCount: repository.unreadCount,
            busy: repository.busy || _opening,
            canUpdate: repository is! CachedNotificationRepository || repository.canUpdate,
            tools: _tools(repository),
            listState: content,
            onReadAll: _readAll,
            onOpen: _open,
          ),
        ),
        desktop: readOnlyIfStale(
          DesktopNotificationsView(
            items: repository.items,
            unreadCount: repository.unreadCount,
            busy: repository.busy || _opening,
            canUpdate: repository is! CachedNotificationRepository || repository.canUpdate,
            tools: _tools(repository),
            listState: content,
            onReadAll: _readAll,
            onOpen: _open,
          ),
        ),
      ),
    );
  }
}

Widget _notificationIdentified(NotificationRecord item, Widget child) =>
    item.serverRecord ? Identified(id: UiTestIds.notificationRow(item.id), child: child) : child;

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
    (item.serverRecord ? item.route != 'material' : notificationMaterialType(item.route) == null);

String _notificationTitle(BuildContext context, NotificationRecord item) =>
    _materialTargetUnavailable(item)
    ? AppLocalizations.of(context).mockMaterialUnavailableTitle
    : item.serverRecord
    ? switch (item.messageCode) {
        'material.import.completed' => AppLocalizations.of(context).notificationImportCompleted,
        'material.import.failed' => AppLocalizations.of(context).notificationImportFailed,
        _ => AppLocalizations.of(context).notificationImportNeedsReview,
      }
    : item.title;

String _notificationDetail(BuildContext context, NotificationRecord item) =>
    _materialTargetUnavailable(item)
    ? AppLocalizations.of(context).mockMaterialUnavailableMessage
    : item.serverRecord
    ? AppLocalizations.of(context).notificationSourceBoundary
    : item.detail;

class MobileNotificationsView extends StatelessWidget {
  const MobileNotificationsView({
    required this.items,
    required this.unreadCount,
    required this.busy,
    required this.onReadAll,
    required this.onOpen,
    this.canUpdate = true,
    this.tools,
    this.listState,
    super.key,
  });
  final List<NotificationRecord> items;
  final int unreadCount;
  final bool busy;
  final bool canUpdate;
  final Widget? tools;
  final Widget? listState;
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
            if (canUpdate)
              Identified(
                id: UiTestIds.notificationsReadAll,
                child: TextButton(
                  onPressed: unreadCount > 0 && !busy ? onReadAll : null,
                  child: Text(strings.mockSupportNotificationsMarkAllRead),
                ),
              ),
          ],
        ),
        ?tools,
        const SizedBox(height: 18),
        ?listState,
        if (items.isEmpty && listState == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(child: Text(strings.mockSupportNotificationsEmpty)),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _notificationIdentified(
              item,
              HarukaSurface(
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
    this.canUpdate = true,
    this.tools,
    this.listState,
    super.key,
  });
  final List<NotificationRecord> items;
  final int unreadCount;
  final bool busy;
  final bool canUpdate;
  final Widget? tools;
  final Widget? listState;
  final VoidCallback onReadAll;
  final ValueChanged<NotificationRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
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
                  if (canUpdate)
                    Identified(
                      id: UiTestIds.notificationsReadAll,
                      child: TextButton(
                        onPressed: unreadCount > 0 && !busy ? onReadAll : null,
                        child: Text(strings.mockSupportNotificationsMarkAllRead),
                      ),
                    ),
                ],
              ),
              ?tools,
              const SizedBox(height: 14),
              HarukaSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ?listState,
                    if (items.isEmpty && listState == null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(strings.mockSupportNotificationsEmpty),
                      ),
                    for (var i = 0; i < items.length; i++) ...[
                      _notificationIdentified(
                        items[i],
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

import 'test_database.dart';
export 'test_database.dart';

import 'package:flutter/widgets.dart';
import 'package:haruka/app/preview_app.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/dev/preview/settings_cache_adapter.dart';
import 'package:haruka/features/library/data/material_catalog.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/notifications/data/notification_repository.dart';

Widget buildTestPreviewApp({
  DateTime Function() clock = DateTime.now,
  MaterialCatalog? materialCatalog,
  QueryResultRepository? queryResultRepository,
  NotificationRepository? notificationRepository,
}) => PreviewHarukaApp(
  clock: clock,
  materialCatalog: materialCatalog,
  queryResultRepository: queryResultRepository,
  notificationRepository: notificationRepository,
  settingsCacheAdapter: PreviewSettingsCacheAdapter(
    coordinator: CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: memoryTestDatabase(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    ),
  ),
);

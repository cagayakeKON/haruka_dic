import 'package:dio/dio.dart';

import '../domain/settings_snapshot.dart';

final class SettingsRevisionConflict implements Exception {
  const SettingsRevisionConflict();
}

/// Backend adapter boundary. A PATCH result means the source has committed;
/// read and write permissions, field masks and revisions belong to the source.
abstract interface class SettingsSource {
  Future<SettingsSnapshot> fetch(SettingsGroup group, CancelToken cancel);

  Future<SettingsSnapshot> patch(SettingsGroup group, SettingsPatch patch);
}

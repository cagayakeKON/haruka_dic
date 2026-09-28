import 'package:flutter/widgets.dart';

import '../data/cached_settings_repository.dart';

class SettingsRepositoryScope extends InheritedNotifier<CachedSettingsRepository> {
  const SettingsRepositoryScope({
    required CachedSettingsRepository repository,
    required super.child,
    super.key,
  }) : super(notifier: repository);

  static CachedSettingsRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsRepositoryScope>();
    assert(scope != null, 'SettingsRepositoryScope is missing');
    return scope!.notifier!;
  }

  static CachedSettingsRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsRepositoryScope>()?.notifier;
}

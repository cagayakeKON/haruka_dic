import 'package:flutter/widgets.dart';

import '../data/notification_repository.dart';

class NotificationRepositoryScope extends InheritedNotifier<NotificationRepository> {
  const NotificationRepositoryScope({
    required NotificationRepository repository,
    required super.child,
    super.key,
  }) : super(notifier: repository);

  static NotificationRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NotificationRepositoryScope>();
    assert(scope != null, 'NotificationRepositoryScope is missing');
    return scope!.notifier!;
  }
}

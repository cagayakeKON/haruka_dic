import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/notifications/domain/notification_record.dart';
import 'package:haruka/features/notifications/presentation/notifications_page.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  final item = NotificationRecord(
    id: 'notification-1',
    title: 'Ready',
    detail: 'Finished',
    route: 'textbook',
    resourceId: 'textbook-1',
    resourceRevision: 1,
    createdAt: DateTime.utc(2026, 9, 27),
  );

  for (final compact in [true, false]) {
    testWidgets(
      '${compact ? 'mobile' : 'desktop'} read-only controls hide writes but keep navigation',
      (tester) async {
        var opens = 0, writes = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: HarukaTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: compact
                  ? MobileNotificationsView(
                      items: [item],
                      unreadCount: 1,
                      busy: false,
                      canUpdate: false,
                      onReadAll: () => writes++,
                      onOpen: (_) => opens++,
                    )
                  : DesktopNotificationsView(
                      items: [item],
                      unreadCount: 1,
                      busy: false,
                      canUpdate: false,
                      onReadAll: () => writes++,
                      onOpen: (_) => opens++,
                    ),
            ),
          ),
        );
        expect(find.text('全部标为已读'), findsNothing);
        await tester.tap(find.text('Ready'));
        expect(opens, 1);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('${compact ? 'mobile' : 'desktop'} read controls disable during mutation', (
      tester,
    ) async {
      var reads = 0;
      var readAlls = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          theme: HarukaTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: compact
                ? MobileNotificationsView(
                    items: [item],
                    unreadCount: 1,
                    busy: true,
                    onReadAll: () => readAlls++,
                    onOpen: (_) => reads++,
                  )
                : DesktopNotificationsView(
                    items: [item],
                    unreadCount: 1,
                    busy: true,
                    onReadAll: () => readAlls++,
                    onOpen: (_) => reads++,
                  ),
          ),
        ),
      );
      final markAll = find.widgetWithText(TextButton, '全部标为已读');
      expect(tester.widget<TextButton>(markAll).onPressed, isNull);
      final card = find.ancestor(of: find.text('Ready'), matching: find.byType(InkWell));
      expect(tester.widget<InkWell>(card).onTap, isNull);
      expect(reads, 0);
      expect(readAlls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/preview_app.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/main.dart' as configured;
import 'package:haruka/main_preview.dart' as preview;

void main() {
  testWidgets('Android entry rejects missing deployment identity before opening a service', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.runAsync(configured.main);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(UiTestIds.configurationError)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'explicit preview entry opens the existing mock shell without service configuration',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      unawaited(preview.main());
      // runApp schedules a warm-up frame; align its epoch with the widget clock.
      tester.binding.resetEpoch();
      await tester.pumpAndSettle();
      expect(find.byType(PreviewHarukaApp), findsOneWidget);
      expect(find.byKey(const ValueKey(UiTestIds.configurationError)), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

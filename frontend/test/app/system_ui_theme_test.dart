import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';

void main() {
  for (final (theme, brightness) in [
    (HarukaTheme.light(), Brightness.dark),
    (HarukaTheme.dark(), Brightness.light),
  ]) {
    testWidgets('system bars follow ${theme.brightness} theme', (tester) async {
      late SystemUiOverlayStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              style = HarukaTheme.systemUiOverlayStyle(context);
              return const Scaffold();
            },
          ),
        ),
      );

      expect(style.statusBarIconBrightness, brightness);
      expect(style.systemNavigationBarIconBrightness, brightness);
      expect(style.statusBarColor?.a, 0);
      expect(style.systemNavigationBarColor?.a, 0);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    });
  }
}

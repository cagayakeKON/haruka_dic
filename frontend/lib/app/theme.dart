import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The only source of product colors. Widgets consume the current theme roles.
@immutable
class HarukaColors extends ThemeExtension<HarukaColors> {
  const HarukaColors({
    required this.canvas,
    required this.content,
    required this.selected,
    required this.signal,
    required this.onSignal,
    required this.positive,
    required this.warning,
    required this.danger,
    required this.bookBlue,
    required this.bookGreen,
    required this.bookPeach,
    required this.scrim,
  });

  final Color canvas;
  final Color content;
  final Color selected;
  final Color signal;
  final Color onSignal;
  final Color positive;
  final Color warning;
  final Color danger;
  final Color bookBlue;
  final Color bookGreen;
  final Color bookPeach;
  final Color scrim;

  static HarukaColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HarukaColors>() ??
        (theme.brightness == Brightness.dark ? HarukaTheme._dark : HarukaTheme._light);
  }

  @override
  HarukaColors copyWith({
    Color? canvas,
    Color? content,
    Color? selected,
    Color? signal,
    Color? onSignal,
    Color? positive,
    Color? warning,
    Color? danger,
    Color? bookBlue,
    Color? bookGreen,
    Color? bookPeach,
    Color? scrim,
  }) => HarukaColors(
    canvas: canvas ?? this.canvas,
    content: content ?? this.content,
    selected: selected ?? this.selected,
    signal: signal ?? this.signal,
    onSignal: onSignal ?? this.onSignal,
    positive: positive ?? this.positive,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    bookBlue: bookBlue ?? this.bookBlue,
    bookGreen: bookGreen ?? this.bookGreen,
    bookPeach: bookPeach ?? this.bookPeach,
    scrim: scrim ?? this.scrim,
  );

  @override
  HarukaColors lerp(ThemeExtension<HarukaColors>? other, double t) {
    if (other is! HarukaColors) return this;
    return HarukaColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      content: Color.lerp(content, other.content, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
      onSignal: Color.lerp(onSignal, other.onSignal, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      bookBlue: Color.lerp(bookBlue, other.bookBlue, t)!,
      bookGreen: Color.lerp(bookGreen, other.bookGreen, t)!,
      bookPeach: Color.lerp(bookPeach, other.bookPeach, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

abstract final class HarukaTheme {
  static SystemUiOverlayStyle systemUiOverlayStyle(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HarukaColors.of(context);
    final iconBrightness = theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: colors.canvas.withValues(alpha: 0),
      statusBarIconBrightness: iconBrightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: colors.content.withValues(alpha: 0),
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static const _light = HarukaColors(
    canvas: Color(0xfff4f7fb),
    content: Color(0xffffffff),
    selected: Color(0xffe8efff),
    signal: Color(0xffd8f36a),
    onSignal: Color(0xff26370b),
    positive: Color(0xff167a5a),
    warning: Color(0xffb45330),
    danger: Color(0xffbe3d47),
    bookBlue: Color(0xffe8efff),
    bookGreen: Color(0xffd8f36a),
    bookPeach: Color(0xffffefe7),
    scrim: Color(0x520f2030),
  );

  static const _dark = HarukaColors(
    canvas: Color(0xff101925),
    content: Color(0xff192535),
    selected: Color(0xff273b60),
    signal: Color(0xffd8f36a),
    onSignal: Color(0xff26370b),
    positive: Color(0xff72d8af),
    warning: Color(0xffffbc8b),
    danger: Color(0xffff8d98),
    bookBlue: Color(0xff273b60),
    bookGreen: Color(0xff405529),
    bookPeach: Color(0xff563c3a),
    scrim: Color(0x76040a12),
  );

  static ThemeData light() => _build(
    colors: _light,
    scheme: const ColorScheme.light(
      primary: Color(0xff2457ed),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffe8efff),
      onPrimaryContainer: Color(0xff152b42),
      secondary: Color(0xffd8f36a),
      onSecondary: Color(0xff26370b),
      surface: Color(0xffffffff),
      onSurface: Color(0xff152b42),
      onSurfaceVariant: Color(0xff58697b),
      outline: Color(0xffdde5ee),
      error: Color(0xffbe3d47),
    ),
  );

  static ThemeData dark() => _build(
    colors: _dark,
    scheme: const ColorScheme.dark(
      primary: Color(0xff9ab6ff),
      onPrimary: Color(0xff0b204a),
      primaryContainer: Color(0xff2954d3),
      onPrimaryContainer: Color(0xffedf3ff),
      secondary: Color(0xffd8f36a),
      onSecondary: Color(0xff26370b),
      surface: Color(0xff192535),
      onSurface: Color(0xffedf3ff),
      onSurfaceVariant: Color(0xffa8b8cc),
      outline: Color(0xff41536a),
      error: Color(0xffff8d98),
    ),
  );

  static ThemeData _build({required HarukaColors colors, required ColorScheme scheme}) => ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansSC',
    colorScheme: scheme,
    extensions: [colors],
    scaffoldBackgroundColor: colors.canvas,
    dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1, space: 1),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.22),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.25),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, height: 1.3),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.content,
      indicatorColor: colors.selected,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 6,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.canvas,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      barrierColor: colors.scrim,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontFamily: 'NotoSansSC',
        fontSize: 21,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontFamily: 'NotoSansSC',
        fontSize: 14,
        height: 1.55,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      modalBarrierColor: colors.scrim,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

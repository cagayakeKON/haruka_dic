import 'package:flutter/material.dart';

import 'theme.dart';

/// A shared fade/scale dialog route with a shorter exit than entry.
final class _HarukaDialogRoute<T> extends DialogRoute<T> {
  _HarukaDialogRoute({
    required super.context,
    required super.builder,
    required AnimationStyle animationStyle,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.requestFocus,
    super.anchorPoint,
    super.traversalEdgeBehavior,
    super.fullscreenDialog,
  }) : _reverseDuration =
           animationStyle.reverseDuration ?? animationStyle.duration ?? HarukaMotion.exit,
       super(animationStyle: animationStyle);

  final Duration _reverseDuration;

  @override
  Duration get reverseTransitionDuration => _reverseDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .012), end: Offset.zero).animate(eased),
        child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(eased), child: child),
      ),
    );
  }
}

Future<T?> showHarukaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
  bool waitForRemoval = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final route = _HarukaDialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor: barrierColor ?? HarukaColors.of(context).scrim,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    settings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle ?? HarukaMotion.dialogStyle(context),
  );
  final result = await navigator.push<T>(route);
  if (waitForRemoval) await route.completed;
  return result;
}

/// Motion timings shared by Material routes, dialogs, and sheets.
abstract final class HarukaMotion {
  static const pageEnter = Duration(milliseconds: 220);
  static const dialogEnter = Duration(milliseconds: 200);
  static const exit = Duration(milliseconds: 140);
  static const menu = Duration(milliseconds: 120);
  static const selection = Duration(milliseconds: 180);

  static bool reduced(BuildContext context, {bool reducedMotion = false}) =>
      reducedMotion || MediaQuery.disableAnimationsOf(context);

  static AnimationStyle dialogStyle(BuildContext context, {bool reducedMotion = false}) =>
      reduced(context, reducedMotion: reducedMotion)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          curve: Curves.easeOutCubic,
          duration: dialogEnter,
          reverseCurve: Curves.easeInCubic,
          reverseDuration: exit,
        );

  static AnimationStyle sheetStyle(BuildContext context, {bool reducedMotion = false}) =>
      dialogStyle(context, reducedMotion: reducedMotion);

  static Widget pageTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child, {
    bool root = false,
  }) {
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final departing = secondaryAnimation.drive(
      Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: const Interval(0, .64))),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([curved, departing]),
      child: child,
      builder: (context, content) => Opacity(
        opacity: (curved.value * departing.value).clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - curved.value) * 8), child: content),
      ),
    );
  }
}

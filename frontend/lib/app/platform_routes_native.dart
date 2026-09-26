import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

// Native targets never register the administrative surface.
List<RouteBase> platformRoutes(
  Widget Function(BuildContext, GoRouterState) adminBuilder,
  Widget Function(BuildContext, GoRouterState) passwordBuilder,
  Widget Function(BuildContext, GoRouterState) sessionsBuilder,
) => const [];

void configureUrlStrategy() {}

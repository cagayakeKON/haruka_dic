import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

List<RouteBase> platformRoutes(
  Widget Function(BuildContext, GoRouterState) adminBuilder,
  Widget Function(BuildContext, GoRouterState) passwordBuilder,
  Widget Function(BuildContext, GoRouterState) sessionsBuilder,
) => [
  GoRoute(path: '/admin', builder: adminBuilder),
  GoRoute(path: '/admin/login', builder: adminBuilder),
  GoRoute(path: '/admin/password', builder: passwordBuilder),
  GoRoute(path: '/admin/sessions', builder: sessionsBuilder),
];

void configureUrlStrategy() => usePathUrlStrategy();

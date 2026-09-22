import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'status_page.dart';

List<RouteBase> platformRoutes() => [
  GoRoute(path: '/admin', builder: (context, state) => const AdminPlaceholderPage()),
];

void configureUrlStrategy() => usePathUrlStrategy();

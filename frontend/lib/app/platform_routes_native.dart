import 'package:go_router/go_router.dart';

// Native targets never register the administrative surface.
List<RouteBase> platformRoutes() => const [];

void configureUrlStrategy() {}

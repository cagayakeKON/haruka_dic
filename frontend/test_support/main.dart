import 'package:flutter/widgets.dart';
import 'package:haruka/app/platform_routes.dart';

import '../test/support/controls_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  runApp(const ControlsApp());
}

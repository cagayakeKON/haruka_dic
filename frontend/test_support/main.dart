import 'package:flutter/widgets.dart';
import 'package:haruka/app/platform_routes.dart';

import 'controls_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  runApp(const ControlsApp());
}

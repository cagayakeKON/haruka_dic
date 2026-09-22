import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/haruka_app.dart';
import 'app/platform_routes.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategy();
  try {
    final platform = kIsWeb
        ? AppPlatform.web
        : defaultTargetPlatform == TargetPlatform.android
        ? AppPlatform.android
        : AppPlatform.windows;
    final config = AppConfig.fromEnvironment(platform: platform, flavor: appFlavor);
    runApp(HarukaApp(config: config));
  } on FormatException {
    // Never display raw configuration values or fall back to another service.
    runApp(const ConfigurationErrorApp());
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/haruka_app.dart';
import 'app/platform_routes.dart';
import 'core/config/app_config.dart';
import 'core/auth/email_action_link.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Remove a one-time mail secret before the router, telemetry, or error UI starts.
  final emailAction = captureEmailActionLink();
  configureUrlStrategy();
  try {
    final platform = kIsWeb
        ? AppPlatform.web
        : defaultTargetPlatform == TargetPlatform.android
        ? AppPlatform.android
        : AppPlatform.windows;
    final config = AppConfig.fromEnvironment(platform: platform, flavor: appFlavor);
    runApp(HarukaApp(config: config, emailAction: emailAction, installErrorHandlers: true));
  } on FormatException {
    // Never display raw configuration values or fall back to another service.
    runApp(const ConfigurationErrorApp());
  }
}

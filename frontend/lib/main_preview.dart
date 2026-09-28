import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/platform_routes.dart';
import 'app/preview_app.dart';

/// Explicit development preview entrypoint. The configured application uses main.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  configureUrlStrategy();
  runApp(const PreviewHarukaApp());
}

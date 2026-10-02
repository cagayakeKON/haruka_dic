// Independent release test driver. This is not the production main entry.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/request_ids.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/telemetry/telemetry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const build = String.fromEnvironment('HARUKA_BUILD');
  if (!kIsWeb || !kReleaseMode || !build.startsWith('telemetry-pipeline-')) {
    throw StateError('Independent release Web telemetry driver required');
  }
  final config = AppConfig.fromEnvironment(platform: AppPlatform.web);
  final api = ApiClient(config, requireSessionBinding: true);
  final auth = AuthController(AuthRepository(api, config), config);
  // Do not restore a session or authenticate. Only anonymous whitelist events.
  final telemetry = Telemetry(config, api, auth);
  final operation = newRequestId();
  final status = ValueNotifier<String>('Running independent telemetry driver');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    telemetry.captureException(category: 'flutter_framework', stack: details.stack);
  };
  try {
    await api.verifyInstance();
    for (final level in ['debug', 'info', 'warn']) {
      telemetry.log('app.started', level: level, operationId: operation);
    }
    telemetry.recordTiming('app.started', const Duration(milliseconds: 1));
    // Exercise the same capture API used by production's framework handler.
    // This reported test error is handled; it is not an unhandled termination.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('Independent telemetry test report'),
        stack: StackTrace.fromString('telemetry_pipeline.dart:1:1'),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await telemetry.flush();
    } while (telemetry.bufferedCount > 0 && DateTime.now().isBefore(deadline));
    status.value = telemetry.bufferedCount == 0
        ? 'Independent telemetry driver queue drained'
        : 'Independent telemetry driver upload incomplete';
  } finally {
    FlutterError.onError = previousHandler;
    await telemetry.dispose();
    auth.dispose();
    api.close();
  }
}

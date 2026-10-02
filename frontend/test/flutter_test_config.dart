import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Ordinary unit/widget tests have a finite backstop. Device integration tests
/// live outside this directory and retain their independently chosen timeout.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 60));
  }
  await testMain();
}

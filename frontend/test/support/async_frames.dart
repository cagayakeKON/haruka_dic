import 'package:flutter_test/flutter_test.dart';

/// Advance widget frames and the real async zone in bounded alternation.
/// Mock HTTP futures can be created during a build in the fake zone, while
/// router refreshes can finish in the real zone. Neither zone alone drains both.
Future<void> settleAsyncFrames(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    if (!tester.binding.hasScheduledFrame) return;
  }
  throw TestFailure('Widget frames did not settle after bounded real/fake async turns');
}

/// Wait for an observed business state, including continuations across both zones.
/// A quiet frame scheduler alone does not mean an HTTP/router future is complete.
Future<void> waitForAsyncState(
  WidgetTester tester,
  bool Function() isReady, {
  required String reason,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    if (isReady()) return;
  }
  throw TestFailure(reason);
}

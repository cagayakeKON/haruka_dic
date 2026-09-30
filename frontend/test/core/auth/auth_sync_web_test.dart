@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/auth/auth_sync_web.dart';

void main() {
  test('Web identity lock retains retired sign-out caller zone', () async {
    final sync = PlatformAuthSync('zone-${DateTime.now().microsecondsSinceEpoch}', (_) {});
    final marker = Object();
    final retiredBinding = Object();
    try {
      final observed = await runZoned(
        () => sync.withIdentityLock(() async {
          await Future<void>.delayed(Duration.zero);
          return Zone.current[marker];
        }),
        zoneValues: {marker: retiredBinding},
      );
      expect(observed, same(retiredBinding));
    } finally {
      sync.dispose();
    }
  });
}

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/coverage_semantics_probe.dart';

void main() {
  test('a second suite records its late call without adding another source denominator', () {
    expect(lateValue(), 24);
    expect(calledValue(), 'called');
    expect(neverCalledValue, isA<String Function()>());
  });
}

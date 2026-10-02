@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/coverage_semantics_probe.dart';

void main() {
  test('collector distinguishes called bodies from retained uncalled functions', () async {
    expect(calledValue(), 'called');
    // Retain the function as a value without invoking its body.
    expect(neverCalledValue, isA<String Function()>());
    expect(unicodeBranch(true), '晴空 🦋');
    expect(nestedBranch(true), 7);
    final object = CoverageProbe(3);
    expect(object.value, 3);
    expect(object.enabled, false);
    expect(object.computed, 4);
    expect(object.neverMethod, isA<int Function()>());
    expect(lateValue, isA<int Function()>());
    expect(await asynchronousProbe(), 9);
    expect(finalizationCount, 1);
  });
}

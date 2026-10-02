// A small test-only source for checking the compiler coverage collector.
String calledValue() {
  return 'called';
}

String neverCalledValue() {
  return 'never';
}

String unicodeBranch(bool selected) {
  if (selected) {
    return '晴空 🦋';
  }
  return 'unselected';
}

int nestedBranch(bool selected) {
  int nested() {
    return 91;
  }

  if (selected) {
    return 7;
  }
  return nested();
}

class CoverageProbe {
  CoverageProbe(this.value, {this.enabled = false});
  final int value;
  final bool enabled;

  int get computed => value + 1;

  int neverMethod() {
    return 77;
  }
}

int lateValue() {
  return 24;
}

int finalizationCount = 0;

Future<int> asynchronousProbe() async {
  await Future<void>.value();
  try {
    throw const FormatException('collector probe');
  } on FormatException {
    return 9;
  } finally {
    finalizationCount += 1;
  }
}

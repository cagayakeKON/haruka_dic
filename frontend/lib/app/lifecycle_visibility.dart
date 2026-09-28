import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Browser window blur reports `inactive` even while its tab stays visible.
/// Keep that page visible; an actual background transition only pauses timers.
bool foregroundAfterLifecycle(
  AppLifecycleState state, {
  required bool wasForeground,
  bool web = kIsWeb,
}) {
  if (web && state == AppLifecycleState.inactive) return wasForeground;
  return state == AppLifecycleState.resumed;
}

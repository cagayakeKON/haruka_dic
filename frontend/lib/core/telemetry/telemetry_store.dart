import 'dart:convert';

import 'telemetry_store_native.dart'
    if (dart.library.js_interop) 'telemetry_store_web.dart'
    as implementation;

final class TelemetrySnapshot {
  const TelemetrySnapshot({required this.clientSessionId, required this.events});
  final String clientSessionId;
  final List<Map<String, Object?>> events;
}

abstract interface class TelemetryStore {
  factory TelemetryStore(String instanceId) = implementation.PlatformTelemetryStore;
  Future<TelemetrySnapshot?> read(String scope);
  Future<void> write(String scope, TelemetrySnapshot snapshot);
  Future<void> clear(String scope);
}

// A fixed-size local filename/key; no user identifier is exposed in a path.
String telemetryScopeKey(String scope) {
  var hash = BigInt.parse('6c62272e07bb014262b821756295c58d', radix: 16);
  final mask = (BigInt.one << 128) - BigInt.one;
  final prime = BigInt.parse('0000000001000000000000000000013b', radix: 16);
  for (final byte in utf8.encode(scope)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(32, '0');
}

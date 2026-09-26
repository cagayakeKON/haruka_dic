import 'wire.dart';

final class TelemetryItemResult {
  const TelemetryItemResult({
    required this.index,
    required this.eventId,
    required this.status,
    required this.reason,
  });
  factory TelemetryItemResult.fromJson(Object? value) {
    final json = wireObject(value);
    final index = json['index'];
    final status = wireString(json['status']);
    if (index is! int ||
        index < 0 ||
        !const {'accepted', 'duplicate', 'rejected'}.contains(status)) {
      throw const FormatException('Invalid telemetry item result');
    }
    return TelemetryItemResult(
      index: index,
      eventId: json['event_id'] == null ? null : wireUuid(json['event_id']),
      status: status,
      reason: json['reason'] == null ? null : wireString(json['reason']),
    );
  }
  final int index;
  final String? eventId;
  final String status;
  final String? reason;
}

final class TelemetryBatchRead {
  const TelemetryBatchRead(this.results);
  factory TelemetryBatchRead.fromJson(Object? value) {
    final items = wireObject(value)['results'];
    if (items is! List<Object?>) throw const FormatException('Invalid telemetry batch');
    return TelemetryBatchRead(List.unmodifiable(items.map(TelemetryItemResult.fromJson)));
  }
  final List<TelemetryItemResult> results;
}

/// The only untyped JSON boundary. Exceptions never retain response contents.
Map<String, Object?> wireObject(Object? value) {
  if (value is! Map<String, Object?>) throw const FormatException('Expected JSON object');
  return value;
}

String wireString(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

String wireUuid(Object? value) {
  final text = wireString(value);
  if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(text)) {
    throw const FormatException('Expected UUID');
  }
  return text;
}

DateTime wireUtc(Object? value) {
  final text = wireString(value);
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|\+00:00)$',
  ).firstMatch(text);
  final timestamp = DateTime.tryParse(text);
  if (parts == null ||
      timestamp == null ||
      !timestamp.isUtc ||
      timestamp.year < 1 ||
      timestamp.year != int.parse(parts[1]!) ||
      timestamp.month != int.parse(parts[2]!) ||
      timestamp.day != int.parse(parts[3]!) ||
      timestamp.hour != int.parse(parts[4]!) ||
      timestamp.minute != int.parse(parts[5]!) ||
      timestamp.second != int.parse(parts[6]!)) {
    throw const FormatException('Expected UTC timestamp');
  }
  return timestamp;
}

/// Decimal is never converted to binary floating point.
String wireDecimal(Object? value) {
  final text = wireString(value);
  if (!RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(text)) {
    throw const FormatException('Expected decimal string');
  }
  return text;
}

sealed class OptionalValue<T> {
  const OptionalValue();

  static OptionalValue<T> read<T>(
    Map<String, Object?> json,
    String key,
    T Function(Object?) decode,
  ) => !json.containsKey(key)
      ? AbsentValue<T>()
      : json[key] == null
      ? NullValue<T>()
      : PresentValue<T>(decode(json[key]));
}

final class AbsentValue<T> extends OptionalValue<T> {
  const AbsentValue();
}

final class NullValue<T> extends OptionalValue<T> {
  const NullValue();
}

final class PresentValue<T> extends OptionalValue<T> {
  const PresentValue(this.value);
  final T value;
}

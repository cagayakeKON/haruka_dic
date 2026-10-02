import 'package:haruka/core/api/wire.dart';

// Test-only consumer of the backend's Pydantic contract prototype.
enum CompatibilityStatus { pending, complete, unknown }

sealed class CompatibilityCard {
  const CompatibilityCard();
  factory CompatibilityCard.fromJson(Object? value) {
    final json = wireObject(value);
    switch (json['kind']) {
      case 'text':
        return TextCard(wireString(json['text']));
      case 'choice':
        final choices = json['choices'];
        if (choices is! List<Object?>) throw const FormatException('Invalid choices');
        return ChoiceCard(List<String>.unmodifiable(choices.map(wireString)));
      default:
        throw const FormatException('Unsupported card kind');
    }
  }
}

final class TextCard extends CompatibilityCard {
  const TextCard(this.text);
  final String text;
}

final class ChoiceCard extends CompatibilityCard {
  const ChoiceCard(this.choices);
  final List<String> choices;
}

final class CompatibilityRead {
  CompatibilityRead.fromJson(Object? value) {
    final json = wireObject(value);
    resourceId = wireUuid(json['resource_id']);
    createdAt = wireUtc(json['created_at']);
    exactAmount = wireDecimal(json['exact_amount']);
    status = switch (wireString(json['status'])) {
      'pending' => CompatibilityStatus.pending,
      'complete' => CompatibilityStatus.complete,
      _ => CompatibilityStatus.unknown,
    };
    nullableOptional = OptionalValue.read(json, 'nullable_optional', wireString);
    card = CompatibilityCard.fromJson(json['card']);
  }
  late final String resourceId;
  late final DateTime createdAt;
  late final String exactAmount;
  late final CompatibilityStatus status;
  late final OptionalValue<String> nullableOptional;
  late final CompatibilityCard card;
}

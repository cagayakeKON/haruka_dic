import 'package:flutter/widgets.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_controller.dart';

final class LanguageOption {
  const LanguageOption({
    required this.code,
    required this.label,
    required this.ui,
    required this.learning,
    required this.explanation,
    required this.native,
  });

  final String code;
  final String label;
  final bool ui;
  final bool learning;
  final bool explanation;
  final bool native;
}

final class LanguageCapabilities {
  const LanguageCapabilities({required this.version, required this.languages});
  final int version;
  final List<LanguageOption> languages;

  List<String> codes(bool Function(LanguageOption) allowed) => [
    for (final item in languages)
      if (allowed(item)) item.code,
  ];

  String label(String code) =>
      languages.where((item) => item.code == code).map((item) => item.label).firstOrNull ?? code;

  static LanguageCapabilities decode(Object? value) {
    if (value is! Map || value['version'] is! int || value['languages'] is! List) {
      throw const FormatException('language capabilities');
    }
    final languages = <LanguageOption>[];
    for (final value in value['languages'] as List) {
      if (value is! Map || value['code'] is! String || value['label'] is! String) {
        throw const FormatException('language capability row');
      }
      languages.add(
        LanguageOption(
          code: value['code'] as String,
          label: value['label'] as String,
          ui: value['ui_supported'] == true,
          learning: value['learning_supported'] == true,
          explanation: value['explanation_supported'] == true,
          native: value['native_supported'] == true,
        ),
      );
    }
    return LanguageCapabilities(version: value['version'] as int, languages: languages);
  }
}

Future<LanguageCapabilities> readLanguageCapabilities(ApiClient api, AuthController auth) =>
    auth.authorizedRead((headers) async {
      final response = await api.getJson(
        '/api/v1/language-capabilities',
        LanguageCapabilities.decode,
        headers: headers,
      );
      return response.data;
    });

class LanguageCapabilitiesScope extends InheritedWidget {
  const LanguageCapabilitiesScope({
    required this.value,
    required this.failed,
    required this.retry,
    required super.child,
    super.key,
  });
  final LanguageCapabilities? value;
  final bool failed;
  final VoidCallback retry;

  static LanguageCapabilitiesScope? scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageCapabilitiesScope>();

  static LanguageCapabilities? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageCapabilitiesScope>()?.value;

  @override
  bool updateShouldNotify(LanguageCapabilitiesScope oldWidget) =>
      value != oldWidget.value || failed != oldWidget.failed;
}

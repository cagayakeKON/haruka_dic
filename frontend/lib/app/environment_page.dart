import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';

class EnvironmentPage extends StatelessWidget {
  const EnvironmentPage({required this.config, super.key});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Identified(
      id: UiTestIds.environmentPage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.environment, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                Text(strings.environmentDescription),
                const SizedBox(height: 32),
                for (final (label, value) in [
                  (
                    strings.environmentLabel,
                    config.environment == 'dev'
                        ? strings.devEnvironment
                        : strings.productionEnvironment,
                  ),
                  (strings.instanceLabel, config.instanceId),
                  (strings.apiLabel, config.apiBaseUrl.toString()),
                  (strings.applicationLabel, config.applicationId),
                ]) ...[
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SelectableText(value, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

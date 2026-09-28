import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/responses.dart';
import '../core/config/app_config.dart';
import '../generated/api_catalog.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';
import 'theme.dart';

class EnvironmentPage extends StatefulWidget {
  const EnvironmentPage({required this.config, required this.api, super.key});

  final AppConfig config;
  final ApiClient api;

  @override
  State<EnvironmentPage> createState() => _EnvironmentPageState();
}

class _EnvironmentPageState extends State<EnvironmentPage> {
  CancelToken? _request;
  String? _failure;
  bool _ready = false;

  Future<void> _check() async {
    if (_request != null) return;
    final token = CancelToken();
    setState(() {
      _request = token;
      _failure = null;
      _ready = false;
    });
    try {
      await widget.api.checkReadiness(cancelToken: token);
      if (mounted && identical(_request, token)) setState(() => _ready = true);
    } on ApiFailure catch (failure) {
      if (mounted && identical(_request, token)) setState(() => _failure = failure.code);
    } finally {
      if (mounted && identical(_request, token)) setState(() => _request = null);
    }
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                const SizedBox(height: 12),
                Text(
                  strings.environmentDescription,
                  style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outline),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Identified(
                          id: UiTestIds.checkConnection,
                          child: FilledButton(
                            onPressed: _request == null ? _check : null,
                            child: Text(
                              _request == null
                                  ? strings.checkConnection
                                  : strings.checkingConnection,
                            ),
                          ),
                        ),
                        if (_ready || _failure != null)
                          Identified(
                            id: UiTestIds.connectionStatus,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    _ready ? Icons.check_circle_outline : Icons.error_outline,
                                    color: _ready
                                        ? HarukaColors.of(context).positive
                                        : colors.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _ready
                                          ? strings.connectionReady
                                          : ApiCatalog.message(strings, _failure!),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outline),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                          Text(
                            label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(value, style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 24),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

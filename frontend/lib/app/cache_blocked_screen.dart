import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';

/// A terminal cache fault must cover private routes, including routes that do
/// not show cache settings. Memory-only online degradation does not use this.
class CacheBlockedScreen extends StatelessWidget {
  const CacheBlockedScreen({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (reason) {
      'cache_update_required' => strings.mockSettingCacheUpdateRequired,
      'cache_writer_unavailable' => strings.mockSettingCacheWriterUnavailable,
      _ => strings.cacheRevalidating,
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(message, style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Identified(
      id: UiTestIds.homePage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.shellTitle, style: theme.textTheme.headlineLarge),
                const SizedBox(height: 16),
                Text(strings.shellDescription, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 48),
                Text(strings.materialsTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(strings.materialsDescription),
                const SizedBox(height: 24),
                for (final (label, icon) in [
                  (strings.novels, Icons.auto_stories_outlined),
                  (strings.textbooks, Icons.menu_book_outlined),
                  (strings.exams, Icons.assignment_outlined),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Icon(icon, size: 28, color: theme.colorScheme.primary),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text(strings.unavailable),
                                ],
                              ),
                            ),
                          ],
                        ),
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

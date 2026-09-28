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
    final colors = theme.colorScheme;
    final materials = [
      (strings.novels, Icons.auto_stories_outlined),
      (strings.textbooks, Icons.menu_book_outlined),
      (strings.exams, Icons.assignment_outlined),
    ];
    return Identified(
      id: UiTestIds.homePage,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          bottomLeft: Radius.circular(6),
                          topRight: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(strings.shellTitle, style: theme.textTheme.headlineLarge),
                    const SizedBox(height: 48),
                    Text(strings.materialsTitle, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final (label, icon) in materials)
                          SizedBox(
                            width: cardWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border.all(color: colors.outline),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(22),
                                  topRight: Radius.circular(22),
                                  bottomLeft: Radius.circular(22),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(icon, size: 28, color: colors.primary),
                                    const SizedBox(height: 20),
                                    Text(label, style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    Text(
                                      strings.unavailable,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';
import '../generated/l10n/app_localizations.dart';
import '../generated/ui_test_ids.dart';
import '../shared/identified.dart';

class StatusPage extends StatelessWidget {
  const StatusPage({required this.id, required this.title, required this.description, super.key});

  final String id;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Identified(
    id: id,
    child: Scaffold(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Text(description, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 24),
                      Identified(
                        id: UiTestIds.backHome,
                        merge: true,
                        child: FilledButton(
                          onPressed: () => context.go(AppRoutes.home),
                          child: Text(AppLocalizations.of(context).backHome),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AdminPlaceholderPage extends StatelessWidget {
  const AdminPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return StatusPage(
      id: UiTestIds.adminPage,
      title: strings.adminTitle,
      description: strings.adminDescription,
    );
  }
}

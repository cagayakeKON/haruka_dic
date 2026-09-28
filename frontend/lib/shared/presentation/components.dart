import 'package:flutter/material.dart';

import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

String displayNameOrFallback(BuildContext context, String value) =>
    value.isEmpty ? AppLocalizations.of(context).mockProfileFallbackName : value;

abstract final class HarukaLayout {
  static const pageMaxWidth = 1120.0;
  static const queryMaxWidth = 800.0;
  static const formMaxWidth = 760.0;
  static const readingMaxWidth = 720.0;
}

class HarukaContentWidth extends StatelessWidget {
  const HarukaContentWidth({
    required this.child,
    this.maxWidth = HarukaLayout.pageMaxWidth,
    this.horizontalPadding = 24,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + horizontalPadding * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    ),
  );
}

enum HarukaDialogSize { compact, form, content }

class HarukaSurface extends StatelessWidget {
  const HarukaSurface({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 18,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: .7)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// Shared centered dialog layout for focused choices and material details.
class HarukaDialogSurface extends StatelessWidget {
  const HarukaDialogSurface({
    required this.title,
    required this.child,
    this.actions = const [],
    this.size = HarukaDialogSize.form,
    this.description,
    this.leadingAction,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final HarukaDialogSize size;
  final String? description;
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final maxHeight = availableHeight <= 160 ? availableHeight : availableHeight * .85;
    final width = switch (size) {
      HarukaDialogSize.compact => 400.0,
      HarukaDialogSize.form => 520.0,
      HarukaDialogSize.content => 760.0,
    };
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).dialogTheme.titleTextStyle)),
                  IconButton(
                    tooltip: AppLocalizations.of(context).mockMaterialClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(description!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
              ],
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(child: child),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                if (leadingAction != null)
                  Align(alignment: Alignment.centerLeft, child: leadingAction!),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HarukaDialogAction extends StatelessWidget {
  const HarukaDialogAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: foreground),
      title: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
      onTap: onPressed,
    );
  }
}

class HarukaEmpty extends StatelessWidget {
  const HarukaEmpty({required this.title, required this.message, this.action, super.key});
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => HarukaSurface(
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class HarukaPill extends StatelessWidget {
  const HarukaPill({required this.label, required this.selected, required this.onTap, super.key});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
        backgroundColor: selected ? roles.selected : null,
        minimumSize: const Size(42, 37),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(label),
    );
  }
}

class HarukaCardMotion extends StatelessWidget {
  const HarukaCardMotion({required this.child, this.show = true, super.key});
  final Widget child;
  final bool show;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, .025),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

import 'reference_controller.dart';

/// One account-scoped reference flow shared by the library, reader and
/// collection surfaces. The application replaces the controller on identity
/// or authorization-version changes.
class ReferenceFeatureScope extends InheritedNotifier<ReferenceController> {
  const ReferenceFeatureScope({
    required ReferenceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ReferenceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReferenceFeatureScope>()?.notifier;
}

/// Root dialogs do not inherit a route's authorization gate. Keep their
/// private content tied to the exact account and permission generation that
/// opened them, and close before a revoked scope can render another frame.
class ReferenceDialogGuard extends StatelessWidget {
  const ReferenceDialogGuard({
    required this.controller,
    required this.openingScope,
    required this.allowed,
    required this.child,
    super.key,
  });

  final ReferenceController controller;
  final bool Function() allowed;
  final Widget child;
  final String openingScope;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.auth,
    builder: (context, _) {
      if (controller.auth.isAuthenticated &&
          referenceScope(controller.auth, 'reference') == openingScope &&
          allowed()) {
        return child;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    },
  );
}

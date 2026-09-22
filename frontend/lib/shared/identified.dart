import 'package:flutter/widgets.dart';

/// Shares one registered identifier between Flutter and external semantic locators.
/// The child's accessible name, role and state remain intact.
class Identified extends StatelessWidget {
  const Identified({required this.id, required this.child, this.merge = false, super.key});

  final String id;
  final Widget child;
  final bool merge;

  @override
  Widget build(BuildContext context) {
    final identified = Semantics(key: ValueKey(id), identifier: id, child: child);
    return merge ? MergeSemantics(child: identified) : identified;
  }
}

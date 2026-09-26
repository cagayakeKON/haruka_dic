import 'package:flutter/widgets.dart';

/// Exposes the registered control ID to Flutter tests and external UI drivers.
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

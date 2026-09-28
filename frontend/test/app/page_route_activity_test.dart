import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/page_route_activity.dart';

class _PageProbe extends StatefulWidget {
  const _PageProbe({required this.events});

  final List<String> events;

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  late final activity = PageRouteActivity(
    onCovered: () => widget.events.add('covered'),
    onReturned: () => widget.events.add('returned'),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    activity.bind(context);
  }

  @override
  void dispose() {
    activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('base page'));
}

void main() {
  testWidgets('popup routes keep a page active; a page above a popup still counts', (tester) async {
    final events = <String>[];
    final observer = PageRouteActivityObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: _PageProbe(events: events),
      ),
    );

    final dialog = showDialog<void>(
      context: tester.element(find.text('base page')),
      builder: (_) => const AlertDialog(title: Text('popup')),
    );
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    final page = MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('next page')));
    final pageResult = navigatorKey.currentState!.push(page);
    await tester.pumpAndSettle();
    expect(events, ['covered']);
    navigatorKey.currentState!.pop();
    await pageResult;
    await tester.pumpAndSettle();
    expect(events, ['covered', 'returned']);
    navigatorKey.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(events, ['covered', 'returned']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('observer resets its page stack when a Navigator is remounted', (tester) async {
    final observer = PageRouteActivityObserver();
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('first'),
        navigatorObservers: [observer],
        home: _PageProbe(events: events),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('second'),
        navigatorObservers: [observer],
        home: _PageProbe(events: events),
      ),
    );
    expect(
      observer.isPageCurrent(
        ModalRoute.of(tester.element(find.text('base page')))! as PageRoute<dynamic>,
      ),
      isTrue,
    );
    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

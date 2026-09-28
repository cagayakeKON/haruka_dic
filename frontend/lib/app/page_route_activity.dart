import 'package:flutter/material.dart';

/// Tracks the top page even when a PopupRoute sits above it. Install one
/// instance per Navigator; a root dialog and a nested router remain separate.
final class PageRouteActivityObserver extends NavigatorObserver {
  static final Expando<PageRouteActivityObserver> _installed = Expando();
  NavigatorState? _owner;
  final List<Route<dynamic>> _routes = [];
  final Map<PageRoute<dynamic>, Set<PageRouteActivity>> _listeners = {};

  static PageRouteActivityObserver? forNavigator(NavigatorState? navigator) =>
      navigator == null ? null : _installed[navigator];

  PageRoute<dynamic>? get _topPage {
    for (final route in _routes.reversed) {
      if (route is PageRoute<dynamic>) return route;
    }
    return null;
  }

  bool isPageCurrent(PageRoute<dynamic> route) => identical(_topPage, route);

  void subscribe(PageRouteActivity listener, PageRoute<dynamic> route) =>
      _listeners.putIfAbsent(route, () => {}).add(listener);

  void unsubscribe(PageRouteActivity listener, PageRoute<dynamic> route) {
    final listeners = _listeners[route];
    listeners?.remove(listener);
    if (listeners?.isEmpty ?? false) _listeners.remove(route);
  }

  void _notifyChange(PageRoute<dynamic>? before) {
    final after = _topPage;
    if (identical(before, after)) return;
    for (final listener in _listeners[before]?.toList() ?? const <PageRouteActivity>[]) {
      listener.didPushNext();
    }
    for (final listener in _listeners[after]?.toList() ?? const <PageRouteActivity>[]) {
      listener.didPopNext();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final owner = navigator;
    if (owner != null && !identical(_owner, owner)) {
      _owner = owner;
      _routes.clear();
      _listeners.clear();
      _installed[owner] = this;
    }
    final before = _topPage;
    final previousIndex = previousRoute == null ? -1 : _routes.indexOf(previousRoute);
    _routes.insert(previousIndex < 0 ? _routes.length : previousIndex + 1, route);
    _notifyChange(before);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final before = _topPage;
    _routes.remove(route);
    _notifyChange(before);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final before = _topPage;
    _routes.remove(route);
    _notifyChange(before);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final before = _topPage;
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _notifyChange(before);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// A page remains active while a PopupRoute is shown over it. A QueryPage
/// hosted inside a dialog has no PageRoute of its own and is active there.
final class PageRouteActivity implements RouteAware {
  PageRouteActivity({this.onCovered, this.onReturned});

  final VoidCallback? onCovered;
  final VoidCallback? onReturned;
  PageRouteActivityObserver? _observer;
  PageRoute<dynamic>? _route;
  bool _current = true;

  bool get isCurrent => _current;

  void bind(BuildContext context) {
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is! PageRoute<dynamic>) {
      _unsubscribe();
      _current = true;
      return;
    }
    final observer = PageRouteActivityObserver.forNavigator(modalRoute.navigator);
    if (identical(_route, modalRoute) && identical(_observer, observer)) return;
    _unsubscribe();
    _route = modalRoute;
    _observer = observer;
    // Standalone hosts without an observer do not mistake a popup for a page
    // departure. Navigation tests install the same observer as the app.
    _current = observer?.isPageCurrent(modalRoute) ?? true;
    observer?.subscribe(this, modalRoute);
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {
    _current = false;
    onCovered?.call();
  }

  @override
  void didPopNext() {
    _current = true;
    onReturned?.call();
  }

  void _unsubscribe() {
    final route = _route;
    if (route != null) _observer?.unsubscribe(this, route);
    _observer = null;
    _route = null;
  }

  void dispose() => _unsubscribe();
}

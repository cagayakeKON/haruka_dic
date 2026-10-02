import 'dart:async';

import 'package:flutter/material.dart';

import 'package:haruka/generated/l10n/app_localizations.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';

import '../data/material_catalog.dart';
import 'material_catalog_scope.dart';

/// Requests missing/query-changed data. Authorization is checked separately by
/// the shared auth/cache scope; menus and route return do not invalidate data.
class MaterialCatalogAccess extends StatefulWidget {
  const MaterialCatalogAccess({
    required this.builder,
    this.query = const MaterialCatalogQuery(),
    this.loadingBuilder,
    super.key,
  });

  final Widget Function(BuildContext, MaterialCatalog) builder;
  final MaterialCatalogQuery query;
  final WidgetBuilder? loadingBuilder;

  @override
  State<MaterialCatalogAccess> createState() => _MaterialCatalogAccessState();
}

class _MaterialCatalogAccessState extends State<MaterialCatalogAccess> with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: () => _routeCurrent = false,
    onReturned: _onPageReturned,
  );
  MaterialCatalog? _catalog;
  Timer? _queryTimer;
  bool _entered = false;
  bool _refreshFailed = false;
  bool _foreground = true;
  bool _routeCurrent = false;
  bool _needsVisibleRecheck = false;
  int _generation = 0;
  int? _inFlightGeneration;

  bool get _visible => mounted && _foreground && _routeCurrent;

  void _onPageReturned() {
    if (!mounted) return;
    _routeCurrent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible) _requestVisibleRefresh();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MaterialCatalogAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.key == widget.query.key) return;
    _queryTimer?.cancel();
    _generation++;
    _entered = false;
    final delay = oldWidget.query.type == widget.query.type
        ? const Duration(milliseconds: 300)
        : Duration.zero;
    _queryTimer = Timer(delay, () {
      // A changed query supersedes the previous catalog request even if its
      // source never settles. The catalog retires the older request generation.
      if (_visible) unawaited(_refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = MaterialCatalogScope.of(context);
    _pageActivity.bind(context);
    final routeCurrent = _pageActivity.isCurrent;
    final catalogChanged = !identical(_catalog, catalog);
    final becameVisible = !_routeCurrent && routeCurrent;
    _routeCurrent = routeCurrent;
    if (!catalogChanged && !becameVisible) return;
    if (catalogChanged) _catalog = catalog;
    if (catalogChanged) _entered = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible && identical(_catalog, catalog)) _requestVisibleRefresh();
    });
  }

  void _requestVisibleRefresh() {
    if (!_visible) return;
    if (_entered &&
        (_catalog?.status == MaterialCatalogStatus.ready ||
            _catalog?.status == MaterialCatalogStatus.stale)) {
      return;
    }
    _queryTimer?.cancel();
    if (_inFlightGeneration != null) {
      _needsVisibleRecheck = true;
      setState(() => _entered = false);
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh({bool gate = true, bool preserveCurrent = false}) async {
    final catalog = _catalog;
    if (catalog == null) return;
    _needsVisibleRecheck = false;
    final generation = ++_generation;
    _inFlightGeneration = generation;
    if (gate) {
      setState(() {
        _entered = false;
        _refreshFailed = false;
      });
    }
    var failed = false;
    try {
      await catalog.refresh(query: widget.query, preserveCurrent: preserveCurrent);
    } on Object {
      failed = true;
    }
    if (_inFlightGeneration == generation) {
      _inFlightGeneration = null;
      if (_needsVisibleRecheck && _visible) {
        _needsVisibleRecheck = false;
        unawaited(_refresh());
        return;
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _entered = !_needsVisibleRecheck;
      _refreshFailed = failed;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void dispose() {
    _generation++;
    _queryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageActivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = MaterialCatalogScope.of(context);
    Widget content;
    if (!_entered ||
        catalog.status == MaterialCatalogStatus.loading ||
        catalog.status == MaterialCatalogStatus.initial) {
      content =
          widget.loadingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator());
    } else if (_refreshFailed ||
        (catalog.status != MaterialCatalogStatus.ready &&
            catalog.status != MaterialCatalogStatus.stale)) {
      content = Center(child: Text(AppLocalizations.of(context).mockMaterialUnavailableMessage));
    } else {
      content = widget.builder(context, catalog);
    }
    return Stack(
      children: [
        content,
        if (_entered && catalog.status == MaterialCatalogStatus.stale)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              child: Row(
                children: [
                  Expanded(child: Text(AppLocalizations.of(context).apiUnknownError)),
                  TextButton(
                    onPressed: () => unawaited(_refresh(gate: false, preserveCurrent: true)),
                    child: Text(AppLocalizations.of(context).authRetry),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

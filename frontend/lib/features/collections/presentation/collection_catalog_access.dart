import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haruka/app/page_route_activity.dart';
import 'package:haruka/app/lifecycle_visibility.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../data/collection_catalog.dart';
import 'collection_catalog_scope.dart';

/// New list entries and filter changes recheck both collection and notebook
/// read actions before the private rows become visible.
class CollectionCatalogAccess extends StatefulWidget {
  const CollectionCatalogAccess({
    required this.builder,
    this.loadingBuilder,
    this.unavailableBuilder,
    this.query = const CollectionListQuery(),
    this.allCollections = false,
    super.key,
  });

  final Widget Function(BuildContext, CollectionCatalog) builder;
  final Widget Function(BuildContext, CollectionCatalog)? loadingBuilder;
  final Widget Function(BuildContext, CollectionCatalog)? unavailableBuilder;
  final CollectionListQuery query;
  final bool allCollections;

  @override
  State<CollectionCatalogAccess> createState() => _CollectionCatalogAccessState();
}

class _CollectionCatalogAccessState extends State<CollectionCatalogAccess>
    with WidgetsBindingObserver {
  late final PageRouteActivity _pageActivity = PageRouteActivity(
    onCovered: () => _routeCurrent = false,
    onReturned: _onPageReturned,
  );
  CollectionCatalog? _catalog;
  Timer? _timer;
  Timer? _queryTimer;
  bool _entered = false;
  bool _foreground = true;
  bool _routeCurrent = false;
  bool _needsVisibleRecheck = false;
  int _generation = 0;
  int? _inFlightGeneration;

  bool get _visible => mounted && _foreground && _routeCurrent;

  void _onPageReturned() {
    if (!mounted) return;
    _routeCurrent = true;
    setState(() => _entered = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible) _requestVisibleRefresh();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_visible && _inFlightGeneration == null) {
        unawaited(_refresh(gate: false, preserveCurrent: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = CollectionCatalogScope.of(context);
    _pageActivity.bind(context);
    final routeCurrent = _pageActivity.isCurrent;
    final catalogChanged = !identical(_catalog, catalog);
    final becameVisible = !_routeCurrent && routeCurrent;
    _routeCurrent = routeCurrent;
    if (!catalogChanged && !becameVisible) return;
    if (catalogChanged) _catalog = catalog;
    _entered = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible && identical(_catalog, catalog)) _requestVisibleRefresh();
    });
  }

  void _requestVisibleRefresh() {
    if (!_visible) return;
    if (_inFlightGeneration != null) {
      _needsVisibleRecheck = true;
      setState(() => _entered = false);
      return;
    }
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant CollectionCatalogAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.key == widget.query.key &&
        oldWidget.allCollections == widget.allCollections) {
      return;
    }
    _queryTimer?.cancel();
    _generation++;
    _entered = false;
    final delay =
        oldWidget.query.kind == widget.query.kind &&
            oldWidget.query.notebookId == widget.query.notebookId
        ? const Duration(milliseconds: 300)
        : Duration.zero;
    _queryTimer = Timer(delay, () {
      if (_visible) unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool gate = true, bool preserveCurrent = false}) async {
    final catalog = _catalog;
    if (catalog == null) return;
    _needsVisibleRecheck = false;
    final generation = ++_generation;
    _inFlightGeneration = generation;
    if (gate) setState(() => _entered = false);
    await Future.wait([
      if (widget.allCollections)
        catalog.refreshAllCollections(force: true, preserveCurrent: preserveCurrent)
      else
        catalog.refreshCollections(
          query: widget.query,
          force: true,
          preserveCurrent: preserveCurrent,
        ),
      catalog.refreshNotebooks(force: true, preserveCurrent: preserveCurrent),
    ]);
    if (_inFlightGeneration == generation) {
      _inFlightGeneration = null;
      if (_needsVisibleRecheck && _visible) {
        _needsVisibleRecheck = false;
        unawaited(_refresh());
        return;
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() => _entered = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = foregroundAfterLifecycle(state, wasForeground: _foreground);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _queryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageActivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CollectionCatalogScope.of(context);
    final collectionStatus = widget.allCollections
        ? catalog.allCollectionStatus
        : catalog.collectionStatus;
    Widget content;
    if (!_entered ||
        collectionStatus == CollectionCatalogStatus.initial ||
        collectionStatus == CollectionCatalogStatus.loading ||
        catalog.notebookStatus == CollectionCatalogStatus.initial ||
        catalog.notebookStatus == CollectionCatalogStatus.loading) {
      content =
          widget.loadingBuilder?.call(context, catalog) ??
          const Center(child: CircularProgressIndicator());
    } else if ((collectionStatus != CollectionCatalogStatus.ready &&
            collectionStatus != CollectionCatalogStatus.stale) ||
        (catalog.notebookStatus != CollectionCatalogStatus.ready &&
            catalog.notebookStatus != CollectionCatalogStatus.stale)) {
      content =
          widget.unavailableBuilder?.call(context, catalog) ??
          Center(child: Text(AppLocalizations.of(context).authUnavailableShort));
    } else {
      content = widget.builder(context, catalog);
    }
    return Stack(
      children: [
        content,
        if (_entered &&
            (collectionStatus == CollectionCatalogStatus.stale ||
                catalog.notebookStatus == CollectionCatalogStatus.stale))
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

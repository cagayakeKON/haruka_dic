@TestOn('browser')
library;

import 'dart:ui_web' as ui_web;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:haruka/app/platform_routes_web.dart';
import 'package:web/web.dart' as web;

void main() {
  test('Web startup keeps public route paths and query parameters without navigating the host', () {
    final originalUrl = web.window.location.href;
    final existingBase = web.document.querySelector('base');
    final originalBase = existingBase?.getAttribute('href');
    final base = existingBase ?? web.document.createElement('base');
    base.setAttribute('href', '/');
    if (existingBase == null) web.document.head!.appendChild(base);
    final originalStrategy = ui_web.urlStrategy;
    final hadCustomStrategy = ui_web.isCustomUrlStrategySet;
    // The locked engine documents this reset specifically for isolated tests.
    ui_web.debugResetCustomUrlStrategy();
    try {
      configureUrlStrategy();
      final strategy = ui_web.urlStrategy;
      expect(strategy, isA<PathUrlStrategy>());
      expect(strategy!.getPath(), '${web.window.location.pathname}${web.window.location.search}');
      expect(
        strategy.prepareExternalUrl('/settings/profile?field=display_name&return=%2Faccount'),
        '/settings/profile?field=display_name&return=%2Faccount',
      );
      expect(web.window.location.href, originalUrl);
    } finally {
      ui_web.debugResetCustomUrlStrategy();
      if (hadCustomStrategy) ui_web.urlStrategy = originalStrategy;
      if (existingBase == null) {
        base.remove();
      } else if (originalBase == null) {
        base.removeAttribute('href');
      } else {
        base.setAttribute('href', originalBase);
      }
    }
  });
}

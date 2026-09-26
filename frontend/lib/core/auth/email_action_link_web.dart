import 'package:web/web.dart' as web;

import 'email_action_link.dart';

CapturedEmailAction? captureEmailActionLink() {
  final location = web.window.location;
  final path = location.pathname;
  final fragment = location.hash;
  if (fragment.isEmpty) return null;
  // Fragments never reach the HTTP server, but must still leave browser history
  // before a screenshot, navigation, or error report can capture the page.
  web.window.history.replaceState(
    web.window.history.state,
    '',
    '${location.pathname}${location.search}',
  );
  if (path != '/verify-email' && path != '/reset-password') return null;
  final token = validatedEmailActionFragment(
    fragment.startsWith('#') ? fragment.substring(1) : fragment,
  );
  return token == null ? null : CapturedEmailAction(path: path, token: token);
}

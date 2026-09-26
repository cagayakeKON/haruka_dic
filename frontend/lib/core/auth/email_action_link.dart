import 'email_action_link_native.dart'
    if (dart.library.js_interop) 'email_action_link_web.dart'
    as implementation;

/// Captured before router startup, so a browser fragment can neither conflict
/// with routing nor remain in history until a page happens to build.
final class CapturedEmailAction {
  const CapturedEmailAction({required this.path, required this.token});

  final String path;
  final String token;
}

CapturedEmailAction? captureEmailActionLink() => implementation.captureEmailActionLink();

String? validatedEmailActionFragment(String fragment) {
  if (!fragment.startsWith('token=') || fragment.contains('&')) return null;
  final token = fragment.substring('token='.length);
  return RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ? token : null;
}

/// A pasted link is accepted only from the published action-link origin and
/// the exact action path. This also prevents cross-purpose token use.
String? tokenFromPastedActionLink({
  required String pasted,
  required Uri trustedBase,
  required String actionPath,
}) {
  final candidate = Uri.tryParse(pasted.trim());
  if (candidate == null ||
      candidate.userInfo.isNotEmpty ||
      candidate.hasQuery ||
      candidate.scheme != trustedBase.scheme ||
      candidate.host != trustedBase.host ||
      candidate.port != trustedBase.port ||
      candidate.path != actionPath ||
      candidate.fragment.isEmpty) {
    return null;
  }
  return validatedEmailActionFragment(candidate.fragment);
}

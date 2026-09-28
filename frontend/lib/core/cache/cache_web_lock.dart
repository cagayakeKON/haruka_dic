import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A Web Lock lease shared by all tabs and workers on the same origin.
final class WebCacheLock {
  WebCacheLock._(this._release, this._request);

  final Completer<JSAny?> _release;
  final Future<JSAny?> _request;

  static String partitionPublishName(String partition) => 'haruka-cache:$partition:publish';

  static Future<WebCacheLock?> acquire(String name, String mode, {bool ifAvailable = false}) async {
    final entered = Completer<bool>();
    final release = Completer<JSAny?>();
    final callback = ((web.Lock? lock) {
      if (lock == null) {
        entered.complete(false);
        return Future<JSAny?>.value(null).toJS;
      }
      entered.complete(true);
      return release.future.toJS;
    }).toJS;
    late final Future<JSAny?> request;
    try {
      request = web.window.navigator.locks
          .request(name, web.LockOptions(mode: mode, ifAvailable: ifAvailable), callback)
          .toDart;
    } catch (error) {
      throw StateError('Web Locks unavailable: $error');
    }
    unawaited(
      request.catchError((Object error) {
        if (!entered.isCompleted) entered.completeError(error);
        return null;
      }),
    );
    if (!await entered.future) return null;
    return WebCacheLock._(release, request);
  }

  Future<void> release() async {
    if (!_release.isCompleted) _release.complete(null);
    await _request;
  }
}

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'auth_sync.dart';

final class PlatformAuthSync implements AuthSync {
  PlatformAuthSync(String instanceId, void Function(AuthSyncEvent) onEvent)
    : _instanceId = instanceId,
      _channel = web.BroadcastChannel('haruka.auth.$instanceId') {
    _channel.onmessage = ((web.MessageEvent event) {
      final value = event.data?.dartify();
      if (value == 'start') onEvent(AuthSyncEvent.started);
      if (value == 'changed') onEvent(AuthSyncEvent.changed);
    }).toJS;
  }

  final String _instanceId;
  final web.BroadcastChannel _channel;

  @override
  void publishStarted() => _channel.postMessage('start'.toJS);

  @override
  void publishChanged() => _channel.postMessage('changed'.toJS);

  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) async {
    final callerZone = Zone.current;
    T? result;
    final callback = ((web.Lock? _) => (() async {
      // JS callbacks do not retain the retired sign-out authorization zone.
      result = await callerZone.run(action);
      return null;
    })().toJS).toJS;
    await web.window.navigator.locks.request('haruka.auth.$_instanceId', callback).toDart;
    return result as T;
  }

  String _marker(String audience) => 'haruka.signed_out.$_instanceId.$audience';

  @override
  bool locallySignedOut(String audience) =>
      web.window.localStorage.getItem(_marker(audience)) == '1';

  @override
  void setLocallySignedOut(String audience, bool value) {
    if (value) {
      web.window.localStorage.setItem(_marker(audience), '1');
    } else {
      web.window.localStorage.removeItem(_marker(audience));
    }
  }

  @override
  void dispose() => _channel.close();
}

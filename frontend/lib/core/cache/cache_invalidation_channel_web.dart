import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'cache_invalidation_hint.dart';

/// Advisory cross-tab refresh hints. No body, key, grant or identity is sent.
final class CacheInvalidationChannel {
  CacheInvalidationChannel(String partition, void Function(String, Set<String>?) onMessage) {
    if (!web.window.hasProperty('BroadcastChannel'.toJS).toDart) return;
    final channel = web.BroadcastChannel('haruka-cache:$partition:events');
    channel.onmessage = ((web.MessageEvent message) {
      final data = message.data;
      if (data == null || !data.isA<JSString>()) return;
      final hint = decodeCacheHint((data as JSString).toDart);
      if (hint != null) onMessage(hint.$1, hint.$2);
    }).toJS;
    _channel = channel;
  }

  web.BroadcastChannel? _channel;

  void publish(String type, [Set<String>? tags]) {
    if (type != 'invalidate' && type != 'clear' && type != 'identity') return;
    _channel?.postMessage(encodeCacheHint(type, tags).toJS);
  }

  void close() {
    _channel?.close();
    _channel = null;
  }
}

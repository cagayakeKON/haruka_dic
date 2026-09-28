import 'dart:async';

import 'cache_web_lock.dart';

// A synchronous pin release requests browser unlock; the Web Locks promise
// settles later. New local acquisitions wait for that exact lock name first.
final _pendingReleases = <String, Set<Future<void>>>{};

Future<void> _waitForLocalReleases(String name) async {
  final pending = _pendingReleases[name];
  if (pending == null || pending.isEmpty) return;
  await Future.wait(pending.toList());
}

void _release(String name, WebCacheLock lease) {
  final pending = lease.release();
  final releases = _pendingReleases.putIfAbsent(name, () => <Future<void>>{});
  releases.add(pending);
  unawaited(
    pending.then(
      (_) {
        releases.remove(pending);
        if (releases.isEmpty && identical(_pendingReleases[name], releases)) {
          _pendingReleases.remove(name);
        }
      },
      onError: (Object _) {
        // An uncertain unlock stays in the set, so a later acquisition fails
        // closed instead of assuming the browser has released the lock.
      },
    ),
  );
}

Future<void Function()> acquireCacheEntryPin(String partition, String key) async {
  final name = 'haruka-cache:$partition:text:$key';
  await _waitForLocalReleases(name);
  final lease = await WebCacheLock.acquire(name, 'shared');
  if (lease == null) throw StateError('Cache text pin unavailable');
  return () => _release(name, lease);
}

Future<void Function()?> tryCacheEntryEviction(String partition, String key) async {
  final name = 'haruka-cache:$partition:text:$key';
  try {
    await _waitForLocalReleases(name);
  } on Object {
    return null;
  }
  final lease = await WebCacheLock.acquire(name, 'exclusive', ifAvailable: true);
  return lease == null ? null : () => _release(name, lease);
}

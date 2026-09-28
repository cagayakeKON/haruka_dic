import 'dart:async';

/// Linux file locks are process scoped, so separate handles in one process
/// need their own shared-reader/exclusive-writer gate as well.
final class AudioProcessLock {
  static final Map<String, _State> _states = {};

  static Future<AudioProcessLease?> acquire(
    String key, {
    bool shared = false,
    bool ifAvailable = false,
  }) async {
    final state = _states.putIfAbsent(key, _State.new);
    if (!ifAvailable) state.waiters++;
    if (!shared && !ifAvailable) state.waitingWriters++;
    try {
      while (true) {
        final available = shared
            ? !state.writer && state.waitingWriters == 0
            : !state.writer && state.readers == 0;
        if (available) {
          if (shared) {
            state.readers++;
          } else {
            state.writer = true;
          }
          return AudioProcessLease._(key, state, shared);
        }
        if (ifAvailable) return null;
        final changed = state.changed.future;
        await changed;
      }
    } finally {
      if (!shared && !ifAvailable) state.waitingWriters--;
      if (!ifAvailable) state.waiters--;
      state.removeIfIdle(key);
    }
  }
}

final class _State {
  int readers = 0;
  int waitingWriters = 0;
  int waiters = 0;
  bool writer = false;
  Completer<void> changed = Completer<void>();

  void notify() {
    final old = changed;
    changed = Completer<void>();
    old.complete();
  }

  void removeIfIdle(String key) {
    if (readers == 0 && !writer && waiters == 0) {
      AudioProcessLock._states.remove(key);
    }
  }
}

final class AudioProcessLease {
  AudioProcessLease._(this._key, this._state, this._shared);

  final String _key;
  final _State _state;
  final bool _shared;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    if (_shared) {
      _state.readers--;
    } else {
      _state.writer = false;
    }
    _state.notify();
    _state.removeIfIdle(_key);
  }
}

import 'dart:async';

final _readers = <String, int>{};
final _writers = <String, Completer<void>>{};

Future<void Function()> acquireCacheEntryPin(String partition, String key) async {
  final name = '$partition:$key';
  while (_writers.containsKey(name)) {
    await _writers[name]!.future;
  }
  _readers[name] = (_readers[name] ?? 0) + 1;
  var released = false;
  return () {
    if (released) return;
    released = true;
    final count = _readers[name]! - 1;
    if (count == 0) {
      _readers.remove(name);
    } else {
      _readers[name] = count;
    }
  };
}

Future<void Function()?> tryCacheEntryEviction(String partition, String key) async {
  final name = '$partition:$key';
  if (_readers.containsKey(name) || _writers.containsKey(name)) return null;
  final lease = Completer<void>();
  _writers[name] = lease;
  return () {
    if (lease.isCompleted) return;
    _writers.remove(name);
    lease.complete();
  };
}

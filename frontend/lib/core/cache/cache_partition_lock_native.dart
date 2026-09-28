import 'dart:async';

/// The native backend holds the cross-process writer lock for its lifetime;
/// this short in-process mutex also serializes independently scheduled tasks.
final _tails = <String, Future<void>>{};

Future<T> withCachePartitionPublishLock<T>(String partition, Future<T> Function() operation) async {
  final previous = _tails[partition];
  final done = Completer<void>();
  _tails[partition] = done.future;
  if (previous != null) await previous;
  try {
    return await operation();
  } finally {
    if (identical(_tails[partition], done.future)) unawaited(_tails.remove(partition)!);
    done.complete();
  }
}

/// Recovery already holds the byte publish lock, then takes the index mutex.
Future<T> withCachePartitionRecoveryIndexLock<T>(
  String partition,
  Future<T> Function() operation,
) => withCachePartitionPublishLock(partition, operation);

import 'cache_web_lock.dart';

/// Serializes short index publications and epoch changes across browser tabs.
Future<T> withCachePartitionPublishLock<T>(String partition, Future<T> Function() operation) async {
  final lease = await WebCacheLock.acquire(
    WebCacheLock.partitionPublishName(partition),
    'exclusive',
  );
  if (lease == null) throw StateError('Cache publish lock unavailable');
  try {
    return await operation();
  } finally {
    await lease.release();
  }
}

/// The byte publish lock uses this same Web Lock name; recovery must not
/// reacquire it while already inside the byte store's publish callback.
Future<T> withCachePartitionRecoveryIndexLock<T>(
  String partition,
  Future<T> Function() operation,
) => operation();

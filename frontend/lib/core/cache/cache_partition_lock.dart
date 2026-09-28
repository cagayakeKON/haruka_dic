export 'cache_partition_lock_native.dart'
    if (dart.library.js_interop) 'cache_partition_lock_web.dart'
    show withCachePartitionPublishLock, withCachePartitionRecoveryIndexLock;

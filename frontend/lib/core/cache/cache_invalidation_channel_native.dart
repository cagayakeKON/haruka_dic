/// A native process already has a single database owner for each partition.
final class CacheInvalidationChannel {
  CacheInvalidationChannel(String partition, void Function(String, Set<String>?) onMessage);
  void publish(String type, [Set<String>? tags]) {}
  void close() {}
}

import 'dart:convert';

/// Only public dependency categories cross tabs; never resource IDs or content.
const _broadcastTags = {
  'material:list',
  'collection:list',
  'vocabulary_notebook:list',
  'notification:list',
  'settings:profile',
  'settings:study-profile',
  'settings:preferences',
  // Public category only. The card ID never crosses a tab channel.
  'learning-result:*',
  'material:*',
};

String? _publicTag(String tag) {
  if (_broadcastTags.contains(tag)) return tag;
  if (tag.startsWith('learning-result:')) return 'learning-result:*';
  if (tag.startsWith('material:')) return 'material:*';
  return null;
}

String encodeCacheHint(String type, Set<String>? tags) {
  final publicTags = tags?.map(_publicTag).toList();
  return jsonEncode({
    'type': type,
    if (publicTags != null && publicTags.every((tag) => tag != null))
      'tags': publicTags.whereType<String>().toSet().toList(),
  });
}

(String, Set<String>?)? decodeCacheHint(String message) {
  const types = {'invalidate', 'clear', 'identity'};
  if (types.contains(message)) return (message, null); // Older running tabs.
  if (message.length > 2048) return null;
  try {
    final decoded = jsonDecode(message);
    if (decoded is! Map || !types.contains(decoded['type'])) return null;
    final tags = decoded['tags'];
    if (tags != null &&
        (tags is! List ||
            tags.length > _broadcastTags.length ||
            !tags.every(_broadcastTags.contains))) {
      return null;
    }
    return (decoded['type'] as String, (tags as List?)?.cast<String>().toSet());
  } on FormatException {
    return null;
  }
}

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

import '../../core/api/learning_models.dart';

/// Converts a real selection within a published chapter block to the scalar
/// offsets used by the source locator protocol. The server still verifies the
/// text, source version, ownership and persisted card binding.
final class ReferenceSelection {
  const ReferenceSelection({required this.block, required this.locator});

  final NovelBlock block;
  final NovelContentLocator locator;

  static ReferenceSelection? fromTextSelection(NovelBlock block, TextSelection selection) {
    final text = block.text;
    final published = block.locator;
    if (!selection.isValid ||
        selection.isCollapsed ||
        selection.start < 0 ||
        selection.end > text.length ||
        published.quote != text ||
        published.span.end - published.span.start != text.runes.length) {
      return null;
    }

    // TextSelection uses UTF-16 code units. A valid source span must also
    // start and end at grapheme boundaries before conversion to scalar units.
    final boundaries = <int>{0};
    var offset = 0;
    for (final character in text.characters) {
      offset += character.length;
      boundaries.add(offset);
    }
    if (!boundaries.contains(selection.start) || !boundaries.contains(selection.end)) return null;

    final before = text.substring(0, selection.start);
    final quote = text.substring(selection.start, selection.end);
    if (quote.trim().isEmpty) return null;
    final scalarStart = published.span.start + before.runes.length;
    final scalarEnd = scalarStart + quote.runes.length;
    final beforeRunes = before.runes.toList();
    final afterRunes = text.substring(selection.end).runes.toList();
    final prefix = String.fromCharCodes(
      beforeRunes.skip(beforeRunes.length > 100 ? beforeRunes.length - 100 : 0),
    );
    final suffix = String.fromCharCodes(afterRunes.take(100));
    return ReferenceSelection(
      block: block,
      locator: NovelContentLocator(
        instanceId: published.instanceId,
        libraryId: published.libraryId,
        materialId: published.materialId,
        materialRevisionId: published.materialRevisionId,
        novelChapterId: published.novelChapterId,
        chapterBlockId: published.chapterBlockId,
        quote: quote,
        prefix: prefix,
        suffix: suffix,
        sourceTitle: published.sourceTitle,
        nodeTitle: published.nodeTitle,
        span: SourceSpan(blockId: published.span.blockId, start: scalarStart, end: scalarEnd),
      ),
    );
  }
}

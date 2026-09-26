import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/learning_models.dart';
import 'package:haruka/features/collections/reference_selection.dart';

NovelBlock _block(String text, {int start = 0}) {
  final end = start + text.runes.length;
  return NovelBlock(
    id: '018f1234-0000-7000-8000-000000000008',
    chapterBlockId: '018f1234-0000-7000-8000-000000000007',
    text: text,
    ordinal: 0,
    locator: NovelContentLocator(
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      libraryId: '018f1234-0000-7000-8000-000000000003',
      materialId: '018f1234-0000-7000-8000-000000000004',
      materialRevisionId: '018f1234-0000-7000-8000-000000000005',
      novelChapterId: '018f1234-0000-7000-8000-000000000006',
      chapterBlockId: '018f1234-0000-7000-8000-000000000007',
      quote: text,
      prefix: '',
      suffix: '',
      sourceTitle: '合成短篇',
      nodeTitle: '第一章',
      span: SourceSpan(blockId: '018f1234-0000-7000-8000-000000000008', start: start, end: end),
    ),
  );
}

void main() {
  test('actual long-pressed word keeps source identity and uses its own range', () {
    final block = _block('青い空を見上げた。');
    final selected = ReferenceSelection.fromTextSelection(
      block,
      const TextSelection(baseOffset: 2, extentOffset: 3),
    )!;
    expect(selected.locator.quote, '空');
    expect(selected.locator.prefix, '青い');
    expect(selected.locator.suffix, 'を見上げた。');
    expect(selected.locator.span.start, 2);
    expect(selected.locator.span.end, 3);
    expect(selected.locator.materialRevisionId, block.locator.materialRevisionId);
    expect(selected.locator.chapterBlockId, block.locator.chapterBlockId);
  });

  test('UTF-16 selection converts to scalar offsets from nonzero source base', () {
    final block = _block('😀e\u0301空', start: 17);
    final selected = ReferenceSelection.fromTextSelection(
      block,
      const TextSelection(baseOffset: 4, extentOffset: 5),
    )!;
    expect(selected.locator.quote, '空');
    expect(selected.locator.span.start, 20);
    expect(selected.locator.span.end, 21);
    expect(selected.locator.prefix, '😀e\u0301');
    expect(
      ReferenceSelection.fromTextSelection(
        block,
        const TextSelection(baseOffset: 2, extentOffset: 3),
      ),
      isNull,
    );
  });

  test('collapsed and out-of-range selections do not create locators', () {
    final block = _block('青い空');
    expect(
      ReferenceSelection.fromTextSelection(
        block,
        const TextSelection(baseOffset: 2, extentOffset: 2),
      ),
      isNull,
    );
    expect(
      ReferenceSelection.fromTextSelection(
        block,
        const TextSelection(baseOffset: 2, extentOffset: 9),
      ),
      isNull,
    );
  });
}

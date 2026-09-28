import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/collections/domain/vocabulary_csv.dart';

Uint8List encoded(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('CSV v2 exports only words with named notebooks and a stable header', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final bytes = exportVocabularyCsv(store.collections, store.notebooks);
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    final records = Csv().decode(utf8.decode(bytes));
    expect(records, hasLength(5));
    expect(records.first, vocabularyCsvHeader);
    final word = records[1];
    expect(word[vocabularyCsvHeader.indexOf('word')], 'glimmer');
    expect(word[vocabularyCsvHeader.indexOf('wordbooks')], '["English sparks"]');
    expect(
      records.skip(1).map((row) => row[vocabularyCsvHeader.indexOf('word')]),
      isNot(contains('に / へ')),
    );
  });

  test('v2 round-trip keeps unicode, multiline notes and formula-like text', () {
    final original = CollectionEntry(
      id: 'local-1',
      kind: CollectionKind.word,
      displayText: '=SUM(1,2)',
      targetLanguage: 'en',
      meaning: 'quoted "value", emoji 🌱',
      notes: 'first line\nsecond line',
      tags: const ['a,b', '日本語'],
      notebookIds: const {'book-1'},
      createdAt: DateTime.utc(2026, 9, 27),
    );
    final bytes = exportVocabularyCsv(
      [original],
      [
        const NotebookRecord(
          id: 'book-1',
          name: 'My words',
          targetLanguage: 'en',
          description: '',
          revision: 1,
        ),
      ],
    );
    final csvText = utf8.decode(bytes);
    expect(csvText, contains("'=SUM(1,2)"));
    final preview = previewVocabularyCsv(
      bytes: bytes,
      filename: 'words.csv',
      existing: const [],
      defaultLanguage: 'ja',
    );
    expect(preview.errorCount, 0);
    expect(preview.rows.single.word, '=SUM(1,2)');
    expect(preview.rows.single.meaning, original.meaning);
    expect(preview.rows.single.notes, original.notes);
    expect(preview.rows.single.tags, original.tags);
    expect(preview.rows.single.notebookNames, ['My words']);
  });

  test('preview counts existing duplicates and errors without mutating store', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final before = store.collections.length;
    final preview = previewVocabularyCsv(
      bytes: encoded(
        'word,language,meaning,notes,context,source_title\n'
        'そっと,ja,轻轻地,,夏の風がそっと頬に触れた。,夏の手紙 · 第 03 章\n'
        '新しい,ja,新的,"跨行\n笔记",,\n'
        ',ja,缺少词形,,,\n',
      ),
      filename: 'chosen.csv',
      existing: store.collections,
      defaultLanguage: 'ja',
    );
    expect(preview.rows.length, 3);
    expect(preview.newCount, 1);
    expect(preview.duplicateCount, 1);
    expect(preview.errorCount, 1);
    expect(store.collections.length, before);
    expect(() => store.importVocabularyCsv(preview), throwsStateError);
    expect(store.collections.length, before);

    final result = store.importVocabularyCsv(preview, excludeErrors: true);
    expect((result.added, result.skipped, result.excluded), (1, 1, 1));
    expect(store.collections.length, before + 1);
    expect(store.collections.first.displayText, '新しい');
    expect(store.collections.first.notes, '跨行\n笔记');
    expect(store.collections.first.createdAt.isAfter(DateTime.utc(2026, 9, 26)), isTrue);
    final replay = store.importVocabularyCsv(preview, excludeErrors: true);
    expect(replay.added, 0);
    expect(replay.skipped, 2);
  });

  test('v1 paused maps to exercise exclusion without mastery evidence', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final preview = previewVocabularyCsv(
      bytes: encoded('schema_version,word,language,status\n1,新語,ja,paused'),
      filename: 'old.csv',
      existing: store.collections,
      defaultLanguage: 'en',
    );
    expect(preview.rows.single.exerciseControl, 'excluded');
    expect(preview.rows.single.status, isNull);
    store.importVocabularyCsv(preview);
    final imported = store.collections.first;
    expect(imported.exerciseControl, 'excluded');
    expect(imported.importedStatus, isNull);
  });

  test('unsupported version and malformed UTF-8 are rejected before writes', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    expect(
      () => previewVocabularyCsv(
        bytes: Uint8List.fromList([0xff]),
        filename: 'bad.csv',
        existing: store.collections,
        defaultLanguage: 'ja',
      ),
      throwsA(
        isA<CsvReadException>().having((error) => error.problem, 'problem', CsvProblem.invalidUtf8),
      ),
    );
    final preview = previewVocabularyCsv(
      bytes: encoded('schema_version,word,language\n3,unknown,ja'),
      filename: 'future.csv',
      existing: store.collections,
      defaultLanguage: 'ja',
    );
    expect(preview.errorCount, 1);
    expect(preview.rows.single.issues, contains(CsvProblem.invalidVersion));
  });

  test('foreign item ID never updates an unrelated local word', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final original = store.collections.first;
    final preview = previewVocabularyCsv(
      bytes: encoded(
        'schema_version,item_id,word,language,meaning\n'
        '2,${original.id},別の語,ja,新词',
      ),
      filename: 'foreign.csv',
      existing: store.collections,
      defaultLanguage: 'ja',
    );
    expect(preview.duplicateCount, 0);
    store.importVocabularyCsv(preview, duplicateAction: CsvDuplicateAction.merge);
    expect(store.collections.first.id, isNot(original.id));
    expect(store.collections.first.displayText, '別の語');
    expect(
      store.collections.where((item) => item.id == original.id).single.meaning,
      original.meaning,
    );
  });

  test('source locator stays unbound and source date does not replace joined date', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final preview = previewVocabularyCsv(
      bytes: encoded(
        'schema_version,word,language,source_locator,created_at\n'
        '2,新語,ja,"{""material_id"":""other-user""}",2020-01-01T00:00:00Z',
      ),
      filename: 'source.csv',
      existing: store.collections,
      defaultLanguage: 'ja',
    );
    expect(preview.rows.single.valid, isTrue);
    expect(preview.rows.single.unboundSource, isTrue);
    store.importVocabularyCsv(preview);
    expect(store.collections.first.sourceCreatedAt, DateTime.utc(2020));
    expect(store.collections.first.createdAt.year, isNot(2020));
  });

  test('merge fills blanks and keeps the current exercise control', () {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final initial = store.collections.first;
    store.collections[0] = CollectionEntry(
      id: initial.id,
      kind: initial.kind,
      displayText: initial.displayText,
      targetLanguage: initial.targetLanguage,
      meaning: '',
      context: initial.context,
      sourceTitle: initial.sourceTitle,
      createdAt: initial.createdAt,
      exerciseControl: 'excluded',
    );
    final preview = previewVocabularyCsv(
      bytes: encoded(
        'word,language,meaning,context,source_title,wordbooks\n'
        'そっと,ja,补全释义,夏の風がそっと頬に触れた。,夏の手紙 · 第 03 章,"[""新词本""]"',
      ),
      filename: 'merge.csv',
      existing: store.collections,
      defaultLanguage: 'ja',
    );
    final result = store.importVocabularyCsv(preview, duplicateAction: CsvDuplicateAction.merge);
    expect(result.merged, 1);
    expect(store.collections.length, 6);
    final merged = store.collections.first;
    expect(merged.id, initial.id);
    expect(merged.meaning, '补全释义');
    expect(merged.exerciseControl, 'excluded');
    expect(merged.notebookIds, hasLength(1));
    expect(store.notebooks.last.name, '新词本');
    final replay = store.importVocabularyCsv(preview, duplicateAction: CsvDuplicateAction.merge);
    expect(replay.merged, 0);
    expect(replay.skipped, 1);
    expect(store.collections.first.revision, merged.revision);
  });
}

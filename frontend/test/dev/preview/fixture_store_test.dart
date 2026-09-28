import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/agent/domain/query_request.dart';

void main() {
  late PreviewFixtureStore store;

  setUp(() => store = PreviewFixtureStore());
  tearDown(() => store.dispose());

  test('seed records use the planned material and collection DTO fields', () {
    expect(store.materials.map((item) => item.type).toSet(), LearningMaterialType.values.toSet());
    expect(store.materials.map((item) => item.id).toSet().length, store.materials.length);
    expect(store.collections.map((item) => item.id).toSet().length, store.collections.length);
    final material = store.materials.first.toJson();
    expect(material, containsPair('material_type', 'novel'));
    expect(material, containsPair('source_status', 'readable'));
    expect(material, containsPair('revision', 1));
    expect(material['updated_at'], isA<String>());
    expect(material, isNot(contains('user_id')));

    final collection = store.collections.first.toJson();
    expect(collection, containsPair('kind', 'word'));
    expect(collection, containsPair('target_language', 'ja'));
    expect(collection['source_snapshot'], containsPair('title', '夏の手紙 · 第 03 章'));
    expect(
      collection['source_snapshot'],
      containsPair('material_id', '11111111-1111-4111-8111-111111111111'),
    );
    expect(collection['notebook_ids'], contains(store.notebooks.first.id));
    expect(store.notifications.first.toJson()['read_at'], isNull);
    expect(store.cards.first.toJson(), containsPair('revision', 1));
  });

  test('material filter combines type and trimmed case insensitive title search', () {
    expect(store.filterMaterials(null, ''), hasLength(4));
    expect(store.filterMaterials(LearningMaterialType.novel, ''), hasLength(2));
    expect(store.filterMaterials(LearningMaterialType.novel, ' 夏の '), hasLength(1));
    expect(store.filterMaterials(LearningMaterialType.exam, ' 夏の '), isEmpty);
    expect(store.filterMaterials(null, 'JA'), hasLength(4));
  });

  test('collection filter searches spelling, reading and meaning within notebook', () {
    expect(store.filterCollections(CollectionKind.word, ''), hasLength(4));
    expect(store.filterCollections(null, 'SOTTO').single.displayText, 'そっと');
    expect(store.filterCollections(null, '平静').single.displayText, '穏やか');
    expect(store.filterCollections(null, '', notebookId: store.notebooks.first.id), hasLength(2));
    expect(
      store.filterCollections(CollectionKind.grammar, '', notebookId: store.notebooks.first.id),
      isEmpty,
    );
  });

  test('import validates title, creates a processing record, then delete removes only it', () {
    expect(
      () => store.importMaterial(LearningMaterialType.novel, '   ', 'ja'),
      throwsArgumentError,
    );
    store.importMaterial(LearningMaterialType.textbook, '  新教材  ', 'en');
    final created = store.materials.first;
    expect(created.title, '新教材');
    expect(created.type, LearningMaterialType.textbook);
    expect(created.language, 'en');
    expect(created.status, 'processing');
    expect(created.toJson()['material_type'], 'textbook');
    store.deleteMaterial(created.id);
    expect(store.materials, hasLength(4));
  });

  test('notebook rename advances revision; deletion keeps collection and removes membership', () {
    expect(() => store.addNotebook(' ', 'ja', ''), throwsArgumentError);
    expect(() => store.addNotebook('日常的细节', 'ja', ''), throwsArgumentError);
    final created = store.addNotebook(' 新词本 ', 'en', ' 课程 ');
    expect(created.name, '新词本');
    expect(created.description, '课程');
    expect(created.toJson()['target_language'], 'en');
    store.updateNotebook(created.id, name: '改名');
    expect(store.notebooks.last.name, '改名');
    expect(store.notebooks.last.revision, 2);

    final original = store.collections.first;
    store.deleteNotebook(store.notebooks.first.id);
    expect(store.collections, hasLength(6));
    expect(store.collections.first.id, original.id);
    expect(store.collections.first.notebookIds, isEmpty);
    expect(store.collections.first.revision, original.revision + 1);
  });

  test('notebook create and rename use normalized unique names within a language', () {
    expect(() => store.addNotebook('  english SPARKS  ', 'en', ''), throwsArgumentError);
    final created = store.addNotebook('Words', 'en', '');
    final revision = store.notebooks.last.revision;
    expect(() => store.updateNotebook(created.id, name: '   '), throwsArgumentError);
    expect(() => store.updateNotebook(created.id, name: ' ENGLISH sparks '), throwsArgumentError);
    expect(store.notebooks.last.name, 'Words');
    expect(store.notebooks.last.revision, revision);
    store.updateNotebook(created.id, name: ' words ');
    expect(store.notebooks.last.name, 'words');
  });

  test('manual collection IDs remain unique and duplicate inserts are rejected', () {
    final ids = <String>{};
    for (var index = 0; index < 40; index++) {
      final id = store.nextCollectionId();
      expect(ids.add(id), isTrue);
      final source = store.collections.first;
      final json = {...source.toJson(), 'id': id, 'display_text': '词$index'};
      store.addCollection(CollectionEntry.fromJson(json));
      expect(() => store.addCollection(CollectionEntry.fromJson(json)), throwsArgumentError);
    }
    expect(store.collections.map((item) => item.id).toSet(), hasLength(store.collections.length));
  });

  test('one collection can belong to two books and deleting one preserves the other', () {
    final word = store.collections.first;
    final firstBook = store.notebooks[0];
    final secondBook = store.notebooks[1];
    final englishBook = store.notebooks[2];
    expect(word.notebookIds, {firstBook.id});

    store.setCollectionNotebooks(word.id, {firstBook.id, secondBook.id});
    final inTwoBooks = store.collections.first;
    expect(inTwoBooks.notebookIds, {firstBook.id, secondBook.id});
    expect(inTwoBooks.id, word.id);
    expect(inTwoBooks.createdAt, word.createdAt);
    expect(inTwoBooks.meaning, word.meaning);
    expect(inTwoBooks.revision, word.revision + 1);
    expect(store.filterCollections(null, '', notebookId: firstBook.id), contains(inTwoBooks));
    expect(store.filterCollections(null, '', notebookId: secondBook.id), contains(inTwoBooks));

    store.setCollectionNotebooks(word.id, {firstBook.id, secondBook.id});
    expect(store.collections.first.revision, inTwoBooks.revision);
    expect(
      () => store.setCollectionNotebooks(word.id, {firstBook.id, englishBook.id}),
      throwsArgumentError,
    );
    expect(
      () => store.setCollectionNotebooks(word.id, {firstBook.id, 'missing-notebook'}),
      throwsArgumentError,
    );
    expect(store.collections.first.notebookIds, {firstBook.id, secondBook.id});

    store.deleteNotebook(firstBook.id);
    final afterDelete = store.collections.first;
    expect(afterDelete.id, word.id);
    expect(afterDelete.notebookIds, {secondBook.id});
    expect(afterDelete.createdAt, word.createdAt);
    expect(afterDelete.meaning, word.meaning);
    expect(store.filterCollections(null, '', notebookId: secondBook.id), contains(afterDelete));
    expect(store.filterCollections(null, '', notebookId: firstBook.id), isEmpty);
    expect(store.collections, hasLength(6));
  });

  test('Chinese manual notebook accepts Chinese collection and rejects cross-language members', () {
    final chinese = store.addNotebook('中文随手记', 'zh', '手动整理');
    final template = store.collections.first;
    final chineseEntry = CollectionEntry(
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      kind: CollectionKind.word,
      displayText: '清晨',
      targetLanguage: 'zh',
      meaning: '天刚亮的时候',
      notebookIds: {chinese.id},
      createdAt: DateTime.utc(2026, 9, 27),
    );
    store.addCollection(chineseEntry);
    expect(store.collections.first.targetLanguage, 'zh');
    expect(store.filterCollections(null, '', notebookId: chinese.id).single.id, chineseEntry.id);
    expect(
      () => store.setCollectionNotebooks(chineseEntry.id, {chinese.id, store.notebooks.first.id}),
      throwsArgumentError,
    );
    expect(store.collections.first.notebookIds, {chinese.id});
    expect(
      () => store.addCollection(
        CollectionEntry.fromJson({
          ...template.toJson(),
          'id': store.nextCollectionId(),
          'notebook_ids': [chinese.id],
        }),
      ),
      throwsArgumentError,
    );
    expect(store.filterCollections(null, '', notebookId: chinese.id), hasLength(1));
  });

  test('notes and notebook assignment update one collection revision', () {
    final original = store.collections.first;
    store.saveCollectionNotes(original.id, '  复习时留意语气  ');
    expect(store.collections.first.notes, '  复习时留意语气  ');
    expect(store.collections.first.revision, 2);
    final nextNotebook = store.notebooks[1].id;
    store.setCollectionNotebooks(original.id, {nextNotebook});
    expect(store.collections.first.notebookIds, {nextNotebook});
    expect(store.collections.first.revision, 3);
    expect(store.collections.skip(1).map((item) => item.revision), everyElement(1));
  });

  test('query chooses typed cards, records one result and collection save is idempotent', () {
    expect(() => store.runQuery('   '), throwsArgumentError);
    expect(store.runQuery('に 和 へ 的区别').kind, CollectionKind.grammar);
    expect(store.runQuery('翻译：夏の風').kind, CollectionKind.sentence);
    expect(store.runQuery('批改：昨日、図書館に行きます。').kind, CollectionKind.exercise);
    expect(store.lastQuery, '批改：昨日、図書館に行きます。');
    expect(store.localExplanationCount, 3);
    expect(store.savedExplanationCount, 3);

    final card = store.lastCard!;
    final initialCount = store.collections.length;
    store.saveCard(card);
    expect(store.collections, hasLength(initialCount + 1));
    expect(store.collections.first.kind, CollectionKind.exercise);
    store.saveCard(card);
    expect(store.collections, hasLength(initialCount + 1));
  });

  test('selected exam word resolves to its own query card', () {
    final card = store.runQuery('穏やか');
    expect(card.kind, CollectionKind.word);
    expect(card.title, '穏やか');
    expect(card.explanation, contains('平静'));
    expect(card.examples, contains('穏やかな一日を過ごした。'));
    expect(store.runQuery('そっと 是什么意思？').title, 'そっと');
    expect(store.history.map((entry) => entry.prompt), ['穏やか', 'そっと 是什么意思？']);
    expect(store.history.first.card.title, '穏やか');
    expect(PreviewFixtureStore().history, isEmpty);
  });

  test('query context changes result identity and exact context reuses saved result', () async {
    const first = QueryRequest(text: 'そっと', context: '小说句子');
    const second = QueryRequest(text: 'そっと', context: '教材例句');
    final firstCard = await store.submit(first);
    final secondCard = await store.submit(second);
    final reused = await store.submit(first);
    expect(firstCard.id, isNot(secondCard.id));
    expect(reused.id, firstCard.id);
    expect(store.savedExplanationCount, 2);
    expect(store.history, hasLength(3));
  });

  test('query languages are part of saved result identity', () async {
    const japaneseChinese = QueryRequest(
      text: 'そっと',
      targetLanguage: 'ja',
      explanationLanguage: 'zh',
    );
    const japaneseEnglish = QueryRequest(
      text: 'そっと',
      targetLanguage: 'ja',
      explanationLanguage: 'en',
    );
    const englishChinese = QueryRequest(
      text: 'そっと',
      targetLanguage: 'en',
      explanationLanguage: 'zh',
    );
    final first = await store.submit(japaneseChinese);
    final second = await store.submit(japaneseEnglish);
    final third = await store.submit(englishChinese);
    expect({first.id, second.id, third.id}, hasLength(3));
    expect((await store.submit(japaneseChinese)).id, first.id);
    expect(store.savedExplanationCount, 3);
  });

  test('exam preparation snapshot survives page state rebuild and stays scoped to its exam', () {
    final examId = store.materials.firstWhere((item) => item.type == LearningMaterialType.exam).id;
    final otherId = store.materials
        .firstWhere((item) => item.type == LearningMaterialType.novel)
        .id;
    final questions = [
      const ExamPrepQuestion(number: 7, group: ExamPrepQuestionGroup.language, score: 2),
      const ExamPrepQuestion(number: 9, group: ExamPrepQuestionGroup.listening, score: 3),
    ];
    expect(store.examPrepFor(examId), isNull);
    store.saveExamPrep(
      examId,
      ExamPrepSnapshot(
        questions: questions,
        questionsReviewed: true,
        scriptConfirmed: true,
        scriptRejected: false,
        linkedItem: 9,
        audioReady: true,
      ),
    );
    questions.clear();
    final restored = store.examPrepFor(examId)!;
    expect(restored.questions.map((question) => question.number), [7, 9]);
    expect(restored.questions.last.group, ExamPrepQuestionGroup.listening);
    expect(restored.questions.last.score, 3);
    expect(restored.questionsReviewed, isTrue);
    expect(restored.scriptConfirmed, isTrue);
    expect(restored.scriptRejected, isFalse);
    expect(restored.linkedItem, 9);
    expect(restored.audioReady, isTrue);
    expect(() => restored.questions.clear(), throwsUnsupportedError);
    expect(store.examPrepFor(otherId), isNull);
    expect(() => store.saveExamPrep(otherId, restored), throwsArgumentError);
    store.deleteMaterial(examId);
    expect(store.examPrepFor(examId), isNull);
  });

  test('exercise requires selection, freezes submitted answer, and can reset', () {
    store.submitExercise();
    expect(store.exerciseSubmitted, isFalse);
    store.chooseAnswer(1);
    store.submitExercise();
    expect(store.exerciseSubmitted, isTrue);
    store.chooseAnswer(0);
    expect(store.selectedAnswer, 1);
    store.resetExercise();
    expect(store.exerciseSubmitted, isFalse);
    expect(store.selectedAnswer, isNull);
  });

  test('notifications read once and cache clear preserves saved counts and limits', () {
    expect(store.unreadCount, 2);
    final first = store.notifications.first.id;
    store.readNotification(first);
    final readAt = store.notifications.first.readAt;
    expect(store.unreadCount, 1);
    store.readNotification(first);
    expect(store.notifications.first.readAt, readAt);
    store.readAllNotifications();
    expect(store.unreadCount, 0);

    store.runQuery('そっと');
    store.saveCacheLimits(200, 800);
    store.clearLocalCache();
    expect(store.localExplanationCount, 0);
    expect(store.savedExplanationCount, 1);
    expect(store.textLimitMb, 200);
    expect(store.audioLimitMb, 800);
  });
}

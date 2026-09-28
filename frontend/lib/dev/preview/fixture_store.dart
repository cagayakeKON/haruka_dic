import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import 'package:haruka/shared/domain/learning_records.dart';
import 'package:haruka/features/collections/domain/vocabulary_csv.dart';
import 'package:haruka/features/agent/data/query_result_repository.dart';
import 'package:haruka/features/agent/domain/query_history_entry.dart';
import 'package:haruka/features/agent/domain/query_request.dart';

final class CsvImportResult {
  const CsvImportResult({
    required this.added,
    required this.merged,
    required this.skipped,
    required this.excluded,
  });

  final int added;
  final int merged;
  final int skipped;
  final int excluded;
}

enum ExamPrepQuestionGroup { language, reading, listening }

final class ExamPrepQuestion {
  const ExamPrepQuestion({required this.number, required this.group, required this.score});

  final int number;
  final ExamPrepQuestionGroup group;
  final double score;
}

final class ExamPrepSnapshot {
  ExamPrepSnapshot({
    required List<ExamPrepQuestion> questions,
    required this.questionsReviewed,
    required this.scriptConfirmed,
    required this.scriptRejected,
    required this.linkedItem,
    required this.audioReady,
  }) : questions = List.unmodifiable(questions);

  final List<ExamPrepQuestion> questions;
  final bool questionsReviewed;
  final bool scriptConfirmed;
  final bool scriptRejected;
  final int linkedItem;
  final bool audioReady;
}

/// An in-process implementation of the planned list/detail/mutation boundary.
/// Widgets consume typed projections; replacing this store does not change
/// their state or presentation contracts.
final class PreviewFixtureStore extends ChangeNotifier implements QueryResultRepository {
  PreviewFixtureStore();

  final Set<String> _unreadableMaterialIds = <String>{};

  bool canReadMaterial(String id) => !_unreadableMaterialIds.contains(id);

  void revokeMaterialRead(String id) {
    if (_unreadableMaterialIds.add(id)) notifyListeners();
  }

  final materials = <MaterialSummary>[
    MaterialSummary(
      id: '11111111-1111-4111-8111-111111111111',
      type: LearningMaterialType.novel,
      title: '夏の手紙',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27, 9, 42),
      description: '一封从夏日海边寄来的信，慢慢连接起两个人的故事。',
      cover: '夏',
      sectionCount: 12,
    ),
    MaterialSummary(
      id: '22222222-2222-4222-8222-222222222222',
      type: LearningMaterialType.textbook,
      title: '日语的日常表达',
      language: 'ja',
      status: 'readable',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 26, 18, 10),
      description: '用熟悉的生活场景学习表达、语法和课后练习。',
      cover: 'あ',
      sectionCount: 8,
    ),
    MaterialSummary(
      id: '33333333-3333-4333-8333-333333333333',
      type: LearningMaterialType.exam,
      title: 'N2 模拟试卷',
      language: 'ja',
      status: 'needs_review',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 21),
      description: '结构已提取，听力文字稿与题目关联等待校对。',
      cover: 'N2',
      sectionCount: 38,
    ),
    MaterialSummary(
      id: '44444444-4444-4444-8444-444444444444',
      type: LearningMaterialType.novel,
      title: '雨上がり',
      language: 'ja',
      status: 'processing',
      revision: 1,
      updatedAt: DateTime.utc(2026, 9, 27, 8),
      description: '解析中 · 35%',
      cover: '雨',
      activeJobProgressPercent: 35,
    ),
  ];

  final notebooks = <NotebookRecord>[
    const NotebookRecord(
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      name: '日常的细节',
      targetLanguage: 'ja',
      description: '从小说和日常会话里收集的表达。',
      revision: 1,
    ),
    const NotebookRecord(
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      name: '阅读时遇见',
      targetLanguage: 'ja',
      description: '读故事时想记住的词与短语。',
      revision: 1,
    ),
    const NotebookRecord(
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      name: 'English sparks',
      targetLanguage: 'en',
      description: '英语材料里的高频表达。',
      revision: 1,
    ),
  ];

  final collections = <CollectionEntry>[
    CollectionEntry(
      id: 'd1111111-1111-4111-8111-111111111111',
      kind: CollectionKind.word,
      displayText: 'そっと',
      targetLanguage: 'ja',
      reading: 'sotto',
      meaning: '轻轻地；悄悄地',
      context: '夏の風がそっと頬に触れた。',
      sourceTitle: '夏の手紙 · 第 03 章',
      sourceMaterialId: '11111111-1111-4111-8111-111111111111',
      notebookIds: {'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
      createdAt: DateTime.utc(2026, 9, 27, 9),
    ),
    CollectionEntry(
      id: 'd2222222-2222-4222-8222-222222222222',
      kind: CollectionKind.word,
      displayText: '微笑む',
      targetLanguage: 'ja',
      reading: 'ほほえむ',
      meaning: '微笑',
      context: '私は思わず微笑んだ。',
      sourceTitle: '夏の手紙 · 第 03 章',
      sourceMaterialId: '11111111-1111-4111-8111-111111111111',
      notebookIds: {'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
      createdAt: DateTime.utc(2026, 9, 26, 18),
    ),
    CollectionEntry(
      id: 'd3333333-3333-4333-8333-333333333333',
      kind: CollectionKind.word,
      displayText: '穏やか',
      targetLanguage: 'ja',
      reading: 'おだやか',
      meaning: '平静的；温和的',
      context: '穏やかな一日を過ごした。',
      sourceTitle: 'N2 模拟试卷 · 语言知识',
      sourceMaterialId: '33333333-3333-4333-8333-333333333333',
      notebookIds: {'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
      createdAt: DateTime.utc(2026, 9, 25, 12),
    ),
    CollectionEntry(
      id: 'd4444444-4444-4444-8444-444444444444',
      kind: CollectionKind.word,
      displayText: 'glimmer',
      targetLanguage: 'en',
      reading: '/ˈɡlɪmər/',
      meaning: '微光；一丝希望',
      context: 'A glimmer of light appeared beyond the hill.',
      sourceTitle: 'English sparks · 阅读片段',
      notebookIds: {'cccccccc-cccc-4ccc-8ccc-cccccccccccc'},
      createdAt: DateTime.utc(2026, 9, 24, 9),
    ),
    CollectionEntry(
      id: 'd5555555-5555-4555-8555-555555555555',
      kind: CollectionKind.grammar,
      displayText: 'に / へ',
      targetLanguage: 'ja',
      meaning: '目的地与移动方向',
      sourceTitle: '日语的日常表达 · Unit 02',
      sourceMaterialId: '22222222-2222-4222-8222-222222222222',
      createdAt: DateTime.utc(2026, 9, 23, 9),
    ),
    CollectionEntry(
      id: 'd6666666-6666-4666-8666-666666666666',
      kind: CollectionKind.sentence,
      displayText: '夏の風がそっと頬に触れた。',
      targetLanguage: 'ja',
      meaning: '夏风轻轻拂过脸颊。',
      sourceTitle: '夏の手紙 · 第 03 章',
      sourceMaterialId: '11111111-1111-4111-8111-111111111111',
      createdAt: DateTime.utc(2026, 9, 22, 9),
    ),
  ];

  final notifications = <NotificationRecord>[
    NotificationRecord(
      id: 'e1111111-1111-4111-8111-111111111111',
      title: '「夏の手紙」已可阅读',
      detail: '章节与正文已准备好。',
      route: 'novel',
      resourceId: '11111111-1111-4111-8111-111111111111',
      resourceRevision: 1,
      createdAt: DateTime.utc(2026, 9, 27, 9, 42),
    ),
    NotificationRecord(
      id: 'e2222222-2222-4222-8222-222222222222',
      title: '试卷结构需要校对',
      detail: '听力文字稿与题组匹配仍待确认。',
      route: 'examPrep',
      resourceId: '33333333-3333-4333-8333-333333333333',
      resourceRevision: 1,
      createdAt: DateTime.utc(2026, 9, 26, 16, 18),
    ),
    NotificationRecord(
      id: 'e3333333-3333-4333-8333-333333333333',
      title: '「日语的日常表达」已完成解析',
      detail: '3 个单元可以学习。',
      route: 'textbook',
      resourceId: '22222222-2222-4222-8222-222222222222',
      resourceRevision: 1,
      createdAt: DateTime.utc(2026, 9, 20),
      readAt: DateTime.utc(2026, 9, 21),
    ),
  ];

  final cards = <LearningCard>[
    const LearningCard(
      id: 'f1111111-1111-4111-8111-111111111111',
      kind: CollectionKind.word,
      title: 'そっと',
      explanation: '轻轻地、悄悄地。强调动作温柔，不打扰周围。',
      examples: ['夏の風がそっと頬に触れた。', 'ドアをそっと閉めた。'],
      version: 1,
      wordDetail: WordCardDetail(
        romanization: 'sotto',
        partOfSpeech: '副词',
        meaning: '轻轻地；悄悄地',
        usage: '用于动作轻柔，或不希望打扰别人的场景。',
        examples: [
          WordExample(text: 'ドアをそっと閉めた。', translation: '轻轻地关上了门。'),
          WordExample(text: 'そっと手を握った。', translation: '轻轻握住了手。'),
        ],
      ),
    ),
    const LearningCard(
      id: 'f2222222-2222-4222-8222-222222222222',
      kind: CollectionKind.sentence,
      title: '夏の風がそっと頬に触れた。',
      explanation: '夏风轻轻拂过脸颊。',
      examples: ['夏の風 / が / そっと / 頬に / 触れた'],
      version: 1,
    ),
    const LearningCard(
      id: 'f3333333-3333-4333-8333-333333333333',
      kind: CollectionKind.grammar,
      title: 'に / へ',
      explanation: 'に更强调到达点；へ更强调移动方向。',
      examples: ['駅に行きます。', '駅へ行きます。'],
      version: 1,
    ),
    const LearningCard(
      id: 'f4444444-4444-4444-8444-444444444444',
      kind: CollectionKind.exercise,
      title: '昨日、図書館に行きます。',
      explanation: '昨日表示过去，应改为「行きました」。',
      examples: ['昨日、図書館に行きました。'],
      version: 1,
    ),
    const LearningCard(
      id: 'f5555555-5555-4555-8555-555555555555',
      kind: CollectionKind.word,
      title: '穏やか',
      explanation: '平静、温和。常用于形容气氛、心情或天气。',
      examples: ['穏やかな一日を過ごした。', '穏やかな声で話した。'],
      version: 1,
    ),
  ];

  String displayName = '小遥';
  String avatarGlyph = '遥';
  int? birthYear;
  String gender = 'unset';
  String timezone = 'Asia/Tokyo';
  bool allowProfileForAi = false;
  String activeLanguage = 'ja';
  String explanationLanguage = 'zh-Hans';
  Set<String> nativeLanguages = {'zh-Hans'};
  Set<String> learningLanguages = {'ja', 'en'};
  String learningLevel = 'intermediate';
  Set<String> learningGoals = {'reading', 'exam'};
  String themeMode = 'system';
  bool reducedMotion = false;
  String readingFont = 'serif';
  int readingFontSize = 18;
  double readingLineHeight = 1.8;
  String readingTheme = 'light';
  int queryContextBudget = 10000;
  String modelProvider = 'openrouter';
  bool hasPersonalApiKey = false;
  String textModel = 'default';
  String visionModel = 'default';
  String ttsModel = 'gemini';
  String speechVoice = 'japaneseClear';
  String speechFormat = 'wav';
  String speechStyle = 'natural';
  double speechSpeed = 1;
  String serviceAddress = '';
  bool serviceAddressValidated = false;
  bool serviceProbeAttempted = false;
  int passwordChangeCount = 0;
  int textLimitMb = 100;
  int audioLimitMb = 500;
  int localExplanationCount = 0;
  int savedExplanationCount = 0;
  int localAudioCount = 0;
  int savedAudioCount = 0;
  LearningCard? lastCard;
  String lastQuery = '';
  final _queryHistory = <QueryHistoryEntry>[];

  @override
  List<QueryHistoryEntry> get history => List.unmodifiable(_queryHistory);
  final _resolvedQueries = <String, LearningCard>{};
  final _savedQueryCards = <String, LearningCard>{};
  final _savedQueryTargetLanguages = <String, String>{};

  String _scopedQueryKey(String scopeBinding, String id) => jsonEncode([scopeBinding, id]);

  LearningCard? savedQueryCard(String id, {String scopeBinding = 'standalone-preview'}) =>
      _savedQueryCards[_scopedQueryKey(scopeBinding, id)];
  String? savedQueryTargetLanguage(String id, {String scopeBinding = 'standalone-preview'}) =>
      _savedQueryTargetLanguages[_scopedQueryKey(scopeBinding, id)];

  String _queryIdentity(QueryRequest request) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            request.text.trim(),
            request.context.trim(),
            request.targetLanguage,
            request.explanationLanguage,
          ]),
        ),
      )
      .toString();
  bool exerciseSubmitted = false;
  int? selectedAnswer;
  Map<int, int> examAnswers = const {};
  bool examSubmitted = false;
  Map<int, int> examDraftAnswers = const {};
  Set<int> examMarkedQuestions = const {};
  int examCurrentQuestion = 0;
  bool examDraftSaved = false;
  final _examPrepByMaterialId = <String, ExamPrepSnapshot>{};
  int _nextId = 1;
  late final SettingsDraft settingsDraft = SettingsDraft.fromStore(this);

  int get unreadCount => notifications.where((item) => item.readAt == null).length;

  List<MaterialSummary> filterMaterials(LearningMaterialType? type, String query) {
    final term = query.trim().toLowerCase();
    return materials.where((item) {
      return (type == null || type == item.type) &&
          (term.isEmpty ||
              item.title.toLowerCase().contains(term) ||
              item.language.toLowerCase().contains(term));
    }).toList();
  }

  List<CollectionEntry> filterCollections(
    CollectionKind? kind,
    String query, {
    String? notebookId,
  }) {
    final term = query.trim().toLowerCase();
    return collections.where((item) {
      return (kind == null || kind == item.kind) &&
          (notebookId == null || item.notebookIds.contains(notebookId)) &&
          (term.isEmpty ||
              item.displayText.toLowerCase().contains(term) ||
              (item.reading ?? '').toLowerCase().contains(term) ||
              item.meaning.toLowerCase().contains(term));
    }).toList();
  }

  void importMaterial(LearningMaterialType type, String title, String language) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError('title');
    materials.insert(
      0,
      MaterialSummary(
        id: '99999999-9999-4999-8999-${(_nextId++).toString().padLeft(12, '0')}',
        type: type,
        title: trimmed,
        language: language,
        status: 'processing',
        revision: 1,
        updatedAt: DateTime.now().toUtc(),
        description: '等待解析',
        cover: String.fromCharCode(trimmed.runes.first),
        activeJobProgressPercent: 0,
      ),
    );
    notifyListeners();
  }

  void deleteMaterial(String id) {
    materials.removeWhere((item) => item.id == id);
    _examPrepByMaterialId.remove(id);
    notifyListeners();
  }

  ExamPrepSnapshot? examPrepFor(String materialId) => _examPrepByMaterialId[materialId];

  void saveExamPrep(String materialId, ExamPrepSnapshot snapshot) {
    if (!materials.any((item) => item.id == materialId && item.type == LearningMaterialType.exam)) {
      throw ArgumentError.value(materialId, 'materialId');
    }
    _examPrepByMaterialId[materialId] = snapshot;
    notifyListeners();
  }

  NotebookRecord addNotebook(String name, String language, String description) {
    final trimmed = name.trim();
    if (!const {'ja', 'en', 'zh'}.contains(language) ||
        trimmed.isEmpty ||
        notebooks.any(
          (item) =>
              item.targetLanguage == language &&
              item.name.trim().toLowerCase() == trimmed.toLowerCase(),
        )) {
      throw ArgumentError('name');
    }
    final notebook = NotebookRecord(
      id: '88888888-8888-4888-8888-${(_nextId++).toString().padLeft(12, '0')}',
      name: trimmed,
      targetLanguage: language,
      description: description.trim(),
      revision: 1,
    );
    notebooks.add(notebook);
    notifyListeners();
    return notebook;
  }

  void updateNotebook(String id, {String? name, String? description}) {
    final index = notebooks.indexWhere((item) => item.id == id);
    if (index < 0) throw ArgumentError.value(id, 'id');
    final nextName = name?.trim();
    if (nextName != null &&
        (nextName.isEmpty ||
            notebooks.any(
              (item) =>
                  item.id != id &&
                  item.targetLanguage == notebooks[index].targetLanguage &&
                  item.name.trim().toLowerCase() == nextName.toLowerCase(),
            ))) {
      throw ArgumentError.value(name, 'name');
    }
    notebooks[index] = notebooks[index].copyWith(name: nextName, description: description);
    notifyListeners();
  }

  void deleteNotebook(String id) {
    notebooks.removeWhere((item) => item.id == id);
    for (var i = 0; i < collections.length; i++) {
      if (collections[i].notebookIds.contains(id)) {
        collections[i] = collections[i].copyWith(
          notebookIds: {...collections[i].notebookIds}..remove(id),
        );
      }
    }
    notifyListeners();
  }

  void saveCollectionNotes(String id, String notes) {
    final index = collections.indexWhere((item) => item.id == id);
    if (index < 0) return;
    collections[index] = collections[index].copyWith(notes: notes);
    notifyListeners();
  }

  void updateCollection(
    String id, {
    required String displayText,
    required String meaning,
    required String notes,
  }) {
    final index = collections.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final nextText = displayText.trim();
    if (nextText.isEmpty) throw ArgumentError.value(displayText, 'displayText');
    collections[index] = collections[index].copyWith(
      displayText: nextText,
      meaning: meaning.trim(),
      notes: notes.trim(),
    );
    notifyListeners();
  }

  void addCollection(CollectionEntry item) {
    if (collections.any((existing) => existing.id == item.id)) {
      throw ArgumentError.value(item.id, 'id');
    }
    if (!const {'ja', 'en', 'zh'}.contains(item.targetLanguage)) {
      throw ArgumentError.value(item.targetLanguage, 'targetLanguage');
    }
    for (final notebookId in item.notebookIds) {
      final notebook = notebooks.where((book) => book.id == notebookId).firstOrNull;
      if (notebook == null || notebook.targetLanguage != item.targetLanguage) {
        throw ArgumentError.value(notebookId, 'notebookIds');
      }
    }
    collections.insert(0, item);
    notifyListeners();
  }

  String nextCollectionId() {
    late String id;
    do {
      id = '77777777-7777-4777-8777-${(_nextId++).toString().padLeft(12, '0')}';
    } while (collections.any((item) => item.id == id));
    return id;
  }

  CsvImportResult importVocabularyCsv(
    VocabularyCsvPreview preview, {
    CsvDuplicateAction duplicateAction = CsvDuplicateAction.skip,
    bool excludeErrors = false,
  }) {
    if (preview.errorCount > 0 && !excludeErrors) {
      throw StateError('CSV errors must be explicitly excluded');
    }
    final nextCollections = List<CollectionEntry>.of(collections);
    final nextNotebooks = List<NotebookRecord>.of(notebooks);
    var nextId = _nextId;
    var added = 0;
    var merged = 0;
    var skipped = 0;
    var excluded = 0;
    final now = DateTime.now().toUtc();

    for (final row in preview.rows) {
      if (!row.valid) {
        excluded++;
        continue;
      }
      final key = vocabularyCsvDuplicateKey(
        word: row.word,
        language: row.language,
        context: row.context,
        sourceTitle: row.sourceTitle,
      );
      final existingIndex = nextCollections.indexWhere(
        (item) =>
            item.kind == CollectionKind.word &&
            vocabularyCsvDuplicateKey(
                  word: item.displayText,
                  language: item.targetLanguage,
                  context: item.context,
                  sourceTitle: item.sourceTitle,
                ) ==
                key,
      );
      if (existingIndex >= 0 && duplicateAction == CsvDuplicateAction.skip) {
        skipped++;
        continue;
      }
      final notebookIds = <String>{};
      for (final name in row.notebookNames) {
        final normalized = name.trim();
        if (normalized.isEmpty) continue;
        var book = nextNotebooks
            .where(
              (candidate) =>
                  candidate.targetLanguage == row.language &&
                  candidate.name.trim().toLowerCase() == normalized.toLowerCase(),
            )
            .firstOrNull;
        if (book == null) {
          book = NotebookRecord(
            id: '88888888-8888-4888-8888-${(nextId++).toString().padLeft(12, '0')}',
            name: normalized,
            targetLanguage: row.language,
            description: '',
            revision: 1,
          );
          nextNotebooks.add(book);
        }
        notebookIds.add(book.id);
      }
      if (existingIndex >= 0 && duplicateAction == CsvDuplicateAction.merge) {
        final old = nextCollections[existingIndex];
        final updated = CollectionEntry(
          id: old.id,
          kind: old.kind,
          displayText: old.displayText,
          targetLanguage: old.targetLanguage,
          meaning: old.meaning.isEmpty ? row.meaning : old.meaning,
          createdAt: old.createdAt,
          reading: (old.reading ?? '').isEmpty ? row.reading : old.reading,
          lemma: (old.lemma ?? '').isEmpty ? row.lemma : old.lemma,
          context: (old.context ?? '').isEmpty ? row.context : old.context,
          sourceTitle: (old.sourceTitle ?? '').isEmpty ? row.sourceTitle : old.sourceTitle,
          notebookIds: {...old.notebookIds, ...notebookIds},
          notes: old.notes.isEmpty ? row.notes : old.notes,
          tags: {...old.tags, ...row.tags}.toList(),
          importedStatus: old.importedStatus ?? row.status,
          exerciseControl: old.exerciseControl,
          sourceCreatedAt: old.sourceCreatedAt ?? row.sourceCreatedAt,
          sourceUpdatedAt: old.sourceUpdatedAt ?? row.sourceUpdatedAt,
          revision: old.revision + 1,
        );
        if (updated.meaning == old.meaning &&
            updated.reading == old.reading &&
            updated.lemma == old.lemma &&
            updated.context == old.context &&
            updated.sourceTitle == old.sourceTitle &&
            setEquals(updated.notebookIds, old.notebookIds) &&
            updated.notes == old.notes &&
            setEquals(updated.tags.toSet(), old.tags.toSet()) &&
            updated.importedStatus == old.importedStatus &&
            updated.sourceCreatedAt == old.sourceCreatedAt &&
            updated.sourceUpdatedAt == old.sourceUpdatedAt) {
          skipped++;
          continue;
        }
        nextCollections[existingIndex] = updated;
        merged++;
        continue;
      }
      nextCollections.insert(
        0,
        CollectionEntry(
          id: '77777777-7777-4777-8777-${(nextId++).toString().padLeft(12, '0')}',
          kind: CollectionKind.word,
          displayText: row.word,
          targetLanguage: row.language,
          meaning: row.meaning,
          createdAt: now,
          reading: row.reading?.isEmpty == true ? null : row.reading,
          lemma: row.lemma?.isEmpty == true ? null : row.lemma,
          context: row.context?.isEmpty == true ? null : row.context,
          sourceTitle: row.sourceTitle,
          notebookIds: notebookIds,
          notes: row.notes,
          tags: row.tags,
          importedStatus: row.status,
          exerciseControl: row.exerciseControl,
          sourceCreatedAt: row.sourceCreatedAt,
          sourceUpdatedAt: row.sourceUpdatedAt,
        ),
      );
      added++;
    }
    collections
      ..clear()
      ..addAll(nextCollections);
    notebooks
      ..clear()
      ..addAll(nextNotebooks);
    _nextId = nextId;
    notifyListeners();
    return CsvImportResult(added: added, merged: merged, skipped: skipped, excluded: excluded);
  }

  void setCollectionNotebooks(String id, Set<String> notebookIds) {
    final index = collections.indexWhere((item) => item.id == id);
    if (index < 0) throw ArgumentError.value(id, 'id');
    final item = collections[index];
    for (final notebookId in notebookIds) {
      final notebook = notebooks.where((book) => book.id == notebookId).firstOrNull;
      if (notebook == null || notebook.targetLanguage != item.targetLanguage) {
        throw ArgumentError.value(notebookId, 'notebookIds');
      }
    }
    if (setEquals(item.notebookIds, notebookIds)) return;
    collections[index] = item.copyWith(notebookIds: Set.unmodifiable(notebookIds));
    notifyListeners();
  }

  LearningCard runQuery(String query) {
    final text = query.trim();
    if (text.isEmpty) throw ArgumentError('query');
    lastQuery = text;
    lastCard = _sampleCardFor(text);
    _recordQuery(text, lastCard!);
    savedExplanationCount++;
    localExplanationCount++;
    notifyListeners();
    return lastCard!;
  }

  void _recordQuery(String prompt, LearningCard card, {String? targetLanguage}) {
    _queryHistory.add(
      QueryHistoryEntry(
        prompt: prompt,
        card: card,
        targetLanguage: targetLanguage ?? activeLanguage,
      ),
    );
  }

  LearningCard _sampleCardFor(String text) => text.contains('に') && text.contains('へ')
      ? cards[2]
      : text.contains('批改') || text.contains('行きます')
      ? cards[3]
      : text.contains('夏の風') || text.contains('翻译')
      ? cards[1]
      : text.contains('穏やか')
      ? cards[4]
      : cards[0];

  Future<LearningCard?> resolveQuery(
    QueryRequest request, {
    String scopeBinding = 'standalone-preview',
  }) async {
    final saved = _resolvedQueries[_scopedQueryKey(scopeBinding, _queryIdentity(request))];
    if (saved == null) return null;
    lastQuery = request.text.trim();
    lastCard = saved;
    notifyListeners();
    return saved;
  }

  Future<LearningCard> generateQuery(
    QueryRequest request, {
    String scopeBinding = 'standalone-preview',
  }) async {
    final text = request.text.trim();
    if (text.isEmpty) throw ArgumentError('query');
    final base = _sampleCardFor(text);
    final digest = _queryIdentity(request);
    final card = LearningCard(
      id: '${digest.substring(0, 8)}-${digest.substring(8, 12)}-${digest.substring(12, 16)}-${digest.substring(16, 20)}-${digest.substring(20, 32)}',
      kind: base.kind,
      title: base.title,
      explanation: base.explanation,
      examples: base.examples,
      version: base.version,
      wordDetail: base.wordDetail,
    );
    _resolvedQueries[_scopedQueryKey(scopeBinding, digest)] = card;
    _savedQueryCards[_scopedQueryKey(scopeBinding, card.id)] = card;
    _savedQueryTargetLanguages[_scopedQueryKey(scopeBinding, card.id)] = request.targetLanguage;
    lastQuery = text;
    lastCard = card;
    savedExplanationCount++;
    notifyListeners();
    return card;
  }

  @override
  Future<LearningCard> readSaved(String id) async =>
      savedQueryCard(id) ?? (throw StateError('Saved preview result unavailable'));

  @override
  Future<LearningCard> submit(QueryRequest request) async {
    final card = await resolveQuery(request) ?? await generateQuery(request);
    _recordQuery(request.text.trim(), card, targetLanguage: request.targetLanguage);
    notifyListeners();
    return card;
  }

  void saveCard(LearningCard card) {
    if (collections.any((item) => item.displayText == card.title)) return;
    collections.insert(
      0,
      CollectionEntry(
        id: '77777777-7777-4777-8777-${(_nextId++).toString().padLeft(12, '0')}',
        kind: card.kind,
        displayText: card.title,
        targetLanguage: activeLanguage,
        meaning: card.explanation,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    notifyListeners();
  }

  void chooseAnswer(int answer) {
    if (exerciseSubmitted) return;
    selectedAnswer = answer;
    notifyListeners();
  }

  void submitExercise() {
    if (selectedAnswer == null) return;
    exerciseSubmitted = true;
    notifyListeners();
  }

  void resetExercise() {
    exerciseSubmitted = false;
    selectedAnswer = null;
    notifyListeners();
  }

  void submitExam(Map<int, int> answers) {
    if (examSubmitted) return;
    examDraftAnswers = Map.unmodifiable(answers);
    examAnswers = Map.unmodifiable(answers);
    examSubmitted = true;
    examDraftSaved = true;
    notifyListeners();
  }

  void chooseExamAnswer(int question, int choice) {
    if (examSubmitted || question < 0 || question >= 3 || choice < 0 || choice >= 4) return;
    examDraftAnswers = Map.unmodifiable({...examDraftAnswers, question: choice});
    examDraftSaved = false;
    notifyListeners();
  }

  void toggleExamMark(int question) {
    if (examSubmitted || question < 0 || question >= 3) return;
    final next = {...examMarkedQuestions};
    if (!next.add(question)) next.remove(question);
    examMarkedQuestions = Set.unmodifiable(next);
    examDraftSaved = false;
    notifyListeners();
  }

  void selectExamQuestion(int question) {
    if (question < 0 || question >= 3 || examCurrentQuestion == question) return;
    examCurrentQuestion = question;
    notifyListeners();
  }

  void saveExamDraft() {
    if (examSubmitted) return;
    examDraftSaved = true;
    notifyListeners();
  }

  void readNotification(String id) {
    final index = notifications.indexWhere((item) => item.id == id);
    if (index < 0 || notifications[index].readAt != null) return;
    notifications[index] = notifications[index].read(DateTime.now().toUtc());
    notifyListeners();
  }

  void readAllNotifications() {
    final now = DateTime.now().toUtc();
    for (var i = 0; i < notifications.length; i++) {
      if (notifications[i].readAt == null) notifications[i] = notifications[i].read(now);
    }
    notifyListeners();
  }

  void saveCacheLimits(int textMb, int audioMb) {
    textLimitMb = textMb;
    audioLimitMb = audioMb;
    settingsDraft.textLimitMb = textMb;
    settingsDraft.audioLimitMb = audioMb;
    notifyListeners();
  }

  void editSettingsDraft(void Function(SettingsDraft draft) edit) {
    edit(settingsDraft);
    notifyListeners();
  }

  void saveLanguages() {
    nativeLanguages = {...settingsDraft.nativeLanguages};
    learningLanguages = {...settingsDraft.learningLanguages};
    activeLanguage = settingsDraft.activeLanguage;
    explanationLanguage = settingsDraft.explanationLanguage;
    learningLevel = settingsDraft.learningLevel;
    notifyListeners();
  }

  void saveLearningGoals() {
    learningGoals = {...settingsDraft.learningGoals};
    notifyListeners();
  }

  void saveReadingPreferences() {
    readingFont = settingsDraft.readingFont;
    readingFontSize = settingsDraft.readingFontSize;
    readingLineHeight = settingsDraft.readingLineHeight;
    readingTheme = settingsDraft.readingTheme;
    notifyListeners();
  }

  void saveQueryPreferences() {
    queryContextBudget = settingsDraft.queryContextBudget;
    notifyListeners();
  }

  void saveModelPreferences() {
    modelProvider = settingsDraft.modelProvider;
    textModel = settingsDraft.textModel;
    visionModel = settingsDraft.visionModel;
    notifyListeners();
  }

  void setPersonalApiKeyConfigured(bool configured) {
    hasPersonalApiKey = configured;
    notifyListeners();
  }

  void saveSpeechPreferences() {
    ttsModel = settingsDraft.ttsModel;
    speechVoice = settingsDraft.speechVoice;
    speechFormat = settingsDraft.speechFormat;
    speechStyle = settingsDraft.speechStyle;
    speechSpeed = settingsDraft.speechSpeed;
    notifyListeners();
  }

  void validateServiceAddress() {
    serviceProbeAttempted = true;
    final uri = Uri.tryParse(settingsDraft.serviceAddress.trim());
    serviceAddressValidated =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
    if (serviceAddressValidated) serviceAddress = settingsDraft.serviceAddress.trim();
    notifyListeners();
  }

  void markPasswordChanged() {
    passwordChangeCount++;
    notifyListeners();
  }

  void clearLocalCache() {
    localExplanationCount = 0;
    localAudioCount = 0;
    notifyListeners();
  }

  void updateProfile({String? name, String? language, String? explanation}) {
    if (name != null) displayName = name.trim();
    if (language != null) {
      activeLanguage = language;
      settingsDraft.activeLanguage = language;
    }
    if (explanation != null) {
      explanationLanguage = explanation;
      settingsDraft.explanationLanguage = explanation;
    }
    notifyListeners();
  }

  void updateProfileDetails({
    required String name,
    required int? birthYear,
    required String gender,
    required String timezone,
    required bool allowProfileForAi,
  }) {
    displayName = name.trim();
    this.birthYear = birthYear;
    this.gender = gender;
    this.timezone = timezone;
    this.allowProfileForAi = allowProfileForAi;
    notifyListeners();
  }

  void setProfileAiConsent(bool value) {
    allowProfileForAi = value;
    notifyListeners();
  }

  void selectSampleAvatar() {
    avatarGlyph = avatarGlyph == '遥' ? '花' : '遥';
    notifyListeners();
  }

  void updateAppearance(String mode, bool reduceMotion) {
    themeMode = mode;
    reducedMotion = reduceMotion;
    notifyListeners();
  }

  void setSpeechSpeed(double value) {
    speechSpeed = value;
    settingsDraft.speechSpeed = value;
    notifyListeners();
  }
}

final class SettingsDraft {
  SettingsDraft.fromStore(PreviewFixtureStore store)
    : activeLanguage = store.activeLanguage,
      explanationLanguage = store.explanationLanguage,
      nativeLanguages = {...store.nativeLanguages},
      learningLanguages = {...store.learningLanguages},
      learningLevel = store.learningLevel,
      learningGoals = {...store.learningGoals},
      readingFont = store.readingFont,
      readingFontSize = store.readingFontSize,
      readingLineHeight = store.readingLineHeight,
      readingTheme = store.readingTheme,
      queryContextBudget = store.queryContextBudget,
      queryBudgetText = store.queryContextBudget.toString(),
      modelProvider = store.modelProvider,
      textModel = store.textModel,
      visionModel = store.visionModel,
      ttsModel = store.ttsModel,
      speechVoice = store.speechVoice,
      speechFormat = store.speechFormat,
      speechStyle = store.speechStyle,
      speechSpeed = store.speechSpeed,
      serviceAddress = store.serviceAddress,
      textLimitMb = store.textLimitMb,
      audioLimitMb = store.audioLimitMb;

  String activeLanguage;
  String explanationLanguage;
  Set<String> nativeLanguages;
  Set<String> learningLanguages;
  String learningLevel;
  Set<String> learningGoals;
  String readingFont;
  int readingFontSize;
  double readingLineHeight;
  String readingTheme;
  int queryContextBudget;
  String queryBudgetText;
  String modelProvider;
  String textModel;
  String visionModel;
  String ttsModel;
  String speechVoice;
  String speechFormat;
  String speechStyle;
  double speechSpeed;
  String serviceAddress;
  int textLimitMb;
  int audioLimitMb;
  int usageDays = 30;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import 'package:haruka/shared/domain/learning_records.dart';

const vocabularyCsvMaxBytes = 10 * 1024 * 1024;
const vocabularyCsvMaxRows = 10000;
const vocabularyCsvMaxFieldLength = 20000;

const vocabularyCsvHeader = [
  'schema_version',
  'csv_escape',
  'item_id',
  'word',
  'lemma',
  'language',
  'reading',
  'meaning',
  'context',
  'notes',
  'tags',
  'status',
  'mastery_policy_version',
  'exercise_control',
  'wordbooks',
  'source_title',
  'source_locator',
  'created_at',
  'updated_at',
];

enum CsvProblem {
  emptyFile,
  tooLarge,
  tooManyRows,
  invalidUtf8,
  invalidQuotes,
  missingWordColumn,
  repeatedColumn,
  rowWidth,
  missingWord,
  invalidLanguage,
  invalidVersion,
  invalidEscape,
  invalidTags,
  invalidWordbooks,
  invalidStatus,
  invalidExerciseControl,
  invalidDate,
  invalidLocator,
  fieldTooLong,
}

final class CsvReadException implements Exception {
  const CsvReadException(this.problem);
  final CsvProblem problem;
}

enum CsvDuplicateKind { none, existing, file }

enum CsvDuplicateAction { skip, merge, create }

final class VocabularyCsvImportOutcome {
  const VocabularyCsvImportOutcome({
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

final class VocabularyCsvRow {
  const VocabularyCsvRow({
    required this.number,
    required this.word,
    required this.language,
    required this.meaning,
    required this.issues,
    required this.duplicate,
    required this.notebookNames,
    required this.tags,
    this.itemId,
    this.lemma,
    this.reading,
    this.context,
    this.notes = '',
    this.status,
    this.exerciseControl = 'active',
    this.sourceTitle,
    this.sourceCreatedAt,
    this.sourceUpdatedAt,
    this.unboundSource = false,
  });

  final int number;
  final String word;
  final String language;
  final String meaning;
  final String? itemId;
  final String? lemma;
  final String? reading;
  final String? context;
  final String notes;
  final List<String> tags;
  final String? status;
  final String exerciseControl;
  final List<String> notebookNames;
  final String? sourceTitle;
  final DateTime? sourceCreatedAt;
  final DateTime? sourceUpdatedAt;
  final bool unboundSource;
  final List<CsvProblem> issues;
  final CsvDuplicateKind duplicate;

  bool get valid => issues.isEmpty;
}

final class VocabularyCsvPreview {
  const VocabularyCsvPreview({required this.rows, required this.filename});
  final List<VocabularyCsvRow> rows;
  final String filename;

  int get validCount => rows.where((row) => row.valid).length;
  int get errorCount => rows.where((row) => !row.valid).length;
  int get duplicateCount =>
      rows.where((row) => row.valid && row.duplicate != CsvDuplicateKind.none).length;
  int get newCount => validCount - duplicateCount;
}

String _safeCell(String value) {
  if (value.startsWith("'") ||
      value.startsWith('\t') ||
      value.startsWith('\r') ||
      value.startsWith('\n') ||
      RegExp(r'^[\s]*[=+\-@＝＋－＠]').hasMatch(value)) {
    return "'$value";
  }
  return value;
}

String _readCell(String value, {required bool escaped}) {
  if (!escaped || !value.startsWith("'")) return value;
  final rest = value.substring(1);
  return _safeCell(rest) == value ? rest : value;
}

String vocabularyCsvDuplicateKey({
  required String word,
  required String language,
  String? context,
  String? sourceTitle,
}) => [
  language.trim().toLowerCase(),
  word.trim().toLowerCase(),
  (context ?? '').trim().toLowerCase(),
  (sourceTitle ?? '').trim().toLowerCase(),
].join('\u001f');

Uint8List exportVocabularyCsv(Iterable<CollectionEntry> items, Iterable<NotebookRecord> notebooks) {
  final namesById = {for (final book in notebooks) book.id: book.name};
  final words = items.where((item) => item.kind == CollectionKind.word).toList()
    ..sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  final rows = <List<String>>[
    vocabularyCsvHeader,
    for (final item in words)
      [
        '2',
        'apostrophe-v1',
        item.id,
        _safeCell(item.displayText),
        _safeCell(item.lemma ?? ''),
        item.targetLanguage,
        _safeCell(item.reading ?? ''),
        _safeCell(item.meaning),
        _safeCell(item.context ?? ''),
        _safeCell(item.notes),
        jsonEncode(item.tags),
        item.importedStatus ?? 'new',
        '',
        item.exerciseControl,
        jsonEncode(
          (item.notebookIds.map((id) => namesById[id]).whereType<String>().toList()..sort()),
        ),
        _safeCell(item.sourceTitle ?? ''),
        '',
        (item.sourceCreatedAt ?? item.createdAt).toUtc().toIso8601String(),
        item.sourceUpdatedAt?.toUtc().toIso8601String() ?? '',
      ],
  ];
  return Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(Csv().encode(rows))]);
}

VocabularyCsvPreview previewVocabularyCsv({
  required Uint8List bytes,
  required String filename,
  required Iterable<CollectionEntry> existing,
  required String defaultLanguage,
}) {
  if (bytes.isEmpty) throw const CsvReadException(CsvProblem.emptyFile);
  if (bytes.length > vocabularyCsvMaxBytes) {
    throw const CsvReadException(CsvProblem.tooLarge);
  }
  late final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', '');
  } on FormatException {
    throw const CsvReadException(CsvProblem.invalidUtf8);
  }
  if (_unclosedQuote(source)) {
    throw const CsvReadException(CsvProblem.invalidQuotes);
  }
  final List<List<dynamic>> decoded;
  try {
    decoded = Csv(fieldDelimiter: ',').decode(source);
  } on FormatException {
    throw const CsvReadException(CsvProblem.invalidQuotes);
  }
  if (decoded.isEmpty || decoded.first.isEmpty) {
    throw const CsvReadException(CsvProblem.emptyFile);
  }
  if (decoded.length - 1 > vocabularyCsvMaxRows) {
    throw const CsvReadException(CsvProblem.tooManyRows);
  }
  final header = decoded.first.map((value) => value.toString().trim().toLowerCase()).toList();
  if (header.toSet().length != header.length) {
    throw const CsvReadException(CsvProblem.repeatedColumn);
  }
  final wordColumn = _column(header, ['word', '单词', '词条']);
  if (wordColumn < 0) {
    throw const CsvReadException(CsvProblem.missingWordColumn);
  }
  final existingKeys = {
    for (final item in existing.where((item) => item.kind == CollectionKind.word))
      vocabularyCsvDuplicateKey(
        word: item.displayText,
        language: item.targetLanguage,
        context: item.context,
        sourceTitle: item.sourceTitle,
      ),
  };
  final fileKeys = <String>{};
  final rows = <VocabularyCsvRow>[];
  for (var i = 1; i < decoded.length; i++) {
    final fields = decoded[i].map((value) => value.toString()).toList();
    if (fields.every((value) => value.trim().isEmpty)) continue;
    final issues = <CsvProblem>[];
    if (fields.length != header.length) issues.add(CsvProblem.rowWidth);
    String cell(List<String> columns) {
      final index = _column(header, columns);
      return index < 0 || index >= fields.length ? '' : fields[index];
    }

    final version = cell(['schema_version']);
    if (version.isNotEmpty && version != '1' && version != '2') {
      issues.add(CsvProblem.invalidVersion);
    }
    final escape = cell(['csv_escape']);
    if (escape.isNotEmpty && escape != 'apostrophe-v1') {
      issues.add(CsvProblem.invalidEscape);
    }
    String textCell(List<String> columns) =>
        _readCell(cell(columns), escaped: escape == 'apostrophe-v1');
    final word = textCell(['word', '单词', '词条']).trim();
    final language = cell(['language', '语言']).trim().isEmpty
        ? defaultLanguage
        : cell(['language', '语言']).trim().toLowerCase();
    if (word.isEmpty) issues.add(CsvProblem.missingWord);
    if (language != 'ja' && language != 'en') {
      issues.add(CsvProblem.invalidLanguage);
    }
    if (fields.any((value) => value.length > vocabularyCsvMaxFieldLength)) {
      issues.add(CsvProblem.fieldTooLong);
    }
    List<String> parseArray(String raw, CsvProblem problem) {
      if (raw.trim().isEmpty) return [];
      try {
        final value = jsonDecode(raw);
        if (value is List && value.every((entry) => entry is String)) {
          return value.cast<String>().toSet().toList();
        }
      } on FormatException {
        // The issue is added below.
      }
      issues.add(problem);
      return [];
    }

    final tags = parseArray(cell(['tags']), CsvProblem.invalidTags);
    final wordbooks = parseArray(cell(['wordbooks']), CsvProblem.invalidWordbooks);
    var status = cell(['status']);
    if (status.isNotEmpty &&
        !['new', 'learning', 'mastered', 'needs_practice', 'paused'].contains(status)) {
      issues.add(CsvProblem.invalidStatus);
    }
    var exerciseControl = cell(['exercise_control']);
    if (status == 'paused' && version != '1') {
      issues.add(CsvProblem.invalidStatus);
    }
    if (status == 'paused' && version == '1' && exerciseControl.isEmpty) {
      exerciseControl = 'excluded';
    }
    if (exerciseControl.isEmpty) exerciseControl = 'active';
    if (exerciseControl != 'active' && exerciseControl != 'excluded') {
      issues.add(CsvProblem.invalidExerciseControl);
    }
    if (status == 'paused') status = '';
    DateTime? parseDate(String raw) {
      if (raw.isEmpty) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null || !raw.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
        issues.add(CsvProblem.invalidDate);
        return null;
      }
      return parsed.toUtc();
    }

    final sourceTitle = textCell(['source_title']);
    final unboundSource = cell(['source_locator']).trim().isNotEmpty;
    final key = vocabularyCsvDuplicateKey(
      word: word,
      language: language,
      context: textCell(['context']),
      sourceTitle: sourceTitle,
    );
    final duplicate = existingKeys.contains(key)
        ? CsvDuplicateKind.existing
        : fileKeys.contains(key)
        ? CsvDuplicateKind.file
        : CsvDuplicateKind.none;
    fileKeys.add(key);
    rows.add(
      VocabularyCsvRow(
        number: i + 1,
        word: word,
        language: language,
        meaning: textCell(['meaning', '释义']),
        itemId: cell(['item_id']),
        lemma: textCell(['lemma']),
        reading: textCell(['reading']),
        context: textCell(['context']),
        notes: textCell(['notes']),
        tags: tags,
        status: status.isEmpty ? null : status,
        exerciseControl: exerciseControl,
        notebookNames: wordbooks,
        sourceTitle: sourceTitle.isEmpty ? null : sourceTitle,
        sourceCreatedAt: parseDate(cell(['created_at'])),
        sourceUpdatedAt: parseDate(cell(['updated_at'])),
        unboundSource: unboundSource,
        issues: issues,
        duplicate: duplicate,
      ),
    );
  }
  return VocabularyCsvPreview(rows: rows, filename: filename);
}

int _column(List<String> header, List<String> aliases) {
  for (final alias in aliases) {
    final index = header.indexOf(alias);
    if (index >= 0) return index;
  }
  return -1;
}

bool _unclosedQuote(String value) {
  var quoted = false;
  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) != 34) continue;
    if (quoted && i + 1 < value.length && value.codeUnitAt(i + 1) == 34) {
      i++;
    } else {
      quoted = !quoted;
    }
  }
  return quoted;
}

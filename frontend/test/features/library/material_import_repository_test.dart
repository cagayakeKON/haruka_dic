import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/library/data/material_import_repository.dart';
import 'package:haruka/features/library/data/material_repository.dart';
import 'package:haruka/features/library/domain/material_import.dart';
import 'package:haruka/features/library/domain/material_metadata.dart';
import 'package:haruka/features/library/domain/material_summary.dart';

import '../../support/generated/api_compatibility_samples.dart';
import '../../support/sample_adapter.dart';

const _intentId = '018f1234-0000-7000-8000-0000000000aa';
const _uploadId = '018f1234-0000-7000-8000-0000000000bb';
const _materialId = '018f1234-0000-7000-8000-0000000000cc';
const _jobId = '018f1234-0000-7000-8000-0000000000dd';
const _requestId = '018f1234-0000-7000-8000-000000000099';

void main() {
  test('only the verified snapshot is uploaded and completion keeps its intent key', () async {
    final h = await _Harness.start();
    final file = _MutableFile([35, 32, 65]);
    final intent = await h.create(file);
    expect((h.createBody!['file'] as Map)['sha256'], sha256.convert([35, 32, 65]).toString());
    file.bytes = [9, 9, 9, 9, 9];
    final accepted = await h.repository.uploadAndComplete(intent, file);
    expect(accepted.accepted, isTrue);
    expect(h.uploaded, [35, 32, 65]);
    expect(file.reads, 1);
    expect(
      h.uploadHeaders.keys.any(
        (key) => const {'cookie', 'authorization'}.contains(key.toLowerCase()),
      ),
      isFalse,
    );
    expect(h.uploadHeaders['X-Haruka-Upload-Grant'], 'synthetic-staging-only');
    expect(h.completeBody, {'expected_revision': 1});
    expect(h.completeKey, _intentId);
    expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
  });

  test('a source that grows during snapshot reading is rejected before intent creation', () async {
    final h = await _Harness.start();
    final file = _MutableFile([1, 2, 3], declaredSize: 2);
    await expectLater(h.create(file), throwsA(_code('INPUT_INVALID')));
    expect(h.createWrites, 0);
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
  });

  test(
    'concurrent file readers share one bounded snapshot budget and release on failure',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final h = await _Harness.start(maxSize: 80 * 1024 * 1024);
      final first = _MutableFile(
        [],
        declaredSize: 80 * 1024 * 1024,
        beforeRead: () async {
          started.complete();
          await release.future;
        },
      );
      final pending = h.create(first);
      final failed = expectLater(pending, throwsA(_code('INPUT_INVALID')));
      await started.future;
      final second = _MutableFile([1]);
      await expectLater(h.create(second), throwsA(_code('STATE_CONFLICT')));
      expect(second.reads, 0);
      expect(h.createWrites, 0);
      release.complete();
      await failed;
      expect((await h.create(second)).status, 'awaiting_upload');
      expect(second.reads, 1);
      expect(h.createWrites, 1);
    },
  );

  for (final target in [
    'https://external.example/api/v1/uploads/$_uploadId/content',
    '/api/v1/uploads/$_materialId/content',
    '/api/v1/uploads/$_uploadId/content?token=unexpected',
    '/api/v1/uploads/$_uploadId/content#fragment',
    'http://user@localhost:18443/api/v1/uploads/$_uploadId/content',
  ]) {
    test(
      'a forged staging target is rejected before private file transmission: ${Uri.parse(target).hasQuery
          ? 'query'
          : Uri.parse(target).hasFragment
          ? 'fragment'
          : Uri.parse(target).userInfo.isNotEmpty
          ? 'userinfo'
          : Uri.parse(target).host.isEmpty
          ? 'different resource'
          : 'external origin'}',
      () async {
        final h = await _Harness.start(uploadTarget: target);
        final file = _MutableFile([1, 2, 3]);
        // Structurally invalid grants are rejected at the JSON boundary; valid
        // external and wrong-resource grants fail the transport fence.
        await expectLater(() async {
          final intent = await h.create(file);
          await h.repository.uploadAndComplete(intent, file);
        }(), throwsA(isA<ApiFailure>()));
        expect(h.uploaded, isEmpty);
        expect(h.completeWrites, 0);
      },
    );
  }

  test('logout during staging transfer never completes the old owner import', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final h = await _Harness.start(
      uploadWait: () async {
        started.complete();
        await release.future;
      },
    );
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    final pending = h.repository.uploadAndComplete(intent, file);
    await started.future;
    await h.auth.logout();
    release.complete();
    await expectLater(pending, throwsA(_code('SESSION_INVALID')));
    expect(h.completeWrites, 0);
  });

  test('unknown completion is recovered by reading the existing accepted import', () async {
    final h = await _Harness.start(loseCompletionResponse: true);
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    await expectLater(h.repository.uploadAndComplete(intent, file), throwsA(isA<ApiFailure>()));
    expect(h.completeWrites, 1);
    final recovered = await h.repository.find(intent.id);
    expect(recovered.accepted, isTrue);
    expect(recovered.materialId, _materialId);
    expect(recovered.jobId, _jobId);
    expect(h.completeWrites, 1);
    expect(h.createWrites, 1);
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
  });

  test(
    'cancellation sends revision CAS and authenticated write headers then drops bytes',
    () async {
      final h = await _Harness.start();
      final file = _MutableFile([1, 2, 3]);
      final intent = await h.create(file);
      await h.repository.cancel(intent);
      expect(h.cancelRevision, '1');
      expect(h.cancelHeaders['X-CSRF-Token'], isNotEmpty);
      await expectLater(
        h.repository.uploadAndComplete(intent, file),
        throwsA(_code('SESSION_INVALID')),
      );
      expect(h.completeWrites, 0);
    },
  );

  test('unsupported language and type-format combination create no intent', () async {
    final h = await _Harness.start();
    await expectLater(
      h.create(_MutableFile([1, 2, 3]), language: 'zh'),
      throwsA(_code('INPUT_INVALID')),
    );
    await expectLater(
      h.create(_MutableFile([1, 2, 3], filename: 'scan.png')),
      throwsA(_code('INPUT_INVALID')),
    );
    expect(h.createWrites, 0);
    expect(h.completeWrites, 0);
  });

  test('PDF admission follows the current novel and textbook capabilities', () async {
    for (final type in [LearningMaterialType.novel, LearningMaterialType.textbook]) {
      final h = await _Harness.start();
      final intent = await h.repository.create(
        file: _MutableFile([37, 80, 68, 70], filename: 'source.pdf'),
        type: type,
        language: 'ja',
        title: '合成PDF',
        idempotencyKey: _intentId,
      );
      expect(intent.type, type);
      expect(intent.status, 'awaiting_upload');
      expect(intent.accepted, isFalse);
      expect(intent.materialId, isNull);
      expect((h.createBody!['file'] as Map)['format'], 'pdf');
      expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
      expect(h.uploaded, isEmpty);
      expect(h.completeWrites, 0);
    }
  });

  test('expired local intent drops its snapshot without cancelling server state', () async {
    final h = await _Harness.start();
    final file = _MutableFile([1, 2, 3]);
    final intent = await h.create(file);
    final expired = MaterialImport(
      id: intent.id,
      revision: intent.revision,
      type: intent.type,
      language: intent.language,
      status: intent.status,
      expiresAt: DateTime.utc(2000),
      upload: intent.upload,
    );
    await expectLater(
      h.repository.uploadAndComplete(expired, file),
      throwsA(_code('RESOURCE_EXPIRED')),
    );
    await expectLater(
      h.repository.uploadAndComplete(intent, file),
      throwsA(_code('SESSION_INVALID')),
    );
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
    expect(h.cancelRevision, isNull);
  });

  test('owned source reuse sends only its ID and never stages private bytes', () async {
    final h = await _Harness.start();
    final result = await h.repository.reimportExisting(
      sourceId: _materialId,
      targetType: LearningMaterialType.exam,
      language: 'en',
      title: ' 新材料 ',
      idempotencyKey: _intentId,
    );
    expect(result.accepted, isTrue);
    expect(result.upload, isNull);
    expect(result.type, LearningMaterialType.exam);
    expect(h.createBody!['source_material_id'], _materialId);
    expect(h.createBody!.containsKey('file'), isFalse);
    expect(h.createBody!['title'], '新材料');
    expect(h.createBody!['requested_stages'], {'extract': true, 'analyze': false});
    expect(h.uploaded, isEmpty);
    expect(h.completeWrites, 0);
    expect(h.materialWrites, isEmpty);
  });

  test(
    'catalog preserves null content IDs and scoped filters without claiming readiness',
    () async {
      final h = await _Harness.start();
      final page = await HttpMaterialRepository(h.auth).list(
        type: LearningMaterialType.exam,
        language: 'en',
        search: ' 合成 ',
        cursor: 'safe-cursor',
      );
      expect(h.materialQuery, {
        'limit': '20',
        'material_type': 'exam',
        'language': 'en',
        'search': '合成',
        'cursor': 'safe-cursor',
      });
      expect(page.nextCursor, 'next-safe-cursor');
      final material = page.data.single;
      expect(material.sourceStatus, 'parsing');
      expect(material.analysisStatus, 'not_requested');
      expect(material.readable, isFalse);
      expect(material.contentRevisionId, isNull);
      expect(material.firstChapterId, isNull);
      expect(material.progressPercent, isNull);
      expect(material.revision, 3);
    },
  );

  test('material title and tombstone deletion use current revision and CSRF', () async {
    final h = await _Harness.start();
    final catalog = HttpMaterialRepository(h.auth);
    final renamed = await catalog.rename(_materialId, 3, ' 修改后 ');
    expect(renamed.title, '修改后');
    expect(renamed.revision, 4);
    await catalog.delete(_materialId, renamed.revision);
    expect(h.materialWrites, [
      {'expected_revision': 3, 'title': '修改后'},
      {'expected_revision': '4'},
    ]);
    expect(h.materialWriteHeaders.every((headers) => headers['X-CSRF-Token'] is String), isTrue);
    expect(h.completeWrites, 0);
    expect(h.createWrites, 0);
  });

  test('old published IDs remain available and unsupported metadata is rejected', () {
    final json = _metadata()
      ..['revision_id'] = _intentId
      ..['first_chapter_id'] = _uploadId
      ..['source_status'] = 'readable'
      ..['readable'] = true;
    final old = MaterialMetadata.fromJson(json);
    expect(old.contentRevisionId, _intentId);
    expect(old.firstChapterId, _uploadId);
    expect(old.readable, isTrue);
    expect(
      () => MaterialMetadata.fromJson({...json, 'material_type': 'mixed'}),
      throwsFormatException,
    );
    expect(
      () => MaterialMetadata.fromJson({...json, 'progress_percent': 101}),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _metadata() => {
  'id': _materialId,
  'library_id': _intentId,
  'material_type': 'exam',
  'title': '合成材料',
  'language': 'en',
  'source_format': 'pdf',
  'source_status': 'parsing',
  'analysis_status': 'not_requested',
  'revision': 3,
  'delete_generation': 0,
  'revision_id': null,
  'first_chapter_id': null,
  'job_id': _jobId,
  'progress_percent': null,
  'readable': false,
  'created_at': '2026-10-02T00:00:00Z',
  'updated_at': '2026-10-02T00:00:00Z',
};

Matcher _code(String code) => isA<ApiFailure>().having((error) => error.code, 'code', code);

final class _Harness {
  late final AuthController auth;
  late final ApiClient api;
  late final HttpMaterialImportRepository repository;
  Map<String, Object?>? createBody;
  Object? completeBody;
  Object? completeKey;
  int createWrites = 0;
  int completeWrites = 0;
  String? cancelRevision;
  Map<String, dynamic> cancelHeaders = {};
  Map<String, dynamic> uploadHeaders = {};
  final List<int> uploaded = [];
  Map<String, String>? materialQuery;
  final List<Object?> materialWrites = [];
  final List<Map<String, dynamic>> materialWriteHeaders = [];

  static Future<_Harness> start({
    String uploadTarget = '/api/v1/uploads/$_uploadId/content',
    Future<void> Function()? uploadWait,
    bool loseCompletionResponse = false,
    int maxSize = 1024,
  }) async {
    final h = _Harness();
    final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
    final config = AppConfig.parse(
      platform: AppPlatform.web,
      environment: 'dev',
      instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
      apiBaseUrl: 'http://localhost:18443',
    );
    ResponseBody envelope(Object data, [int status = 200]) => ResponseBody.fromString(
      jsonEncode({
        'data': data,
        'meta': {'request_id': _requestId},
      }),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    Map<String, Object?> intent({
      bool accepted = false,
      String type = 'novel',
      String language = 'ja',
    }) => {
      'id': _intentId,
      'revision': accepted ? 2 : 1,
      'material_type': h.createBody?['material_type'] ?? type,
      'language': language,
      'status': accepted ? 'accepted' : 'awaiting_upload',
      'expires_at': '2099-01-01T00:00:00Z',
      'material_id': accepted ? _materialId : null,
      'job_id': accepted ? _jobId : null,
      'upload': accepted
          ? null
          : {
              'id': _uploadId,
              'method': 'PUT',
              'url': uploadTarget,
              'headers': {'X-Haruka-Upload-Grant': 'synthetic-staging-only'},
              'expires_at': '2099-01-01T00:00:00Z',
            },
    };
    final adapter = SampleAdapter((options, _) async {
      switch (options.uri.path) {
        case '/api/v1/meta':
          return envelope({
            'instance_id': config.instanceId,
            'api_version': 'v1',
            'release': 'test',
          });
        case '/api/v1/auth/login':
          return ResponseBody.fromString(
            jsonEncode(samples['auth_web_authenticated']),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/auth/csrf':
          return envelope({
            'session_ref': '018f1234-0000-7000-8000-000000000002',
            'csrf_token': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          });
        case '/api/v1/me/access':
          return ResponseBody.fromString(
            jsonEncode(samples['auth_client_access_login_only']),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/material-import-capabilities':
          return envelope({
            'schema_version': 1,
            'capabilities': [
              {
                'material_type': 'novel',
                'formats': ['md', 'epub', 'pdf'],
                'languages': ['ja', 'en'],
                'max_size_bytes': maxSize,
              },
              {
                'material_type': 'textbook',
                'formats': ['md', 'epub', 'pdf'],
                'languages': ['ja', 'en'],
                'max_size_bytes': maxSize,
              },
              {
                'material_type': 'exam',
                'formats': ['md', 'epub', 'pdf', 'png', 'jpeg', 'webp'],
                'languages': ['ja', 'en'],
                'max_size_bytes': 1024,
              },
            ],
            'quota_bytes': maxSize * 2,
            'used_bytes': 0,
            'reserved_bytes': 0,
            'upload_ttl_seconds': 600,
          });
        case '/api/v1/material-imports':
          h.createWrites++;
          h.createBody = (options.data as Map).cast<String, Object?>();
          if (h.createBody!.containsKey('source_material_id')) {
            return envelope(
              intent(
                accepted: true,
                type: h.createBody!['material_type'] as String,
                language: h.createBody!['language'] as String,
              ),
              201,
            );
          }
          return envelope(intent(), 201);
        case '/api/v1/uploads/$_uploadId/complete':
          h.completeWrites++;
          h.completeBody = options.data;
          h.completeKey = options.headers['Idempotency-Key'];
          if (loseCompletionResponse) {
            throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
          }
          return envelope(intent(accepted: true), 202);
        case '/api/v1/materials':
          h.materialQuery = options.uri.queryParameters;
          return ResponseBody.fromString(
            jsonEncode({
              'data': [_metadata()],
              'meta': {
                'request_id': _requestId,
                'has_more': true,
                'next_cursor': 'next-safe-cursor',
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        case '/api/v1/materials/$_materialId':
          if (options.method == 'PATCH') {
            h.materialWrites.add(options.data);
            h.materialWriteHeaders.add(options.headers);
            return envelope({
              ..._metadata(),
              'title': (options.data as Map)['title'],
              'revision': 4,
            });
          }
          if (options.method == 'DELETE') {
            h.materialWrites.add(options.uri.queryParameters);
            h.materialWriteHeaders.add(options.headers);
            return ResponseBody.fromString('', 204);
          }
          return envelope(_metadata());
        case '/api/v1/material-imports/$_intentId':
          if (options.method == 'DELETE') {
            h.cancelRevision = options.uri.queryParameters['expected_revision'];
            h.cancelHeaders = options.headers;
            return ResponseBody.fromString('', 204);
          }
          return envelope(intent(accepted: true));
      }
      throw const FormatException('Unexpected synthetic route');
    });
    final uploadAdapter = SampleAdapter((options, stream) async {
      h.uploadHeaders = options.headers;
      if (stream != null) {
        await for (final chunk in stream) {
          h.uploaded.addAll(chunk);
        }
      }
      await uploadWait?.call();
      return ResponseBody.fromString('', 204);
    });
    final transport = Dio();
    transport.httpClientAdapter = uploadAdapter;
    h.api = ApiClient(config, adapter: adapter);
    h.auth = AuthController(AuthRepository(h.api, config), config, vault: _Vault(), sync: _Sync());
    h.repository = HttpMaterialImportRepository(h.auth, uploads: transport);
    addTearDown(() {
      h.repository.dispose();
      h.auth.dispose();
      h.api.close();
    });
    expect(await h.auth.login('user@example.test', 'synthetic-test-password'), isTrue);
    h.auth.pauseAccessDeadline();
    return h;
  }

  Future<MaterialImport> create(XFile file, {String language = 'ja'}) => repository.create(
    file: file,
    type: LearningMaterialType.novel,
    language: language,
    title: '合成材料',
    idempotencyKey: _intentId,
  );
}

final class _MutableFile implements XFile {
  _MutableFile(this.bytes, {this.declaredSize, this.filename = 'source.md', this.beforeRead});
  List<int> bytes;
  final int? declaredSize;
  final String filename;
  final Future<void> Function()? beforeRead;
  int reads = 0;
  @override
  String get name => filename;
  @override
  Future<int> length() async => declaredSize ?? bytes.length;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    reads++;
    await beforeRead?.call();
    yield Uint8List.fromList(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected selected-file operation');
}

final class _Vault implements CredentialVault {
  @override
  Future<RefreshCredential?> read() async => null;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async => false;
  @override
  Future<void> clear({String? sessionRef}) async {}
}

final class _Sync implements AuthSync {
  @override
  void dispose() {}
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void publishChanged() {}
  @override
  void publishStarted() {}
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
}

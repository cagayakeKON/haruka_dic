import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/auth/auth_controller.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/auth/auth_sync.dart';
import 'package:haruka/core/auth/credential_vault.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/features/collections/reference_controller.dart';
import 'package:haruka/features/collections/reference_repository.dart';
import 'package:haruka/features/collections/reference_selection.dart';

import '../test_support/sample_adapter.dart';

final class _Vault implements CredentialVault {
  RefreshCredential? value;
  @override
  Future<RefreshCredential?> read() async => value;
  @override
  Future<bool> replace(RefreshCredential? prior, RefreshCredential next) async {
    if (prior == null ? value != null : value == null || !prior.sameVersion(value!)) return false;
    value = next;
    return true;
  }

  @override
  Future<void> clear({String? sessionRef}) async {
    if (sessionRef == null || value?.sessionRef == sessionRef) value = null;
  }
}

final class _Sync implements AuthSync {
  @override
  void publishStarted() {}
  @override
  void publishChanged() {}
  @override
  Future<T> withIdentityLock<T>(Future<T> Function() action) => action();
  @override
  bool locallySignedOut(String audience) => false;
  @override
  void setLocallySignedOut(String audience, bool value) {}
  @override
  void dispose() {}
}

void main() {
  final samples = jsonDecode(
    File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final config = AppConfig.parse(
    platform: AppPlatform.windows,
    environment: 'dev',
    instanceId: 'haruka-test-0123456789abcdef0123456789abcdef',
    apiBaseUrl: 'http://127.0.0.1:18081',
  );
  final card =
      (samples['learning_word_card'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  final locator = (card['source_refs'] as List<dynamic>).single as Map<String, dynamic>;
  final span = (locator['spans'] as List<dynamic>).single as Map<String, dynamic>;
  final requestId = '018f1234-1234-7123-8123-123456789abc';

  ResponseBody body(Object value, [int status = 200]) => ResponseBody.fromString(
    jsonEncode(value),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  for (final staleFailure in [false, true]) {
    test(
      'selection remains usable after stale ${staleFailure ? 'failure' : 'success'} and save retry keeps one key',
      () async {
        final keys = <String>[];
        final firstResolve = Completer<ResponseBody>();
        final firstResolveReached = Completer<void>();
        final staleCollectionRead = Completer<ResponseBody>();
        final collectionReadReached = Completer<void>();
        var collectionReads = 0;
        Map<String, Object?>? selectedLocator;
        var resolveCalls = 0;
        final adapter = SampleAdapter((options, _) async {
          if (options.path == '/api/v1/meta') {
            return body({
              'data': {'instance_id': config.instanceId, 'api_version': 'v1', 'release': 'test'},
              'meta': {'request_id': requestId},
            });
          }
          if (options.path == '/api/v1/auth/native/login') {
            return body(samples['auth_native_authenticated'] as Object);
          }
          if (options.path == '/api/v1/me/access') {
            final access = jsonDecode(
              jsonEncode(samples['auth_client_access_login_only']),
            ) as Map<String, dynamic>;
            (access['data'] as Map<String, dynamic>)['permissions'] = [
              for (final code in [
                'client.login',
                'client.material.list',
                'client.material.read',
                'client.ai.explain',
                'client.collection.create',
                'client.collection.read',
              ])
                {'code': code, 'data_scope': 'self'},
            ];
            return body(access);
          }
          if (options.path.startsWith('/api/v1/materials?')) {
            return body({
              'data': [
                {
                  'id': locator['material_id'],
                  'library_id': locator['library_id'],
                  'revision_id': locator['material_revision_id'],
                  'first_chapter_id': locator['novel_chapter_id'],
                  'material_type': 'novel',
                  'title': locator['source_title'],
                  'language': 'ja',
                  'created_at': '2026-09-26T01:02:03Z',
                },
              ],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          if (options.path.startsWith('/api/v1/novels/')) {
            return body({
              'data': {
                'material_id': locator['material_id'],
                'library_id': locator['library_id'],
                'revision_id': locator['material_revision_id'],
                'node_id': locator['novel_chapter_id'],
                'title': locator['node_title'],
                'blocks': [
                  {
                    'id': span['block_id'],
                    'chapter_block_id': locator['chapter_block_id'],
                    'canonical_text': locator['quote'],
                    'ordinal': 0,
                    'source_locator': locator,
                  },
                ],
              },
              'meta': {'request_id': requestId},
            });
          }
          if (options.path == '/api/v1/explanations/resolve') {
            final target =
                ((options.data as Map<String, dynamic>)['targets'] as List<dynamic>).single
                    as Map<String, dynamic>;
            expect(target['source_locator'], selectedLocator);
            expect(target['explanation_language'], 'zh-CN');
            resolveCalls++;
            if (resolveCalls == 1) {
              firstResolveReached.complete();
              return firstResolve.future;
            }
            return body(samples['learning_resolve_found'] as Object);
          }
          if (options.path == '/api/v1/collections') {
            if (options.method == 'POST') {
              keys.add(options.headers['Idempotency-Key'] as String);
              expect(options.headers['X-Operation-ID'], options.headers['Idempotency-Key']);
              if (keys.length == 1) {
                return body({
                  'error': {
                    'code': 'SERVICE_UNAVAILABLE',
                    'message': 'unavailable',
                    'retryable': true,
                  },
                  'meta': {'request_id': requestId},
                }, 503);
              }
              return body(samples['learning_collection'] as Object, 201);
            }
          }
          if (options.path.startsWith('/api/v1/collections?')) {
            collectionReads++;
            if (collectionReads == 1) {
              collectionReadReached.complete();
              return staleCollectionRead.future;
            }
            return body({
              'data': <Object>[],
              'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
            });
          }
          throw StateError('Unexpected ${options.path}');
        });
        final api = ApiClient(config, adapter: adapter);
        final auth = AuthController(
          AuthRepository(api, config),
          config,
          vault: _Vault(),
          sync: _Sync(),
        );
        expect(await auth.login('user@example.test', 'valid-test-password'), isTrue);
        final reference = ReferenceController(auth, ReferenceRepository(api));
        addTearDown(() {
          reference.dispose();
          auth.dispose();
          api.close();
        });
        await reference.loadMaterials();
        expect(reference.materials, hasLength(1));
        await reference.openMaterial(reference.materials.single);
        expect(reference.chapter!.blocks, hasLength(1));
        final block = reference.chapter!.blocks.single;
        final selection = ReferenceSelection.fromTextSelection(
          block,
          TextSelection(baseOffset: 0, extentOffset: block.text.length),
        )!;
        selectedLocator = selection.locator.toJson();
        reference.select(selection);
        final stale = reference.resolve();
        await firstResolveReached.future;
        reference.select(null);
        reference.select(selection);
        expect(reference.busy, isFalse);
        await reference.resolve();
        expect(reference.resolved?.card?.id, card['card_id']);
        firstResolve.complete(
          staleFailure
              ? body({
                  'error': {'code': 'SERVICE_UNAVAILABLE', 'message': 'failed', 'retryable': true},
                  'meta': {'request_id': requestId},
                }, 503)
              : body(samples['learning_resolve_found'] as Object),
        );
        await stale;
        expect(reference.resolved?.card?.id, card['card_id']);
        expect(reference.busy, isFalse);
        final pendingList = reference.loadCollections();
        await collectionReadReached.future;
        await reference.save();
        expect(reference.saved, isNull);
        await reference.save();
        expect(reference.saved?.cardId, card['card_id']);
        expect(keys, hasLength(2));
        expect(keys[0], keys[1]);
        staleCollectionRead.complete(
          body({
            'data': <Object>[],
            'meta': {'request_id': requestId, 'next_cursor': null, 'has_more': false},
          }),
        );
        await pendingList;
        expect(
          reference.collections.single.id,
          reference.saved!.id,
          reason: 'a stale in-flight list must not erase a confirmed save',
        );
        await reference.loadCollections();
        expect(
          reference.collections,
          isEmpty,
          reason: 'a later explicit refresh is authoritative, not overlaid forever',
        );
      },
    );
  }
}

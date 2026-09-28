import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/features/agent/data/cached_query_result_repository.dart';
import 'package:haruka/features/agent/domain/learning_card.dart';
import 'package:haruka/features/agent/domain/query_request.dart';
import 'package:haruka/features/collections/domain/collection_entry.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'cached_query_result_repository_test.mocks.dart';

@GenerateNiceMocks([MockSpec<CacheRemote<LearningCard>>(as: #MockLearningResultRemote)])
void main() {
  test('saved result reads offline without resolving or generating a query', () async {
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    addTearDown(cache.closeScope);
    final scope = CacheScope.confirmed(
      endpoint: Uri.parse('https://cache.example/api'),
      instanceId: 'query-offline',
      userId: 'reader',
      audience: 'client',
      sessionRef: 'session',
      securityEpoch: 0,
      authzVersion: 1,
      policyVersion: 1,
    );
    await cache.attach(scope);
    const card = LearningCard(
      id: 'saved',
      kind: CollectionKind.word,
      title: 'そっと',
      explanation: '轻轻地',
      examples: [],
      version: 1,
    );
    const version = CacheVersion(resource: '1', representation: 'learning-card-v1', artifact: '1');
    final payload = CachePayload(
      value: card,
      version: version,
      grant: CacheGrant(
        scopeBinding: scope.binding,
        resourceKey: learningResultResource(card.id).keyFor(scope),
        version: version,
        serverTime: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        securityEpoch: 0,
        authzVersion: 1,
        policyVersion: 1,
      ),
    );
    provideDummy<CachePayload<LearningCard>>(payload);
    provideDummy<CacheValidation>(const CacheValidation(state: ValidationState.changed));
    final remote = MockLearningResultRemote();
    when(remote.fetch(any, any)).thenAnswer((_) async => payload);
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: remote,
      resolveSource: (_) async => throw StateError('must not resolve'),
      generateSource: (_) async => throw StateError('must not generate'),
    );
    expect((await repository.readSaved(card.id)).title, 'そっと');
    cache.handleExternalCacheHint('invalidate');
    cache.enterOfflineForUnreachableNetwork();
    expect((await repository.readSaved(card.id)).title, 'そっと');
    await expectLater(
      repository.submit(const QueryRequest(text: 'そっと')),
      throwsA(isA<CacheBlocked>().having((e) => e.reason, 'reason', 'query_requires_network')),
    );
    verify(remote.fetch(any, any)).called(1);
    verifyNever(remote.validate(any, any, any));
  });

  test('rich word fields survive the cached DTO round trip', () {
    const card = LearningCard(
      id: 'word-1',
      kind: CollectionKind.word,
      title: 'そっと',
      explanation: '轻轻地。',
      examples: ['ドアをそっと閉めた。'],
      version: 1,
      wordDetail: WordCardDetail(
        romanization: 'sotto',
        partOfSpeech: '副词',
        meaning: '轻轻地；悄悄地',
        usage: '用于动作轻柔。',
        examples: [WordExample(text: 'ドアをそっと閉めた。', translation: '轻轻地关上门。')],
      ),
    );
    final decoded = LearningCard.fromJson(card.toJson());
    expect(decoded.wordDetail!.meaning, '轻轻地；悄悄地');
    expect(decoded.wordDetail!.examples.single.translation, '轻轻地关上门。');
  });

  test('a hide and return queues a fresh check behind an older visible read', () async {
    const card = LearningCard(
      id: 'visible-card',
      kind: CollectionKind.word,
      title: 'そっと',
      explanation: '轻轻地',
      examples: [],
      version: 1,
    );
    const version = CacheVersion(
      resource: 'visible-card:1',
      representation: 'learning-card-v1',
      artifact: 'visible-card:1',
    );
    provideDummy<CachePayload<LearningCard>>(const CachePayload(value: card, version: version));
    provideDummy<CacheValidation>(
      const CacheValidation(state: ValidationState.same, version: version),
    );
    final remote = MockLearningResultRemote();
    when(remote.fetch(any, any))
        .thenAnswer((_) async => const CachePayload(value: card, version: version));
    final oldCheck = Completer<CacheValidation>();
    final oldCheckStarted = Completer<void>();
    final newCheckFinished = Completer<void>();
    var validations = 0;
    when(remote.validate(any, any, any)).thenAnswer((_) {
      validations++;
      if (validations == 1) {
        oldCheckStarted.complete();
        return oldCheck.future;
      }
      if (validations == 2) newCheckFinished.complete();
      return Future.value(const CacheValidation(state: ValidationState.same, version: version));
    });
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    addTearDown(cache.closeScope);
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://cache.example/api'),
        instanceId: 'visible-query',
        userId: 'reader',
        audience: 'client',
        sessionRef: 'session',
      ),
    );
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: remote,
      resolveSource: (_) async => card,
      generateSource: (_) async => throw StateError('saved result already exists'),
    );
    addTearDown(repository.dispose);
    await repository.submit(const QueryRequest(text: 'そっと'));
    repository.setVisible(true);
    await oldCheckStarted.future;
    repository.setVisible(false);
    repository.setVisible(true);
    expect(validations, 1);
    oldCheck.complete(const CacheValidation(state: ValidationState.same, version: version));
    await newCheckFinished.future;
    expect(validations, greaterThanOrEqualTo(2));
    expect(repository.history.single.card.id, card.id);

    repository.setVisible(false);
    cache.handleExternalCacheHint('invalidate', {'learning-result:*'});
    expect(repository.history, isEmpty);
    final restored = Completer<void>();
    repository.addListener(() {
      if (!restored.isCompleted && repository.history.isNotEmpty) restored.complete();
    });
    repository.setVisible(true);
    await restored.future;
    expect(repository.history.single.card.id, card.id);
  });

  test(
    'mock source result is published, reused after validation, and restored after local clear',
    () async {
      const card = LearningCard(
        id: 'result-1',
        kind: CollectionKind.word,
        title: 'そっと',
        explanation: '轻轻地、悄悄地。',
        examples: ['ドアをそっと閉めた。'],
        version: 1,
      );
      const version = CacheVersion(
        resource: 'result-1:1',
        representation: 'learning-card-v1',
        artifact: 'result-1:1',
      );
      provideDummy<CachePayload<LearningCard>>(const CachePayload(value: card, version: version));
      provideDummy<CacheValidation>(const CacheValidation(state: ValidationState.changed));
      final remote = MockLearningResultRemote();
      when(remote.fetch(any, any))
          .thenAnswer((_) async => const CachePayload(value: card, version: version));
      when(remote.validate(any, any, any)).thenAnswer(
        (_) async => const CacheValidation(state: ValidationState.same, version: version),
      );
      final cache = CacheCoordinator(
        openBackend: (_) async => OpenedCacheBackend(
          executor: NativeDatabase.memory(),
          mode: CacheStorageMode.persistent,
          closeOwner: () async {},
        ),
      );
      const request = QueryRequest(text: 'そっと');
      final saved = <(String, String, String, String), LearningCard>{};
      (String, String, String, String) key(QueryRequest request) =>
          (request.text, request.context, request.targetLanguage, request.explanationLanguage);
      var resolves = 0;
      var generations = 0;
      final repository = CachedQueryResultRepository(
        cache: cache,
        remote: remote,
        resolveSource: (request) async {
          resolves++;
          return saved[key(request)];
        },
        generateSource: (request) async {
          generations++;
          saved[key(request)] = card;
          return card;
        },
      );
      addTearDown(cache.closeScope);
      await cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'preview-query-test',
          userId: 'preview-user',
          audience: 'client',
          sessionRef: 'preview-session',
        ),
      );

      expect(learningResultResource(card.id).action, 'agent.read');
      expect(learningResultResource(card.id).kind, 'learning_text');
      expect(
        learningResultResource(card.id).keyFor(cache.scope!),
        CacheResource(
          kind: 'learning_result',
          id: card.id,
          projection: 'learning-card-v1',
          action: 'agent.read',
          sourceBinding: 'learning-result:${card.id}',
        ).keyFor(cache.scope!),
      );
      expect(repository.history, isEmpty);
      expect((await repository.submit(request)).title, 'そっと');
      expect(repository.history.single.prompt, 'そっと');
      expect((await cache.usage()).textBytes, greaterThan(0));
      verify(remote.fetch(any, any)).called(1);

      expect((await repository.submit(request)).title, 'そっと');
      expect(repository.history, hasLength(2));
      expect(resolves, 2);
      expect(generations, 1);
      verify(remote.validate(any, any, any)).called(1);
      verifyNever(remote.fetch(any, any));

      await cache.clearTextScope();
      expect((await cache.usage()).textBytes, 0);
      expect((await repository.submit(request)).title, 'そっと');
      expect(repository.history, hasLength(3));
      expect(generations, 1);
      expect((await cache.usage()).textBytes, greaterThan(0));
      verify(remote.fetch(any, any)).called(1);

      await cache.closeScope();
      expect(repository.history, isEmpty);
      await cache.attach(
        CacheScope.confirmed(
          endpoint: Uri.parse('https://preview.example/api'),
          instanceId: 'preview-query-test',
          userId: 'another-user',
          audience: 'client',
          sessionRef: 'another-session',
        ),
      );
      expect(repository.history, isEmpty);
      await repository.submit(const QueryRequest(text: 'new account prompt'));
      expect(repository.history.map((entry) => entry.prompt), ['new account prompt']);
    },
  );

  test('unattached cache blocks before resolving or generating the source', () async {
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.persistent,
        closeOwner: () async {},
      ),
    );
    addTearDown(cache.closeScope);
    var readinessChecks = 0;
    var resolves = 0;
    var generations = 0;
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: MockLearningResultRemote(),
      waitForReadiness: () async {
        readinessChecks++;
      },
      resolveSource: (_) async {
        resolves++;
        return null;
      },
      generateSource: (_) async {
        generations++;
        throw StateError('source must not run');
      },
    );

    await expectLater(
      repository.submit(const QueryRequest(text: 'そっと')),
      throwsA(
        isA<CacheBlocked>().having((error) => error.reason, 'reason', 'identity_unconfirmed'),
      ),
    );
    expect(readinessChecks, 1);
    expect(resolves, 0);
    expect(generations, 0);
    expect(repository.history, isEmpty);
  });

  test('unsaved remote projection never becomes a collectible query history card', () async {
    const card = LearningCard(
      id: 'uncommitted-card',
      kind: CollectionKind.word,
      title: '未提交',
      explanation: 'preview only',
      examples: [],
      version: 1,
    );
    const version = CacheVersion(
      resource: 'uncommitted-card:1',
      representation: 'learning-card-v1',
      artifact: 'uncommitted-card:1',
    );
    provideDummy<CachePayload<LearningCard>>(
      const CachePayload(value: card, version: version, serverSaved: false),
    );
    final remote = MockLearningResultRemote();
    when(remote.fetch(any, any)).thenAnswer(
      (_) async => const CachePayload(value: card, version: version, serverSaved: false),
    );
    final cache = CacheCoordinator(
      openBackend: (_) async {
        final executor = NativeDatabase.memory();
        return OpenedCacheBackend(
          executor: executor,
          mode: CacheStorageMode.memoryOnly,
          closeOwner: executor.close,
        );
      },
    );
    addTearDown(cache.closeScope);
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'query-test',
        userId: 'user',
        audience: 'client',
        sessionRef: 'session',
      ),
    );
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: remote,
      resolveSource: (_) async => card,
      generateSource: (_) async => throw StateError('saved source already returned card'),
    );
    await expectLater(
      repository.submit(const QueryRequest(text: 'そっと')),
      throwsA(isA<CacheBlocked>()),
    );
    expect(repository.history, isEmpty);
  });

  test('scope switch during resolve does not generate or publish an old query', () async {
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: NativeDatabase.memory(),
        mode: CacheStorageMode.memoryOnly,
        closeOwner: () async {},
      ),
    );
    addTearDown(cache.closeScope);
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'preview-query-switch-test',
        userId: 'account-a',
        audience: 'client',
        sessionRef: 'session-a',
      ),
    );
    final resolving = Completer<LearningCard?>();
    final started = Completer<void>();
    var generations = 0;
    final repository = CachedQueryResultRepository(
      cache: cache,
      remote: MockLearningResultRemote(),
      resolveSource: (_) {
        started.complete();
        return resolving.future;
      },
      generateSource: (_) async {
        generations++;
        throw StateError('old account must not generate');
      },
    );
    final pending = repository.submit(const QueryRequest(text: 'account-a-private'));
    await started.future;
    await cache.closeScope();
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('https://preview.example/api'),
        instanceId: 'preview-query-switch-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    resolving.complete(null);
    await expectLater(
      pending,
      throwsA(isA<CacheBlocked>().having((error) => error.reason, 'reason', 'scope_changed')),
    );
    expect(generations, 0);
    expect(repository.history, isEmpty);
  });
}

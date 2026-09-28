import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/cache/cache_backend.dart';
import 'package:haruka/core/cache/cache_coordinator.dart';
import 'package:haruka/core/cache/cache_models.dart';
import 'package:haruka/core/cache/cache_partition_lock.dart';
import 'package:haruka/dev/preview/fixture_settings_source.dart';
import 'package:haruka/dev/preview/fixture_store.dart';
import 'package:haruka/features/settings/data/cached_settings_repository.dart';
import 'package:haruka/features/settings/data/settings_source.dart';
import 'package:haruka/features/settings/domain/settings_snapshot.dart';
import 'package:haruka/features/settings/presentation/settings_form_draft.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'cached_settings_repository_test.mocks.dart';

@GenerateNiceMocks([MockSpec<SettingsSource>()])
void main() {
  provideDummy<SettingsSnapshot>(
    SettingsSnapshot(group: SettingsGroup.profile, revision: 1, fields: const {}),
  );

  Future<CacheCoordinator> attachedCache({bool preview = false, bool persistent = false}) async {
    final cache = CacheCoordinator(
      openBackend: (_) async {
        final executor = NativeDatabase.memory();
        return OpenedCacheBackend(
          executor: executor,
          mode: persistent ? CacheStorageMode.persistent : CacheStorageMode.memoryOnly,
          closeOwner: executor.close,
        );
      },
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse(
          preview ? 'http://127.0.0.1/mock-preview' : 'http://127.0.0.1/settings-test',
        ),
        instanceId: preview ? 'preview-fixtures' : 'settings-test',
        userId: preview ? 'preview-user' : 'account-a',
        audience: 'client',
        sessionRef: 'session-a',
      ),
    );
    return cache;
  }

  test('persistent invalidation waiting for its lock retains the same account snapshot', () async {
    final cache = await attachedCache(persistent: true);
    final source = MockSettingsSource();
    final initial = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 1,
      fields: const {'display_name': 'old'},
    );
    when(source.fetch(any, any)).thenAnswer((_) async => initial);
    when(source.patch(any, any)).thenAnswer(
      (_) async => SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 2,
        fields: const {'display_name': 'new'},
      ),
    );
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    await repository.refresh(SettingsGroup.profile);
    final release = Completer<void>();
    final locked = Completer<void>();
    final holding = withCachePartitionPublishLock(cache.scope!.partition, () async {
      locked.complete();
      await release.future;
    });
    await locked.future;
    final saving = repository.save(SettingsGroup.profile, {'display_name': 'new'});
    await Future<void>.delayed(Duration.zero);
    expect(repository.status(SettingsGroup.profile), SettingsReadStatus.refreshing);
    expect(repository.snapshot(SettingsGroup.profile), same(initial));
    release.complete();
    await holding;
    await saving;
    expect(repository.status(SettingsGroup.profile), SettingsReadStatus.ready);
  });

  test('confirmed profile/study/preferences PATCH retires only its revision group', () async {
    final cache = await attachedCache();
    final source = MockSettingsSource();
    final records = <SettingsGroup, SettingsSnapshot>{
      for (final group in SettingsGroup.values)
        group: SettingsSnapshot(group: group, revision: 1, fields: {'value': group.sourceId}),
    };
    final reads = <SettingsGroup, int>{};
    when(source.fetch(any, any)).thenAnswer((invocation) async {
      final group = invocation.positionalArguments.first as SettingsGroup;
      reads[group] = (reads[group] ?? 0) + 1;
      return records[group]!;
    });
    when(source.patch(any, any)).thenAnswer((invocation) async {
      final group = invocation.positionalArguments.first as SettingsGroup;
      final patch = invocation.positionalArguments[1] as SettingsPatch;
      expect(patch.expectedRevision, records[group]!.revision);
      records[group] = SettingsSnapshot(
        group: group,
        revision: patch.expectedRevision + 1,
        fields: patch.fields,
      );
      return records[group]!;
    });
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });

    for (final group in SettingsGroup.values) {
      await repository.refresh(group);
      expect(repository.status(group), SettingsReadStatus.ready);
    }
    for (final group in SettingsGroup.values) {
      final unaffected = SettingsGroup.values.where((candidate) => candidate != group);
      final before = {
        for (final candidate in unaffected) candidate: repository.snapshot(candidate),
      };
      final readBefore = {for (final candidate in unaffected) candidate: reads[candidate]};
      final generation = cache.invalidationGeneration;
      final committed = await repository.save(group, {'value': 'updated-${group.sourceId}'});
      expect(committed.revision, records[group]!.revision);
      expect(cache.invalidationGeneration, generation + 1);
      expect(cache.lastInvalidatedTags, {group.dependency});
      expect(repository.snapshot(group)?.fields['value'], 'updated-${group.sourceId}');
      for (final candidate in unaffected) {
        expect(repository.status(candidate), SettingsReadStatus.ready);
        expect(repository.snapshot(candidate), same(before[candidate]));
        expect(reads[candidate], readBefore[candidate]);
      }
    }
    final readsBeforeUnrelated = Map.of(reads);
    await cache.applyCommittedMutation({'notification:list'});
    for (final group in SettingsGroup.values) {
      expect(repository.status(group), SettingsReadStatus.ready);
      expect(reads[group], readsBeforeUnrelated[group]);
    }
  });

  test(
    'cross-tab hints reload settings automatically and own save never removes the snapshot',
    () async {
      final cache = await attachedCache();
      final source = MockSettingsSource();
      var record = SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {'display_name': 'old'},
      );
      var pending = Completer<SettingsSnapshot>();
      var reads = 0;
      when(source.fetch(any, any)).thenAnswer((_) {
        reads++;
        return reads == 1 ? Future.value(record) : pending.future;
      });
      when(source.patch(any, any)).thenAnswer((_) async => record);
      final repository = CachedSettingsRepository(cache: cache, source: source);
      addTearDown(() async {
        repository.dispose();
        await cache.closeScope();
      });
      await repository.refresh(SettingsGroup.profile);
      final generation = cache.accountGeneration;
      cache.handleExternalCacheHint('invalidate', {'settings:profile'});
      await Future<void>.delayed(Duration.zero);
      expect(cache.accountGeneration, generation);
      expect(reads, 2);
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.refreshing);
      expect(repository.snapshot(SettingsGroup.profile)?.fields['display_name'], 'old');
      record = SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 2,
        fields: {'display_name': 'remote'},
      );
      pending.complete(record);
      await Future<void>.delayed(Duration.zero);
      expect(repository.snapshot(SettingsGroup.profile)?.revision, 2);

      var lostSnapshot = false;
      repository.addListener(() {
        if (repository.snapshot(SettingsGroup.profile) == null) lostSnapshot = true;
      });
      pending = Completer<SettingsSnapshot>();
      record = SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 3,
        fields: {'display_name': 'saved'},
      );
      final saved = repository.save(SettingsGroup.profile, {'display_name': 'saved'});
      await Future<void>.delayed(Duration.zero);
      expect(repository.status(SettingsGroup.profile), SettingsReadStatus.refreshing);
      expect(lostSnapshot, isFalse);
      pending.complete(record);
      await saved;
      expect(lostSnapshot, isFalse);
      expect(repository.snapshot(SettingsGroup.profile)?.revision, 3);
    },
  );

  test('revision conflict preserves the accepted snapshot without invalidation', () async {
    final cache = await attachedCache();
    final source = MockSettingsSource();
    final record = SettingsSnapshot(
      group: SettingsGroup.studyProfile,
      revision: 4,
      fields: {'active_target_language': 'ja'},
    );
    when(source.fetch(any, any)).thenAnswer((_) async => record);
    when(source.patch(any, any)).thenThrow(const SettingsRevisionConflict());
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    await repository.refresh(SettingsGroup.studyProfile);
    final generation = cache.invalidationGeneration;
    await expectLater(
      repository.save(SettingsGroup.studyProfile, {'active_target_language': 'en'}),
      throwsA(isA<SettingsRevisionConflict>()),
    );
    expect(cache.invalidationGeneration, generation);
    expect(repository.snapshot(SettingsGroup.studyProfile), same(record));
    expect(repository.busy(SettingsGroup.studyProfile), isFalse);
  });

  test('a confirmed PATCH supersedes a slow older read and never revives it', () async {
    final cache = await attachedCache();
    final source = MockSettingsSource();
    final old = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 1,
      fields: {'display_name': 'old'},
    );
    final edited = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 2,
      fields: {'display_name': 'new'},
    );
    final started = Completer<void>();
    final slow = Completer<SettingsSnapshot>();
    var reads = 0;
    when(source.fetch(any, any)).thenAnswer((_) {
      reads++;
      if (reads == 2) {
        started.complete();
        return slow.future;
      }
      return Future.value(reads == 1 ? old : edited);
    });
    when(source.patch(any, any)).thenAnswer((invocation) async {
      final patch = invocation.positionalArguments[1] as SettingsPatch;
      expect(patch.expectedRevision, 1);
      return edited;
    });
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    await repository.refresh(SettingsGroup.profile);
    final oldRead = repository.refresh(SettingsGroup.profile, force: true);
    await started.future;
    final saved = await repository.save(SettingsGroup.profile, {'display_name': 'new'});
    expect(saved.revision, 2);
    expect(repository.snapshot(SettingsGroup.profile)?.fields['display_name'], 'new');
    slow.complete(old);
    await oldRead;
    expect(repository.snapshot(SettingsGroup.profile)?.revision, 2);
    expect(reads, 3);
  });

  test('scope switch hides a pending settings read from the next account', () async {
    final cache = await attachedCache();
    final source = MockSettingsSource();
    final started = Completer<void>();
    final slow = Completer<SettingsSnapshot>();
    when(source.fetch(any, any)).thenAnswer((_) {
      started.complete();
      return slow.future;
    });
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    final oldRead = repository.refresh(SettingsGroup.profile);
    await started.future;
    await cache.closeScope();
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/settings-test'),
        instanceId: 'settings-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    slow.complete(
      SettingsSnapshot(
        group: SettingsGroup.profile,
        revision: 1,
        fields: {'display_name': 'account-a'},
      ),
    );
    await oldRead;
    expect(repository.snapshot(SettingsGroup.profile), isNull);
    expect(repository.status(SettingsGroup.profile), SettingsReadStatus.blocked);
  });

  test('A draft waiting for readiness cannot become a B settings write', () async {
    final cache = await attachedCache();
    final source = MockSettingsSource();
    final waiting = Completer<void>();
    final repository = CachedSettingsRepository(
      cache: cache,
      source: source,
      waitForReadiness: () => waiting.future,
    );
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    final save = repository.save(SettingsGroup.profile, {'display_name': 'A draft'});
    await cache.closeScope();
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/settings-test'),
        instanceId: 'settings-test',
        userId: 'account-b',
        audience: 'client',
        sessionRef: 'session-b',
      ),
    );
    waiting.complete();
    await expectLater(save, throwsA(isA<CacheBlocked>()));
    verifyNever(source.patch(any, any));
  });

  test('confirmed PATCH stays committed when persistent invalidation fails', () async {
    final executor = NativeDatabase.memory();
    final cache = CacheCoordinator(
      openBackend: (_) async => OpenedCacheBackend(
        executor: executor,
        mode: CacheStorageMode.persistent,
        closeOwner: executor.close,
      ),
    );
    await cache.attach(
      CacheScope.confirmed(
        endpoint: Uri.parse('http://127.0.0.1/settings-persistent'),
        instanceId: 'settings-persistent',
        userId: 'account-a',
        audience: 'client',
        sessionRef: 'session-a',
      ),
    );
    final source = MockSettingsSource();
    final old = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 1,
      fields: {'display_name': 'old'},
    );
    final edited = SettingsSnapshot(
      group: SettingsGroup.profile,
      revision: 2,
      fields: {'display_name': 'new'},
    );
    final started = Completer<void>();
    final slow = Completer<SettingsSnapshot>();
    var reads = 0;
    when(source.fetch(any, any)).thenAnswer((_) {
      reads++;
      if (reads == 1) return Future.value(old);
      started.complete();
      return slow.future;
    });
    when(source.patch(any, any)).thenAnswer((_) async => edited);
    final repository = CachedSettingsRepository(cache: cache, source: source);
    addTearDown(() async {
      repository.dispose();
      await cache.closeScope();
    });
    await repository.refresh(SettingsGroup.profile);
    await executor.runCustom(
      'CREATE TRIGGER fail_settings_invalidation '
      'BEFORE INSERT ON cache_invalidations '
      "BEGIN SELECT RAISE(FAIL, 'invalidation failed'); END",
    );
    final save = repository.save(SettingsGroup.profile, {'display_name': 'new'});
    await started.future;
    expect(repository.snapshot(SettingsGroup.profile), isNull);
    expect(repository.status(SettingsGroup.profile), SettingsReadStatus.loading);
    slow.complete(edited);
    expect((await save).revision, 2);
    expect(repository.snapshot(SettingsGroup.profile)?.fields['display_name'], 'new');
    expect(cache.invalidationGeneration, 1);
    verify(source.patch(any, any)).called(1);
    expect(reads, 2);
  });

  test('preview source checks field masks and revision groups before changing store', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final cache = await attachedCache(preview: true);
    addTearDown(cache.closeScope);
    final source = FixtureSettingsSource(store, cache);
    final original = store.activeLanguage;
    await expectLater(
      source.patch(
        SettingsGroup.studyProfile,
        SettingsPatch(expectedRevision: 0, fields: {'active_target_language': 'en'}),
      ),
      throwsA(isA<SettingsRevisionConflict>()),
    );
    await expectLater(
      source.patch(
        SettingsGroup.studyProfile,
        SettingsPatch(expectedRevision: 1, fields: {'timezone': 'UTC'}),
      ),
      throwsArgumentError,
    );
    expect(store.activeLanguage, original);
    final study = await source.patch(
      SettingsGroup.studyProfile,
      SettingsPatch(expectedRevision: 1, fields: {'active_target_language': 'en'}),
    );
    expect(study.revision, 2);
    expect(store.activeLanguage, 'en');
    final targets = (study.fields['target_languages'] as List).cast<Map<String, Object?>>();
    expect(targets.any((row) => row['language_tag'] == 'en'), isTrue);
    expect(targets.any((row) => row['language_tag'] == 'ja'), isTrue);
    final profile = await source.fetch(SettingsGroup.profile, CancelToken());
    expect(profile.revision, 1);
    expect(profile.fields['gender_code'], 'unspecified');
  });

  test('a narrow PATCH does not commit unrelated form drafts', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final cache = await attachedCache(preview: true);
    addTearDown(cache.closeScope);
    final source = FixtureSettingsSource(store, cache);
    final originalExplanation = store.explanationLanguage;
    final originalFont = store.readingFont;
    final originalVoice = store.speechVoice;
    store.editSettingsDraft((draft) {
      draft.explanationLanguage = 'en';
      draft.readingFont = 'sans';
      draft.speechVoice = 'unsaved-voice';
    });
    await source.patch(
      SettingsGroup.studyProfile,
      SettingsPatch(expectedRevision: 1, fields: {'active_target_language': 'en'}),
    );
    await source.patch(
      SettingsGroup.preferences,
      SettingsPatch(expectedRevision: 1, fields: {'reading_theme': 'dark'}),
    );
    expect(store.explanationLanguage, originalExplanation);
    expect(store.readingFont, originalFont);
    expect(store.speechVoice, originalVoice);
    expect(store.settingsDraft.explanationLanguage, 'en');
    expect(store.settingsDraft.readingFont, 'sans');
    expect(store.settingsDraft.speechVoice, 'unsaved-voice');
  });

  test('invalid later field rejects the entire fixture PATCH before any write', () async {
    final store = PreviewFixtureStore();
    addTearDown(store.dispose);
    final cache = await attachedCache(preview: true);
    addTearDown(cache.closeScope);
    final source = FixtureSettingsSource(store, cache);
    final before = await source.fetch(SettingsGroup.preferences, CancelToken());
    await expectLater(
      source.patch(
        SettingsGroup.preferences,
        SettingsPatch(
          expectedRevision: 1,
          fields: {'reading_theme': 'dark', 'playback_speed': 'not-a-double'},
        ),
      ),
      throwsA(isA<TypeError>()),
    );
    final after = await source.fetch(SettingsGroup.preferences, CancelToken());
    expect(after.revision, before.revision);
    expect(after.fields['reading_theme'], before.fields['reading_theme']);
    expect(store.settingsDraft.readingTheme, before.fields['reading_theme']);
  });

  test(
    'same-scope revision merges clean fields and blocks conflicting edits until reload',
    () async {
      final store = PreviewFixtureStore();
      addTearDown(store.dispose);
      final cache = await attachedCache();
      final source = MockSettingsSource();
      var record = SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 1,
        fields: {'reading_font_family': 'serif', 'reading_theme': 'light'},
      );
      when(source.fetch(any, any)).thenAnswer((_) async => record);
      final repository = CachedSettingsRepository(cache: cache, source: source);
      addTearDown(() async {
        repository.dispose();
        await cache.closeScope();
      });
      await repository.refresh(SettingsGroup.preferences);
      hydrateSettingsFormDraft(store, repository, SettingsGroup.preferences);
      expect(store.settingsDraft.ttsModel, 'gemini');
      expect(store.settingsDraft.speechVoice, 'japaneseClear');
      expect(store.settingsDraft.speechFormat, 'wav');
      expect(store.settingsDraft.readingTheme, 'light');
      store.editSettingsDraft((draft) => draft.readingTheme = 'dark');

      record = SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 2,
        fields: {'reading_font_family': 'sans', 'reading_theme': 'sepia'},
      );
      await cache.applyCommittedMutation({SettingsGroup.preferences.dependency});
      await repository.refresh(SettingsGroup.preferences, force: true);
      hydrateSettingsFormDraft(store, repository, SettingsGroup.preferences);
      expect(store.settingsDraft.readingFont, 'sans');
      expect(store.settingsDraft.readingTheme, 'dark');
      expect(settingsFormDraftHasConflict(store, SettingsGroup.preferences), isTrue);
      record = SettingsSnapshot(
        group: SettingsGroup.preferences,
        revision: 3,
        fields: {
          'reading_font_family': 'sans',
          'reading_theme': 'sepia',
          'query_context_budget_tokens': 20000,
        },
      );
      await cache.applyCommittedMutation({SettingsGroup.preferences.dependency});
      await repository.refresh(SettingsGroup.preferences, force: true);
      hydrateSettingsFormDraft(store, repository, SettingsGroup.preferences);
      expect(store.settingsDraft.queryContextBudget, 20000);
      expect(settingsFormDraftHasConflict(store, SettingsGroup.preferences), isTrue);
      resetSettingsFormDraft(store, SettingsGroup.preferences);
      hydrateSettingsFormDraft(store, repository, SettingsGroup.preferences);
      expect(store.settingsDraft.readingTheme, 'sepia');
      expect(settingsFormDraftHasConflict(store, SettingsGroup.preferences), isFalse);
    },
  );
}

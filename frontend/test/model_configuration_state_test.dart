import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/features/settings/presentation/model_configuration_content.dart';
import 'package:haruka/features/settings/presentation/model_configuration_scope.dart';
import 'package:haruka/features/settings/presentation/model_usage_content.dart';
import 'package:haruka/core/api/model_settings_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/features/jobs/data/job_socket.dart';
import 'package:haruka/features/settings/data/model_configuration_repository.dart';
import 'package:haruka/features/settings/domain/model_configuration_controller.dart';
import 'package:haruka/shared/presentation/components.dart';

const credentialId = '018f1234-1234-7123-8123-123456789abc';
const jobId = '018f1234-1234-7123-8123-123456789abd';
const runId = '018f1234-1234-7123-8123-123456789abe';
Map<String, Object?> jobData({int sequence = 1, String state = 'running'}) => {
  'id': jobId,
  'run_id': runId,
  'credential_id': credentialId,
  'state': state,
  'revision': sequence,
  'generation': 1,
  'sequence': sequence,
  'can_cancel': state == 'running',
  'can_retry': state == 'failed',
  'requires_new_attempt_confirmation': state == 'failed',
};
ProviderCredential credential() => ProviderCredential.fromJson({
  'id': credentialId,
  'provider': 'openrouter',
  'label': 'Fixture',
  'masked_key': '••••test',
  'revision': 1,
  'credential_version': 1,
  'status': 'active',
});
ModelDirectory fixtureDirectory() => ModelDirectory.fromJson({
  'revision': 1,
  'default_provider': 'openrouter',
  'models': <Object?>[],
  'voices': <Object?>[],
  'limits': {
    'revision': 1,
    'enabled': true,
    'max_credentials': 10,
    'max_concurrent_jobs': 1,
    'instance_concurrent_jobs': 4,
    'max_model_calls': 1,
    'max_output_tokens': 128,
    'timeout_seconds': 60,
    'tts_timeout_seconds': 90,
    'max_test_image_bytes': 4096,
    'max_tts_characters': 32,
    'websocket_max_jobs': 100,
  },
});

final class MemorySocket implements JobSocket {
  final input = StreamController<String>();
  final sent = <String>[];
  bool closed = false;
  @override
  Stream<String> get messages => input.stream;
  @override
  void send(String message) => sent.add(message);
  @override
  Future<void> close() async {
    closed = true;
    await input.close();
  }
}

final class FixtureRepository implements ModelConfigurationRepository {
  int reads = 0, jobReads = 0, connections = 0, tests = 0;
  int usageReads = 0;
  Completer<List<ProviderCredential>>? pending;
  final sockets = [MemorySocket()];
  MemorySocket get socket => sockets.last;
  int individualJobReads = 0;
  Completer<ModelJob>? pendingJob;
  List<ModelJob>? jobsOverride;
  @override
  Future<List<ProviderCredential>> credentials() async {
    reads++;
    return pending?.future ?? [credential()];
  }

  @override
  Future<ModelDirectory> directory() async => directoryFixture;
  final directoryFixture = fixtureDirectory();
  @override
  Future<PersonalModelSettings> settings() async => PersonalModelSettings.fromJson({
    'revision': 1,
    'bindings': {'text': null, 'vision': null, 'tts': null},
  });
  @override
  Future<List<ModelJob>> jobs() async {
    jobReads++;
    return jobsOverride ?? [ModelJob.fromJson(jobData())];
  }

  @override
  Future<JobSocket> connect() async {
    if (connections > 0) sockets.add(MemorySocket());
    connections++;
    return socket;
  }

  @override
  Future<ModelJob> job(String id) async {
    individualJobReads++;
    return pendingJob?.future ?? ModelJob.fromJson(jobData(sequence: 2));
  }

  @override
  Future<ModelUsage> usage(Map<String, String> filters) async {
    usageReads++;
    return ModelUsage.fromJson({
      'as_of': '2026-09-30T00:00:00Z',
      'aggregation_revision': 1,
      'groups': <Object?>[],
    });
  }

  @override
  Future<AcceptedModelTest> test(
    ProviderCredential credential,
    String capability,
    ModelBinding binding,
    String idempotencyKey,
  ) async {
    tests++;
    throw const ApiFailure(code: 'TRANSPORT_ERROR', retryableTransport: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'source jobs preserve nullable model refs and accept only newer material progress',
    () async {
      Map<String, Object?> source({int sequence = 1, String state = 'running'}) => {
        ...jobData(sequence: sequence, state: state),
        'operation_kind': 'material_import',
        'run_id': null,
        'credential_id': null,
        'material_id': credentialId,
        'material_revision_id': runId,
        'source_status': 'parsing',
        'requires_new_attempt_confirmation': false,
        'progress_percent': state == 'succeeded' ? 100 : 50,
      };
      final repository = FixtureRepository()..jobsOverride = [ModelJob.fromJson(source())];
      final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
      addTearDown(controller.dispose);
      await controller.ensureJobs();
      await Future<void>.delayed(Duration.zero);
      expect(controller.jobs[jobId]!.sourceImport, isTrue);
      expect(controller.jobs[jobId]!.runId, isNull);
      expect(controller.jobs[jobId]!.credentialId, isNull);
      void event(int sequence, String state) => repository.socket.input.add(
        jsonEncode({
          'schema_version': 1,
          'job_id': jobId,
          'generation': 1,
          'sequence': sequence,
          'type': 'progress',
          'payload': source(sequence: sequence, state: state),
        }),
      );
      repository.pendingJob = Completer<ModelJob>()
        ..complete(ModelJob.fromJson(source(sequence: 3, state: 'succeeded')));
      event(3, 'succeeded');
      await Future<void>.delayed(Duration.zero);
      event(2, 'running');
      await Future<void>.delayed(Duration.zero);
      expect(controller.jobs[jobId]!.state, 'succeeded');
      expect(repository.individualJobReads, 1);
      expect(controller.jobs[jobId]!.sourceStatus, 'parsing');
      expect(controller.results, isEmpty);
      expect(controller.jobsErrorCode, isNull); // Any provider-result access would fail this fake.
      expect(repository.tests, 0);
      expect(() => ModelJob.fromJson({...source(), 'run_id': runId}), throwsFormatException);
    },
  );
  testWidgets('simulated results and usage never imply real provider success', (tester) async {
    Map<String, Object?> group(bool simulated, int count) => {
      'provider': 'openrouter',
      'model_id': 'fixture/model',
      'capability': 'text',
      'operation_kind': 'credential.test',
      'simulated': simulated,
      'attempt_count': count,
      'started_count': 0,
      'succeeded_count': simulated ? count : 0,
      'failed_count': simulated ? 0 : count,
      'unknown_count': 0,
      'metrics': <String, Object?>{},
    };
    final usage = ModelUsage.fromJson({
      'as_of': '2026-09-30T00:00:00Z',
      'aggregation_revision': 1,
      'groups': [group(true, 4), group(false, 1)],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: ModelUsageSummary(usage: usage)),
        ),
      ),
    );
    final real = find
        .ancestor(of: find.text('真实供应商调用'), matching: find.byType(HarukaSurface))
        .first;
    final simulated = find
        .ancestor(of: find.text('模拟测试'), matching: find.byType(HarukaSurface))
        .first;
    expect(find.descendant(of: real, matching: find.text('1')), findsNWidgets(2));
    expect(find.descendant(of: real, matching: find.text('4')), findsNothing);
    expect(find.descendant(of: simulated, matching: find.text('4')), findsNWidgets(2));
    expect(find.text('5'), findsNothing);
    final controller = ModelConfigurationController(
      repository: FixtureRepository(),
      allows: (_) => true,
    );
    controller.jobs[jobId] = ModelJob.fromJson(jobData(state: 'succeeded'));
    controller.results[runId] = CredentialTestResult.fromJson({
      'run_id': runId,
      'job_id': jobId,
      'credential_id': credentialId,
      'credential_version': 1,
      'provider': 'openrouter',
      'model_id': 'fixture/model',
      'capability': 'text',
      'state': 'succeeded',
      'usage': {
        'as_of': '2026-09-30T00:00:00Z',
        'aggregation_revision': 1,
        'groups': [group(true, 1)],
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: HarukaTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: ModelJobCards(controller: controller)),
        ),
      ),
    );
    expect(find.text('模拟能力测试 · 已完成'), findsOneWidget);
    expect(find.text('模拟测试结果；模拟执行不证明真实供应商能力已验证。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('job result only claims an old credential when a current version is known', (
    tester,
  ) async {
    final controller = ModelConfigurationController(
      repository: FixtureRepository(),
      allows: (_) => true,
    );
    controller.jobs[jobId] = ModelJob.fromJson(jobData(state: 'succeeded'));
    controller.results[runId] = CredentialTestResult.fromJson({
      'run_id': runId,
      'job_id': jobId,
      'credential_id': credentialId,
      'credential_version': 1,
      'provider': 'openrouter',
      'model_id': 'fixture/model',
      'capability': 'text',
      'state': 'succeeded',
      'usage': {'as_of': '2026-09-30T00:00:00Z', 'aggregation_revision': 1, 'groups': <Object?>[]},
    });
    Widget app() => MaterialApp(
      theme: HarukaTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: ModelJobCards(controller: controller)),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.text('这是旧凭据版本的历史结果。'), findsNothing);
    controller.credentials = [
      ProviderCredential.fromJson({
        'id': credentialId,
        'provider': 'openrouter',
        'label': 'Fixture',
        'masked_key': '••••test',
        'revision': 2,
        'credential_version': 2,
        'status': 'active',
      }),
    ];
    await tester.pumpWidget(app());
    expect(find.text('这是旧凭据版本的历史结果。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('socket opened before late authorization rejection is closed', () async {
    final socket = MemorySocket();
    final subscription = socket.messages.listen((_) {});
    final rejection = StateError('account generation changed');
    await expectLater(
      authorizedJobSocket((open) async {
        await open({});
        throw rejection;
      }, (_) async => socket),
      throwsA(same(rejection)),
    );
    expect(socket.closed, isTrue);
    await subscription.cancel();
  });

  testWidgets('usage draft survives compact/wide replacement without another read', (tester) async {
    final repository = FixtureRepository();
    final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
    Widget app(bool wide) => MaterialApp(
      theme: HarukaTheme.light(),
      home: ModelConfigurationScope(
        controller: controller,
        child: Scaffold(
          body: SingleChildScrollView(
            child: ModelUsageContent(key: ValueKey(wide), wide: wide),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey(UiTestIds.modelUsageModelFilter));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'google/draft');
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.usageReads, 1);
    expect(controller.usageModelDraft, 'google/draft');
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    );
    expect(input.controller!.text, 'google/draft');
    expect(repository.usageReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('credential dialog cancellation preserves background and reads at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FixtureRepository();
      final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          theme: HarukaTheme.light(),
          home: ModelConfigurationScope(
            controller: controller,
            child: Scaffold(
              body: SingleChildScrollView(
                controller: scroll,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ModelConfigurationContent(wide: size.width > 800),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = scroll.offset;
      final content = tester.element(find.byType(ModelConfigurationContent));
      await tester.tap(find.byKey(const ValueKey(UiTestIds.modelCredentialAdd)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey(UiTestIds.modelCredentialKey)),
        'fixture-only-key',
      );
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(repository.reads, 1);
      expect(scroll.offset, before);
      expect(tester.element(find.byType(ModelConfigurationContent)), same(content));
      expect(repository.tests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      scroll.dispose();
    });
  }
  test('configuration reads coalesce and cached re-entry preserves draft', () async {
    final repository = FixtureRepository();
    final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
    await Future.wait([controller.ensureConfiguration(), controller.ensureConfiguration()]);
    const binding = ModelBinding(
      credentialId: credentialId,
      provider: 'openrouter',
      modelId: 'fixture-model',
    );
    controller.editBinding('text', binding);
    await controller.ensureConfiguration();
    expect(repository.reads, 1);
    expect(controller.bindings['text'], same(binding));
    expect(controller.dirty, true);
    controller.dispose();
  });
  test('account generation rejects a configuration response after reset', () async {
    final repository = FixtureRepository()..pending = Completer();
    final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
    final request = controller.ensureConfiguration();
    controller.reset();
    repository.pending!.complete([credential()]);
    await request;
    expect(controller.credentials, isNull);
    expect(controller.directory, isNull);
    controller.dispose();
  });
  test('job reads and socket are unique; duplicate and older events cannot regress', () async {
    final repository = FixtureRepository();
    final controller = ModelConfigurationController(
      repository: repository,
      allows: (permission) => permission != 'client.credential.read',
    );
    await Future.wait([controller.ensureJobs(), controller.ensureJobs()]);
    await Future<void>.delayed(Duration.zero);
    await controller.ensureJobs();
    expect(repository.jobReads, 1);
    expect(repository.connections, 1);
    void emit(int sequence) => repository.socket.input.add(
      jsonEncode({
        'schema_version': 1,
        'type': 'progress',
        'job_id': jobId,
        'generation': 1,
        'sequence': sequence,
        'payload': jobData(sequence: sequence),
      }),
    );
    emit(2);
    emit(2);
    emit(1);
    await Future<void>.delayed(Duration.zero);
    expect(controller.jobs[jobId]!.sequence, 2);
    expect(repository.tests, 0);
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(repository.socket.closed, true);
  });
  test(
    'disconnect restores persisted job snapshot and one subscription without another POST',
    () async {
      final repository = FixtureRepository();
      final controller = ModelConfigurationController(
        repository: repository,
        allows: (permission) => permission != 'client.credential.read',
      );
      await controller.ensureJobs();
      await Future<void>.delayed(Duration.zero);
      final original = repository.socket;
      await original.close();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(original.closed, true);
      expect(repository.connections, 2);
      expect(repository.individualJobReads, 1);
      expect(controller.jobs[jobId]!.sequence, 2);
      expect(repository.socket.sent, hasLength(1));
      final subscription = jsonDecode(repository.socket.sent.single) as Map<String, dynamic>;
      expect(subscription['job_ids'], [jobId]);
      expect(repository.tests, 0);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('account generation drops a late job snapshot after reset', () async {
    final repository = FixtureRepository();
    final controller = ModelConfigurationController(
      repository: repository,
      allows: (permission) => permission != 'client.credential.read',
    );
    await controller.ensureJobs();
    repository.pendingJob = Completer<ModelJob>();
    final pending = controller.refreshJob(jobId);
    controller.reset();
    repository.pendingJob!.complete(ModelJob.fromJson(jobData(sequence: 2)));
    await pending;
    expect(controller.jobs, isEmpty);
    expect(controller.results, isEmpty);
    expect(repository.tests, 0);
    controller.dispose();
  });
  test('unknown acceptance blocks another provider POST and never auto retries', () async {
    final repository = FixtureRepository();
    final controller = ModelConfigurationController(repository: repository, allows: (_) => true);
    await controller.ensureConfiguration();
    const binding = ModelBinding(
      credentialId: credentialId,
      provider: 'openrouter',
      modelId: 'fixture-model',
    );
    await expectLater(controller.submitTest('text', binding), throwsA(isA<ApiFailure>()));
    await controller.submitTest('text', binding);
    expect(repository.tests, 1);
    expect(controller.testOutcomeUncertain, true);
    controller.dispose();
  });
  test('unknown usage stays null while partial known sums remain explicit', () {
    final unknown = UsageMetric.fromJson({
      'known_sum': null,
      'known_attempt_count': 0,
      'unknown_attempt_count': 1,
      'completeness': 'unavailable',
    });
    final partial = UsageMetric.fromJson({
      'known_sum': 7,
      'known_attempt_count': 1,
      'unknown_attempt_count': 1,
      'completeness': 'partial',
    });
    expect(unknown.knownSum, isNull);
    expect(unknown.display, '未提供');
    expect(partial.display, '7（部分）');
  });
}

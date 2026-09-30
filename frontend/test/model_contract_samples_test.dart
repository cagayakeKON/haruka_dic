import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/features/settings/presentation/model_usage_content.dart';
import 'package:haruka/core/api/model_settings_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';

void main() {
  final samples = wireObject(
    jsonDecode(File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync()),
  );
  test('model settings concrete projection preserves unbound capabilities', () {
    final settings = SuccessResponse<PersonalModelSettings>.fromJson(
      samples['model_settings'],
      PersonalModelSettings.fromJson,
    ).data;
    expect(settings.revision, 2);
    expect(settings.bindings.keys, containsAll(['text', 'vision', 'tts']));
    expect(settings.bindings.values, everyElement(isNull));
  });
  test('catalog voices limits and masked credential decode backend samples', () {
    final directory = SuccessResponse<ModelDirectory>.fromJson(
      samples['model_capabilities'],
      ModelDirectory.fromJson,
    ).data;
    final credential = SuccessResponse<ProviderCredential>.fromJson(
      samples['model_credential'],
      ProviderCredential.fromJson,
    ).data;
    expect(directory.models.single.modelId, 'google/gemini-3.8-flash-lite-tts');
    expect(directory.models.single.verified, false);
    expect(directory.voices.single.voiceId, 'Kore');
    expect(directory.voices.single.formats, ['mp3']);
    expect(directory.limits.values['max_model_calls'], 1);
    expect(credential.provider, 'openrouter');
    expect(credential.maskedKey, isNotEmpty);
  });
  test('job and full event snapshots retain generation sequence and explicit retry gate', () {
    final job = SuccessResponse<ModelJob>.fromJson(samples['model_job'], ModelJob.fromJson).data;
    final event = ModelJobEvent.fromJson(samples['model_job_event']);
    expect(event.payload.id, job.id);
    expect(event.payload.generation, job.generation);
    expect(event.payload.sequence, job.sequence);
    expect(job.state, 'blocked');
    expect(job.requiresConfirmation, true);
    expect(job.terminal, true);
    expect(
      () => ModelJobEvent.fromJson({...wireObject(samples['model_job_event']), 'sequence': 99}),
      throwsFormatException,
    );
  });
  test('result unknown outcome and usage unknown null never become zero or success', () {
    final result = SuccessResponse<CredentialTestResult>.fromJson(
      samples['model_test_result'],
      CredentialTestResult.fromJson,
    ).data;
    final usage = SuccessResponse<ModelUsage>.fromJson(
      samples['model_usage_unknown'],
      ModelUsage.fromJson,
    ).data;
    expect(result.state, 'unknown_outcome');
    expect(result.errorCode, 'EXTERNAL_RESULT_UNKNOWN');
    expect(usage.aggregationRevision, 1);
    final metric = usage.groups.single.metrics['input_tokens']!;
    expect(usage.groups.single.simulated, false);
    final group = wireObject(wireObject(samples['model_usage_unknown'])['data']);
    final originalGroup = wireObject((group['groups'] as List).single);
    expect(UsageGroup.fromJson({...originalGroup, 'simulated': true}).simulated, true);
    final missing = Map<String, dynamic>.of(originalGroup)..remove('simulated');
    expect(() => UsageGroup.fromJson(missing), throwsFormatException);
    expect(metric.knownSum, isNull);
    expect(metric.display, '未提供');
    expect(metric.unknownAttempts, 1);
    expect(result.usage.groups.single.metrics['input_tokens']!.knownSum, isNull);
  });
  for (final entry in {
    'model_usage_mixed_100': '100（部分） · 已知 1 次 / 未知 1 次',
    'model_usage_mixed_zero': '0（部分） · 已知 1 次 / 未知 1 次',
    'model_usage_all_unknown': '未提供 · 已知 0 次 / 未知 2 次',
    'model_usage_started': '未提供 · 已知 0 次 / 未知 1 次',
  }.entries) {
    testWidgets('USAGE09 backend ${entry.key} renders known unknown and started counts', (
      tester,
    ) async {
      final usage = SuccessResponse<ModelUsage>.fromJson(
        samples[entry.key],
        ModelUsage.fromJson,
      ).data;
      final group = usage.groups.single;
      expect(group.simulated, false);
      expect(group.started, entry.key == 'model_usage_started' ? 1 : 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: HarukaTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: ModelUsageSummary(usage: usage)),
          ),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.textContaining('调用 ${group.attempts} · 进行中 ${group.started}'), findsOneWidget);
      expect(find.text('模拟测试'), findsNothing);
      if (entry.key == 'model_usage_all_unknown' || entry.key == 'model_usage_started') {
        expect(group.metrics['input_tokens']!.knownSum, isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

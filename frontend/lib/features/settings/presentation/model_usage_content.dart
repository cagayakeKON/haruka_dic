import 'dart:async';

import 'package:flutter/material.dart';

import '../../../generated/ui_test_ids.dart';
import '../../../shared/identified.dart';

import '../../../core/api/model_settings_models.dart';
import '../../../shared/presentation/components.dart';
import '../domain/model_configuration_controller.dart';
import 'model_configuration_scope.dart';
import 'model_configuration_content.dart';

const usageMetricLabels = {
  'input_tokens': '输入 Token',
  'output_tokens': '输出 Token',
  'total_tokens': '总 Token',
  'cache_read_tokens': '缓存读取 Token',
  'cache_write_tokens': '缓存写入 Token',
  'reasoning_tokens': '推理 Token',
  'audio_input_tokens': '音频输入 Token',
  'audio_output_tokens': '音频输出 Token',
  'input_audio_tokens': '音频输入 Token',
  'output_audio_tokens': '音频输出 Token',
  'input_images': '输入图片数',
  'audio_tokens': '音频 Token',
  'input_characters': '输入字符',
  'output_characters': '输出字符',
  'audio_seconds': '音频秒数',
  'characters': '字符数',
};

class UsageMetricRows extends StatelessWidget {
  const UsageMetricRows({required this.group, super.key});
  final UsageGroup group;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(group.simulated ? '模拟用量（非真实供应商）' : '真实供应商用量'),
      for (final entry in group.metrics.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            '${usageMetricLabels[entry.key] ?? entry.key}：${entry.value.display} · 已知 ${entry.value.knownAttempts} 次 / 未知 ${entry.value.unknownAttempts} 次',
          ),
        ),
    ],
  );
}

class ModelUsageContent extends StatefulWidget {
  const ModelUsageContent({this.wide = false, super.key});
  final bool wide;
  @override
  State<ModelUsageContent> createState() => _ModelUsageContentState();
}

class _ModelUsageContentState extends State<ModelUsageContent> {
  ModelConfigurationController? _controller;
  final _model = TextEditingController();
  int _days = 30;
  String? _provider, _capability, _operation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModelConfigurationScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller = next;
    if (next != null) {
      _model.text = next.usageModelDraft;
      _provider = next.usageProviderDraft;
      _capability = next.usageCapabilityDraft;
      _operation = next.usageOperationDraft;
      _days = next.usageDaysDraft;
      scheduleMicrotask(() => unawaited(next.ensureUsage()));
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _filter() {
    final c = _controller;
    if (c == null) return;
    unawaited(
      c.ensureUsage(
        filters: {
          'since': DateTime.now().toUtc().subtract(Duration(days: _days)).toIso8601String(),
          'provider': ?_provider,
          'capability': ?_capability,
          'operation_kind': ?_operation,
          if (_model.text.trim().isNotEmpty) 'model_id': _model.text.trim(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HarukaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('模型用量', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 天')),
                    ButtonSegment(value: 30, label: Text('30 天')),
                    ButtonSegment(value: 90, label: Text('90 天')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (value) {
                    c.usageDaysDraft = value.first;
                    setState(() => _days = value.first);
                    _filter();
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: widget.wide ? 190 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _provider,
                        decoration: const InputDecoration(labelText: '供应商'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('全部')),
                          DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                          DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                        ],
                        onChanged: (v) => setState(() {
                          c.usageProviderDraft = v;
                          _provider = v;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: widget.wide ? 160 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _capability,
                        decoration: const InputDecoration(labelText: '能力'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('全部')),
                          for (final value in const ['text', 'vision', 'tts'])
                            DropdownMenuItem(value: value, child: Text(capabilityTitle(value))),
                        ],
                        onChanged: (v) => setState(() {
                          c.usageCapabilityDraft = v;
                          _capability = v;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: widget.wide ? 190 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _operation,
                        decoration: const InputDecoration(labelText: '操作类型'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('全部')),
                          DropdownMenuItem(value: 'credential_test', child: Text('凭据能力测试')),
                        ],
                        onChanged: (v) => setState(() {
                          c.usageOperationDraft = v;
                          _operation = v;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Identified(
                  id: UiTestIds.modelUsageModelFilter,
                  child: TextField(
                    controller: _model,
                    onChanged: (value) => c.usageModelDraft = value,
                    decoration: const InputDecoration(labelText: '模型 ID（可选）'),
                    onSubmitted: (_) => _filter(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Identified(
                    id: UiTestIds.modelUsageApply,
                    child: OutlinedButton(onPressed: _filter, child: const Text('应用筛选')),
                  ),
                ),
                if (c.usageLoading) const LinearProgressIndicator(),
                if (c.usageErrorCode != null)
                  Text(
                    modelErrorTitle(c.usageErrorCode),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (c.usage != null) ModelUsageSummary(usage: c.usage!, wide: widget.wide),
        ],
      ),
    );
  }
}

class ModelUsageSummary extends StatelessWidget {
  const ModelUsageSummary({required this.usage, this.wide = false, super.key});
  final ModelUsage usage;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ],
    );
    Widget summary(bool simulated) {
      final groups = usage.groups.where((group) => group.simulated == simulated);
      return HarukaSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(simulated ? '模拟测试' : '真实供应商调用', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                stat(
                  simulated ? '模拟执行' : '供应商调用',
                  groups.fold<int>(0, (sum, g) => sum + g.attempts),
                ),
                stat('成功', groups.fold<int>(0, (sum, g) => sum + g.succeeded)),
                stat('进行中', groups.fold<int>(0, (sum, g) => sum + g.started)),
                stat('失败', groups.fold<int>(0, (sum, g) => sum + g.failed)),
                stat('结果待核对', groups.fold<int>(0, (sum, g) => sum + g.unknown)),
              ],
            ),
            const SizedBox(height: 12),
            Text('统计时间：${usage.asOf.toLocal()}'),
            Text(
              simulated
                  ? '模拟执行未调用真实供应商，不计入真实调用合计。'
                  : '以真实供应商 attempt 计数；未提供的用量显示为未知。应用成果复用不计作模型调用。',
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary(false),
        if (usage.groups.any((group) => group.simulated)) ...[
          const SizedBox(height: 16),
          summary(true),
        ],
        if (usage.groups.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('此范围内暂无模型调用。')),
        for (final group in usage.groups) ...[
          const SizedBox(height: 16),
          HarukaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${group.simulated ? '模拟 · ' : ''}${capabilityTitle(group.capability)} · ${group.provider}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(group.modelId),
                Text('操作：${group.operationKind}'),
                Text(
                  '调用 ${group.attempts} · 进行中 ${group.started} · 成功 ${group.succeeded} · 失败 ${group.failed} · 未知 ${group.unknown}',
                ),
                const Divider(),
                UsageMetricRows(group: group),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

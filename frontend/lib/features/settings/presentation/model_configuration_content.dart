import 'dart:async';

import 'package:flutter/material.dart';

import '../../../generated/ui_test_ids.dart';
import '../../../shared/identified.dart';

import '../../../core/api/model_settings_models.dart';
import '../../../core/api/responses.dart';
import '../../../shared/presentation/components.dart';
import '../../../app/motion.dart';
import '../domain/model_configuration_controller.dart';
import 'model_configuration_scope.dart';
import 'model_usage_content.dart';

String capabilityTitle(String value) => switch (value) {
  'text' => '文本',
  'vision' => '视觉',
  'tts' => '朗读',
  _ => value,
};
String modelStateTitle(String value) => switch (value) {
  'accepted' || 'queued' => '已受理',
  'running' => '进行中',
  'succeeded' || 'completed' => '已完成',
  'failed' => '失败',
  'cancelled' => '已取消',
  'unknown' || 'unknown_outcome' => '结果待核对',
  'blocked' => '已暂停，需确认后续动作',
  'superseded' => '配置已变更',
  _ => value,
};
String modelErrorTitle(String? code) => switch (code) {
  'REAUTHENTICATION_REQUIRED' => '为保护个人 Key，请重新登录后再操作。',
  'REVISION_CONFLICT' => '配置已在其他位置更新。草稿已保留，请重新读取后核对再保存。',
  'TEST_ACCEPTANCE_UNKNOWN' => '受理结果暂未确认。请查看已有任务，不要重复测试。',
  'EXTERNAL_RESULT_UNKNOWN' => '供应商结果未知；不会自动再次调用。新调用必须显式确认。',
  'PERMISSION_DENIED' => '当前账号没有此操作权限。',
  'CREDENTIAL_REQUIRED' => '请先配置本人 Key。',
  'RATE_LIMITED' => '当前调用受限，请稍后再试。',
  null => '',
  _ => '操作未完成（$code）。',
};

class ModelConfigurationContent extends StatefulWidget {
  const ModelConfigurationContent({this.wide = false, super.key});
  final bool wide;
  @override
  State<ModelConfigurationContent> createState() => _ModelConfigurationContentState();
}

class _ModelConfigurationContentState extends State<ModelConfigurationContent> {
  ModelConfigurationController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModelConfigurationScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller = next;
    if (next != null) scheduleMicrotask(() => unawaited(next.ensureConfiguration()));
  }

  Widget _card(String title, List<Widget> children) => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final credential = c.selectedCredential;
        final providers = _card('供应商', [
          DropdownButtonFormField<String>(
            initialValue: c.provider,
            decoration: const InputDecoration(labelText: '供应商'),
            items: const [
              DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini 直连')),
            ],
            onChanged: c.submitting
                ? null
                : (value) {
                    if (value != null) c.selectProvider(value);
                  },
          ),
          const SizedBox(height: 14),
          if (c.credentials == null && c.loading) const LinearProgressIndicator(),
          if (c.credentials != null)
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('credential:${c.selectedCredentialId}'),
              initialValue: credential?.id,
              decoration: const InputDecoration(labelText: '本人凭据'),
              items: [
                for (final item in c.credentials!)
                  if (item.provider == c.provider && item.status == 'active')
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${item.label} · ${item.maskedKey}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: c.submitting ? null : c.selectCredential,
            ),
          const SizedBox(height: 10),
          Text(credential == null ? '未配置' : '已保存 · 能力请单独测试'),
          if (c.provider == 'gemini') const Text('Gemini 直连尚未进行真实协议验证。'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (c.allows('client.credential.manage'))
                Identified(
                  id: UiTestIds.modelCredentialAdd,
                  child: OutlinedButton(
                    onPressed: c.submitting ? null : () => _keyDialog(c),
                    child: const Text('配置 API Key'),
                  ),
                ),
              if (credential != null && c.allows('client.credential.manage')) ...[
                TextButton(
                  onPressed: c.submitting ? null : () => _keyDialog(c, previous: credential),
                  child: const Text('轮换 Key'),
                ),
                TextButton(
                  onPressed: c.submitting ? null : () => _delete(c, credential),
                  child: const Text('移除 API Key'),
                ),
              ],
            ],
          ),
        ]);
        final capabilityWidgets = [
          for (final capability in const ['text', 'vision', 'tts']) _bindingCard(c, capability),
        ];
        final model = _card('个人模型', [
          if (widget.wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < capabilityWidgets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: capabilityWidgets[i]),
                ],
              ],
            )
          else ...[
            for (final item in capabilityWidgets) ...[item, const SizedBox(height: 10)],
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (c.allows('client.profile.update'))
                Identified(
                  id: UiTestIds.modelBindingsSave,
                  child: FilledButton(
                    onPressed: c.submitting || c.settings == null || !c.dirty
                        ? null
                        : () => _save(c),
                    child: Text(c.submitting ? '处理中…' : '保存模型偏好'),
                  ),
                ),
              if (c.allows('client.credential.test'))
                Identified(
                  id: UiTestIds.modelTestOpen,
                  child: OutlinedButton(
                    onPressed: c.canTest && !c.testOutcomeUncertain ? () => _testDialog(c) : null,
                    child: const Text('测试模型能力'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.dirty ? '有未保存的模型偏好。保存不会调用供应商。' : '保存与测试为独立操作。'),
          if (c.settings == null && !c.allows('client.profile.read'))
            const Text('当前账号可管理或测试凭据，模型偏好不可读取。'),
        ]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.errorCode != null) ...[
              _error(c.errorCode!, () => c.ensureConfiguration(refresh: true)),
              const SizedBox(height: 14),
            ],
            providers,
            const SizedBox(height: 16),
            model,
            if (c.accepted != null) ...[
              const SizedBox(height: 16),
              _card('本次测试', [
                Text('已持久受理 · ${c.accepted!.jobId}'),
                const SizedBox(height: 8),
                if (!c.allows('client.job.read')) const Text('当前账号不能订阅任务进度，可按已受理引用读取测试结果。'),
                if (!c.allows('client.job.read')) ...[
                  TextButton(onPressed: c.readAcceptedResult, child: const Text('读取本次结果')),
                  if (c.results[c.accepted!.runId] case final result?) ...[
                    Text(
                      '${capabilityTitle(result.capability)} · ${modelStateTitle(result.state)} · ${result.modelId}',
                    ),
                    if (result.usage.groups.any((group) => group.simulated))
                      const Text('模拟测试结果；模拟执行不证明真实供应商能力已验证。'),
                  ],
                ],
                ModelJobCards(controller: c, compact: !widget.wide),
              ]),
            ],
          ],
        );
      },
    );
  }

  Widget _error(String code, VoidCallback reload) => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(modelErrorTitle(code), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: reload, child: const Text('重新读取')),
      ],
    ),
  );
  Widget _bindingCard(ModelConfigurationController c, String capability) {
    final binding = c.bindings[capability];
    final credential = c.selectedCredential;
    final choices =
        c.directory?.models
            .where(
              (m) => m.enabled && m.provider == c.provider && m.capabilities.contains(capability),
            )
            .toList() ??
        <CatalogModel>[];
    final selected = choices
        .where((m) => m.modelId == binding?.modelId && m.provider == binding?.provider)
        .firstOrNull;
    final canEdit = c.allows('client.profile.update') && credential != null && !c.submitting;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(switch (capability) {
                'text' => Icons.text_fields,
                'vision' => Icons.visibility_outlined,
                _ => Icons.graphic_eq,
              }, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(capabilityTitle(capability)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('$capability:${binding?.modelId}:${c.provider}'),
            initialValue: selected?.modelId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '模型'),
            items: [
              for (final m in choices)
                DropdownMenuItem(
                  value: m.modelId,
                  child: Text(m.displayName, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: canEdit
                ? (value) {
                    final model = choices.where((m) => m.modelId == value).firstOrNull;
                    if (model == null) return;
                    final voice = capability == 'tts'
                        ? c.directory?.voices
                              .where(
                                (v) => v.modelId == model.modelId && v.provider == model.provider,
                              )
                              .firstOrNull
                        : null;
                    c.editBinding(
                      capability,
                      ModelBinding(
                        credentialId: credential.id,
                        provider: model.provider,
                        modelId: model.modelId,
                        voiceId: voice?.voiceId,
                      ),
                    );
                  }
                : null,
          ),
          if (binding != null) ...[
            const SizedBox(height: 8),
            Text(binding.modelId, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '绑定：${c.credentials?.where((v) => v.id == binding.credentialId).firstOrNull?.maskedKey ?? '凭据不可用'}',
            ),
            Text(
              selected == null
                  ? '模型已下线或目录不可用'
                  : selected.verified
                  ? '目录协议已验证'
                  : '目录协议未验证',
            ),
            if (capability == 'tts') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('voice:${binding.voiceId}:${binding.modelId}'),
                initialValue:
                    c.directory?.voices.any(
                          (v) =>
                              v.modelId == binding.modelId &&
                              v.provider == binding.provider &&
                              v.voiceId == binding.voiceId,
                        ) ==
                        true
                    ? binding.voiceId
                    : null,
                decoration: const InputDecoration(labelText: '声音'),
                items: [
                  for (final voice in c.directory?.voices ?? <CatalogVoice>[])
                    if (voice.modelId == binding.modelId && voice.provider == binding.provider)
                      DropdownMenuItem(value: voice.voiceId, child: Text(voice.voiceId)),
                ],
                onChanged: canEdit
                    ? (value) => c.editBinding(
                        capability,
                        ModelBinding(
                          credentialId: binding.credentialId,
                          provider: binding.provider,
                          modelId: binding.modelId,
                          voiceId: value,
                          languageTag: binding.languageTag,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: binding.languageTag,
                decoration: const InputDecoration(labelText: '语种'),
                items: const [
                  DropdownMenuItem(value: 'ja', child: Text('日语')),
                  DropdownMenuItem(value: 'en', child: Text('英语')),
                ],
                onChanged: canEdit
                    ? (value) => c.editBinding(
                        capability,
                        ModelBinding(
                          credentialId: binding.credentialId,
                          provider: binding.provider,
                          modelId: binding.modelId,
                          voiceId: binding.voiceId,
                          languageTag: value ?? 'ja',
                        ),
                      )
                    : null,
              ),
              const Text('输出格式：MP3'),
            ],
            if (canEdit)
              TextButton(
                onPressed: () => c.editBinding(capability, null),
                child: const Text('清除绑定'),
              ),
          ] else
            const Text('未绑定'),
        ],
      ),
    );
  }

  Future<void> _save(ModelConfigurationController c) async {
    try {
      await c.saveBindings();
      if (mounted && c.errorCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模型偏好已保存')));
      }
    } catch (_) {}
  }

  Future<void> _keyDialog(ModelConfigurationController c, {ProviderCredential? previous}) async {
    final keyController = TextEditingController();
    final labelController = TextEditingController(text: previous?.label ?? '个人凭据');
    var obscured = true, busy = false;
    String? error;
    final scope = c.auth?.actionEpoch;
    try {
      await showHarukaDialog<void>(
        context: context,
        waitForRemoval: true,
        animationStyle: HarukaMotion.dialogStyle(context),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(previous == null ? '配置 API Key' : '轮换 API Key'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${previous?.provider ?? c.provider} · 仅保存本人加密凭据，不调用供应商。'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: '凭据名称'),
                    ),
                    const SizedBox(height: 10),
                    Identified(
                      id: UiTestIds.modelCredentialKey,
                      child: TextField(
                        controller: keyController,
                        obscureText: obscured,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '新的个人 API Key',
                          errorText: error,
                          suffixIcon: IconButton(
                            onPressed: () => setDialogState(() => obscured = !obscured),
                            tooltip: obscured ? '显示 Key' : '隐藏 Key',
                            icon: Icon(
                              obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              Identified(
                id: UiTestIds.modelCredentialSave,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (keyController.text.trim().length < 8 ||
                              labelController.text.trim().isEmpty) {
                            setDialogState(() => error = '请输入凭据名称和有效长度的 Key。');
                            return;
                          }
                          setDialogState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await c.saveCredential(
                              labelController.text.trim(),
                              keyController.text,
                              previous: previous,
                            );
                            if (dialogContext.mounted) keyController.clear();
                            if (dialogContext.mounted && c.auth?.actionEpoch == scope) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            if (dialogContext.mounted) keyController.clear();
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                busy = false;
                                error = modelErrorTitle(
                                  e is ApiFailure ? e.code : 'SERVICE_UNAVAILABLE',
                                );
                              });
                            }
                          }
                        },
                  child: Text(busy ? '保存中…' : '保存 API Key'),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      keyController.clear();
      keyController.dispose();
      labelController.dispose();
    }
  }

  Future<void> _delete(ModelConfigurationController c, ProviderCredential credential) async {
    final scope = c.auth?.actionEpoch;
    try {
      final impact = await c.repository.deletionImpact(credential);
      if (!mounted || c.auth?.actionEpoch != scope) return;
      final confirmed = await showHarukaDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('移除 API Key'),
          content: Text(
            '将撤销 ${credential.maskedKey}。\n关联能力：${(impact['bound_capabilities'] as List).map((v) => capabilityTitle(v as String)).join('、')}\n未完成任务：${impact['unfinished_job_count']}\n后续调用会停止，已提交结果仍保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认移除'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted && c.auth?.actionEpoch == scope) {
        await c.removeCredential(credential);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(modelErrorTitle(e is ApiFailure ? e.code : 'SERVICE_UNAVAILABLE')),
          ),
        );
      }
    }
  }

  Future<void> _testDialog(ModelConfigurationController c) async {
    var capability = 'text';
    String? selectedModel;
    var busy = false;
    String? error;
    ModelBinding? choice(String type) {
      final cred = c.selectedCredential;
      if (cred == null) return null;
      final models =
          c.directory?.models
              .where(
                (m) => m.enabled && m.provider == cred.provider && m.capabilities.contains(type),
              )
              .toList() ??
          <CatalogModel>[];
      final saved = c.bindings[type];
      final model =
          models.where((m) => m.modelId == selectedModel).firstOrNull ??
          models.where((m) => m.modelId == saved?.modelId).firstOrNull ??
          models.firstOrNull;
      if (model == null) return null;
      final voice = type == 'tts'
          ? c.directory?.voices
                .where((v) => v.provider == model.provider && v.modelId == model.modelId)
                .firstOrNull
          : null;
      return ModelBinding(
        credentialId: cred.id,
        provider: cred.provider,
        modelId: model.modelId,
        voiceId: voice?.voiceId,
        languageTag: saved?.languageTag ?? 'ja',
      );
    }

    final scope = c.auth?.actionEpoch;
    await showHarukaDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final binding = choice(capability);
          return AlertDialog(
            title: const Text('确认单项能力测试'),
            content: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Identified(
                      id: UiTestIds.modelTestCapability,
                      merge: true,
                      child: DropdownButtonFormField<String>(
                        initialValue: capability,
                        decoration: const InputDecoration(labelText: '本次能力'),
                        items: [
                          for (final v in const ['text', 'vision', 'tts'])
                            DropdownMenuItem(value: v, child: Text(capabilityTitle(v))),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setDialogState(() {
                                capability = v ?? 'text';
                                selectedModel = null;
                              }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (binding != null)
                      DropdownButtonFormField<String>(
                        key: ValueKey('test-model:$capability'),
                        isExpanded: true,
                        initialValue: binding.modelId,
                        decoration: const InputDecoration(labelText: '本次模型'),
                        items: [
                          for (final model in c.directory!.models)
                            if (model.enabled &&
                                model.provider == binding.provider &&
                                model.capabilities.contains(capability))
                              DropdownMenuItem(
                                value: model.modelId,
                                child: Text(model.displayName),
                              ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setDialogState(() => selectedModel = value),
                      ),
                    Text(
                      binding == null
                          ? '此能力当前没有已启用模型。'
                          : '${binding.provider} · ${binding.modelId}',
                    ),
                    const SizedBox(height: 10),
                    Text(switch (capability) {
                      'text' => '固定样本：请求返回 ok=true 的 JSON 对象。',
                      'vision' => '固定样本：红色方块 PNG，判断颜色并返回 ok=true。',
                      _ => '固定短句：日语「こんにちは。」或英语「Hello.」，验证 MP3 音频协议。',
                    }),
                    if (capability == 'tts' && binding != null)
                      Text('${binding.voiceId} · ${binding.languageTag} · MP3'),
                    const SizedBox(height: 10),
                    const Text('只测试本次所选一项，最多一次供应商调用；可能消耗供应商用量。失败或结果未知不会自动重试。'),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              Identified(
                id: UiTestIds.modelTestConfirm,
                child: FilledButton(
                  onPressed: busy || binding == null
                      ? null
                      : () async {
                          setDialogState(() => busy = true);
                          try {
                            await c.submitTest(capability, binding);
                            if (dialogContext.mounted && c.auth?.actionEpoch == scope) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                busy = false;
                                error = modelErrorTitle(
                                  c.errorCode ?? (e is ApiFailure ? e.code : 'SERVICE_UNAVAILABLE'),
                                );
                              });
                            }
                          }
                        },
                  child: Text(busy ? '正在受理…' : '确认测试'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ModelJobCards extends StatelessWidget {
  const ModelJobCards({required this.controller, this.compact = false, super.key});
  final ModelConfigurationController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(switch (c.connectionState) {
          'connected' => '进度已连接',
          'connecting' => '正在连接进度…',
          'disconnected' => '连接中断，正在重连；保留已确认状态。',
          _ => '持久任务状态',
        }),
        if (c.jobsLoading) const LinearProgressIndicator(),
        if (c.jobsErrorCode != null)
          Text(
            modelErrorTitle(c.jobsErrorCode),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (c.jobs.isEmpty && !c.jobsLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('暂无能力测试任务。')),
        for (final job in c.jobs.values) ...[
          const SizedBox(height: 14),
          HarukaSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${c.results[job.runId]?.usage.groups.isNotEmpty == true && c.results[job.runId]!.usage.groups.every((group) => group.simulated) ? '模拟能力测试' : '模型能力测试'} · ${modelStateTitle(job.state)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(job.id, style: Theme.of(context).textTheme.bodySmall),
                if (job.stage != null) Text('当前阶段：${job.stage}'),
                if (job.progress != null) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: job.progress! / 100),
                ],
                if (job.errorCode != null) Text(modelErrorTitle(job.errorCode)),
                if (job.state == 'unknown') const Text('请求可能已到达供应商；不会自动再次调用。请核对持久结果。'),
                if (c.results[job.runId] case final result?) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${capabilityTitle(result.capability)} · ${result.provider} · ${result.modelId}',
                  ),
                  Text('凭据版本 ${result.credentialVersion} · ${modelStateTitle(result.state)}'),
                  if (result.usage.groups.any((group) => group.simulated))
                    const Text('模拟测试结果；模拟执行不证明真实供应商能力已验证。'),
                  if (c.credentials?.where((v) => v.id == result.credentialId).firstOrNull
                      case final currentCredential?
                      when currentCredential.credentialVersion != result.credentialVersion)
                    const Text('这是旧凭据版本的历史结果。'),
                  if (result.testedAt != null) Text('完成时间：${result.testedAt!.toLocal()}'),
                  for (final group in result.usage.groups) UsageMetricRows(group: group),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: c.submitting ? null : () => c.refreshJob(job.id),
                      child: const Text('查看最新状态'),
                    ),
                    if (job.canCancel && c.allows('client.job.cancel'))
                      TextButton(
                        onPressed: c.submitting ? null : () => _cancel(context, c, job),
                        child: const Text('取消任务'),
                      ),
                    if (job.canRetry && c.allows('client.job.retry'))
                      TextButton(
                        onPressed: c.submitting ? null : () => _retry(context, c, job),
                        child: const Text('重试可恢复阶段'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _cancel(BuildContext context, ModelConfigurationController c, ModelJob job) async {
    final scope = c.auth?.actionEpoch;
    final yes = await showHarukaDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消任务'),
        content: const Text('取消将在执行边界生效；已发出的供应商请求可能仍会完成。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('返回')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (yes == true &&
        context.mounted &&
        scope == c.auth?.actionEpoch &&
        c.allows('client.job.cancel')) {
      try {
        await c.cancel(job);
      } catch (_) {}
    }
  }

  Future<void> _retry(BuildContext context, ModelConfigurationController c, ModelJob job) async {
    final scope = c.auth?.actionEpoch;
    if (job.state == 'unknown') return;
    final yes = await showHarukaDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认重试'),
        content: Text(
          job.requiresConfirmation ? '本次重试将创建一次新的供应商调用，可能消耗用量。' : '只恢复服务端允许的已提交阶段，不重复已完成的供应商调用。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认重试'),
          ),
        ],
      ),
    );
    if (yes == true &&
        context.mounted &&
        scope == c.auth?.actionEpoch &&
        c.allows('client.job.retry')) {
      try {
        await c.retry(job, job.requiresConfirmation);
      } catch (_) {}
    }
  }
}

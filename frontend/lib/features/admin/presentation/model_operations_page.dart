import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/motion.dart';

import '../../../core/api/model_settings_models.dart';
import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../shared/presentation/components.dart';
import '../../settings/presentation/model_configuration_content.dart';
import '../../settings/presentation/model_usage_content.dart';

const modelLimitLabels = {
  'max_credentials': '本人凭据数量上限',
  'max_concurrent_jobs': '本人同时运行任务数',
  'instance_concurrent_jobs': '实例同时运行任务数',
  'max_model_calls': '单次测试供应商调用数',
  'max_output_tokens': '文本输出 Token 上限',
  'timeout_seconds': '文本/视觉超时（秒）',
  'tts_timeout_seconds': '朗读超时（秒）',
  'max_test_image_bytes': '固定测试图片上限（字节）',
  'max_tts_characters': '朗读样本字符上限',
  'websocket_max_jobs': '进度订阅任务上限',
};

/// Metadata and aggregate operations inside the existing admin shell.
class AdminModelOperations extends StatefulWidget {
  const AdminModelOperations({required this.auth, required this.section, super.key});
  final AuthController auth;
  final String section;
  @override
  State<AdminModelOperations> createState() => _AdminModelOperationsState();
}

class _AdminModelOperationsState extends State<AdminModelOperations> {
  ModelDirectory? _directory;
  ModelLimits? _limits;
  List<AdminModelJob>? _jobs;
  List<UserModelLimit>? _userLimits;
  ModelUsage? _usage;
  final _model = TextEditingController();
  final Map<String, TextEditingController> _limitFields = {};
  String? _provider, _capability, _operation, _error;
  int _days = 30, _request = 0;
  bool _loading = false, _submitting = false, _enabled = true;
  String? _scope;
  bool _can(String permission) =>
      widget.auth.isAuthenticated &&
      widget.auth.admin &&
      (widget.auth.access?.allows(permission) ?? false);
  String get _readPermission => switch (widget.section) {
    'models' => 'admin.model_catalog.read',
    'limits' => 'admin.quota.read',
    'jobs' => 'admin.job.read',
    _ => 'admin.dashboard.view',
  };
  String? _identity() => widget.auth.isAuthenticated && widget.auth.admin
      ? '${widget.auth.boundInstanceId}:${widget.auth.access?.userId}:${widget.auth.access?.sessionRef}'
      : null;
  @override
  void initState() {
    super.initState();
    _scope = _identity();
    widget.auth.addListener(_authChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AdminModelOperations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _clear();
      unawaited(_load());
    }
  }

  void _clear() {
    ++_request;
    _directory = null;
    _limits = null;
    _jobs = null;
    _userLimits = null;
    _usage = null;
    _error = null;
    _loading = false;
    _submitting = false;
    for (final field in _limitFields.values) {
      field.dispose();
    }
    _limitFields.clear();
  }

  void _authChanged() {
    if (_identity() != _scope || !_can(_readPermission)) {
      _scope = _identity();
      _clear();
      if (mounted) setState(() {});
    }
  }

  bool _current(int request, String? scope) =>
      mounted && request == _request && scope == _identity() && _can(_readPermission);
  @override
  void dispose() {
    widget.auth.removeListener(_authChanged);
    _model.dispose();
    for (final field in _limitFields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<T> _get<T>(String path, T Function(Object?) decode) => widget.auth.authorizedRead(
    (headers) async =>
        (await widget.auth.repository.api.getJson(path, decode, headers: headers)).data,
  );
  Future<void> _load() async {
    if (!_can(_readPermission)) return;
    final request = ++_request;
    final scope = _identity();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (widget.section) {
        case 'models':
          final loaded = await _get('/api/v1/admin/model-catalog', ModelDirectory.fromJson);
          if (_current(request, scope)) _directory = loaded;
        case 'limits':
          final loaded = await _get('/api/v1/admin/model-limits', ModelLimits.fromJson);
          if (_current(request, scope)) {
            _limits = loaded;
            _enabled = loaded.enabled;
            for (final entry in loaded.values.entries) {
              _limitFields.putIfAbsent(entry.key, () => TextEditingController()).text =
                  '${entry.value}';
            }
          }
          final overrides = await _get(
            '/api/v1/admin/user-model-limits',
            (value) => modelList(wireObject(value)['items'], UserModelLimit.fromJson),
          );
          if (_current(request, scope)) _userLimits = overrides;
        case 'jobs':
          final loaded = await _get(
            '/api/v1/admin/jobs',
            (value) => modelList(wireObject(value)['items'], AdminModelJob.fromJson),
          );
          if (_current(request, scope)) _jobs = loaded;
        default:
          final path = Uri(
            path: '/api/v1/admin/model-usage',
            queryParameters: {
              'since': DateTime.now().toUtc().subtract(Duration(days: _days)).toIso8601String(),
              'provider': ?_provider,
              'capability': ?_capability,
              'operation_kind': ?_operation,
              if (_model.text.trim().isNotEmpty) 'model_id': _model.text.trim(),
            },
          ).toString();
          final loaded = await _get(path, ModelUsage.fromJson);
          if (_current(request, scope)) _usage = loaded;
      }
    } catch (error) {
      if (_current(request, scope)) {
        _error = error is ApiFailure ? error.code : 'SERVICE_UNAVAILABLE';
      }
    } finally {
      if (_current(request, scope)) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_can(_readPermission)) return const Text('当前账号没有此页面权限。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _loading || _submitting ? null : _load,
            child: const Text('刷新当前数据'),
          ),
        ),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(
            modelErrorTitle(_error),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        switch (widget.section) {
          'models' => _catalog(),
          'limits' => _limitForm(),
          'jobs' => _jobList(),
          _ => _usageView(),
        },
      ],
    );
  }

  Widget _catalog() => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('模型能力目录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('目录启停只控制后续使用，不填入共享 Key，也不会调用个人模型。'),
        for (final model in _directory?.models ?? <CatalogModel>[]) ...[
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(model.displayName),
            subtitle: Text(
              '${model.provider} · ${model.modelId}\n${model.capabilities.map(capabilityTitle).join(' / ')} · ${model.verified ? '协议已验证' : '协议未验证'}',
            ),
            trailing: _can('admin.model_catalog.update')
                ? Switch(
                    value: model.enabled,
                    onChanged: _submitting ? null : (value) => _changeModel(model, value),
                  )
                : Text(model.enabled ? '已启用' : '已停用'),
          ),
        ],
        if (_directory?.models.isEmpty == true) const Text('暂无模型目录。'),
      ],
    ),
  );
  Future<void> _changeModel(CatalogModel model, bool enabled) async {
    final scope = _identity();
    final yes = await showHarukaDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认模型目录变更'),
        content: Text(
          '${model.provider} · ${model.modelId}\n${enabled ? '启用后允许新的有权调用。' : '停用后不允许新的调用；已保存成果仍保留。'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('提交变更'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || scope != _identity() || !_can('admin.model_catalog.update')) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final saved = await widget.auth.authorizedWrite(
        (headers) async => (await widget.auth.repository.api.patchJson(
          '/api/v1/admin/model-catalog/${model.id}',
          {'expected_revision': model.revision, 'enabled': enabled},
          ModelDirectory.fromJson,
          headers: headers,
        )).data,
      );
      if (mounted && scope == _identity() && _can(_readPermission)) {
        final updated = saved.models.where((entry) => entry.id == model.id).firstOrNull;
        if (updated == null || updated.enabled != enabled || updated.revision <= model.revision) {
          throw const ApiFailure(code: 'INVALID_RESPONSE');
        }
        setState(() {
          _directory = saved;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && scope == _identity()) {
        setState(() => _error = error is ApiFailure ? error.code : 'SERVICE_UNAVAILABLE');
      }
    } finally {
      if (mounted && scope == _identity()) setState(() => _submitting = false);
    }
  }

  Widget _limitForm() => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('模型运行限制', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('技术上限用于运行保护，不是套餐或可购买额度。降低限制不删除既有成果。'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('允许能力测试'),
          value: _enabled,
          onChanged: _can('admin.quota.update') && !_submitting
              ? (value) => setState(() => _enabled = value)
              : null,
        ),
        for (final entry in _limitFields.entries) ...[
          const SizedBox(height: 12),
          TextField(
            controller: entry.value,
            readOnly: !_can('admin.quota.update') || _submitting,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: modelLimitLabels[entry.key] ?? entry.key),
          ),
        ],
        const SizedBox(height: 16),
        if (_can('admin.quota.update'))
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _submitting || _limits == null ? null : _saveLimits,
              child: const Text('预览并保存限制'),
            ),
          ),
        const SizedBox(height: 24),
        const Text('用户并发覆盖', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('没有覆盖的用户沿用全局上限；0 暂停后续任务，1 允许单任务。'),
        for (final item in _userLimits ?? <UserModelLimit>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.userId),
            subtitle: Text('并发 ${item.concurrentJobs} · 版本 ${item.revision}'),
            trailing: _can('admin.quota.update')
                ? Wrap(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '修改覆盖',
                        onPressed: _submitting ? null : () => _userLimitDialog(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '恢复全局上限',
                        onPressed: _submitting ? null : () => _userLimitDialog(item, remove: true),
                      ),
                    ],
                  )
                : null,
          ),
        if (_can('admin.quota.update'))
          OutlinedButton(
            onPressed: _submitting ? null : () => _userLimitDialog(null),
            child: const Text('添加用户覆盖'),
          ),
      ],
    ),
  );
  Future<void> _saveLimits() async {
    final values = <String, int>{};
    for (final entry in _limitFields.entries) {
      final value = int.tryParse(entry.value.text);
      if (value == null || value < 0) {
        setState(() => _error = 'INVALID_REQUEST');
        return;
      }
      values[entry.key] = value;
    }
    final scope = _identity();
    final yes = await showHarukaDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认运行限制'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('能力测试：${_enabled ? '启用' : '停用'}'),
                for (final entry in values.entries)
                  Text('${modelLimitLabels[entry.key]}：${entry.value}'),
                const SizedBox(height: 12),
                const Text('仅影响后续动作。服务端仍检查部署硬上限及当前 revision。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || scope != _identity() || !_can('admin.quota.update')) return;
    setState(() => _submitting = true);
    try {
      final saved = await widget.auth.authorizedWrite(
        (headers) async => (await widget.auth.repository.api.patchJson(
          '/api/v1/admin/model-limits',
          {
            'expected_revision': _limits!.revision,
            'limits': {...values, 'enabled': _enabled, 'revision': _limits!.revision},
          },
          ModelLimits.fromJson,
          headers: headers,
        )).data,
      );
      if (mounted && scope == _identity()) setState(() => _limits = saved);
    } catch (error) {
      if (mounted && scope == _identity()) {
        setState(() => _error = error is ApiFailure ? error.code : 'SERVICE_UNAVAILABLE');
      }
    } finally {
      if (mounted && scope == _identity()) setState(() => _submitting = false);
    }
  }

  Future<void> _userLimitDialog(UserModelLimit? previous, {bool remove = false}) async {
    final user = TextEditingController(text: previous?.userId ?? '');
    var value = previous?.concurrentJobs ?? 1;
    final scope = _identity();
    try {
      final confirmed = await showHarukaDialog<bool>(
        context: context,
        waitForRemoval: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(remove ? '恢复全局上限' : '确认用户并发覆盖'),
            content: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: user,
                    readOnly: previous != null,
                    decoration: const InputDecoration(labelText: '用户 ID'),
                  ),
                  if (!remove)
                    DropdownButtonFormField<int>(
                      initialValue: value,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('0 · 暂停')),
                        DropdownMenuItem(value: 1, child: Text('1 · 单任务')),
                      ],
                      onChanged: (next) => update(() => value = next ?? 1),
                    ),
                  Text(remove ? '移除个人覆盖，后续动作沿用全局限制。' : '仅修改运行保护，不授予模型调用权限。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted || scope != _identity() || !_can('admin.quota.update')) {
        return;
      }
      final id = wireUuid(user.text.trim());
      setState(() => _submitting = true);
      final saved = await widget.auth.authorizedWrite((headers) async {
        if (remove) {
          await widget.auth.repository.api.deleteJson(
            '/api/v1/admin/user-model-limits/$id',
            {'expected_revision': previous!.revision},
            wireObject,
            headers: headers,
          );
          return null;
        }
        return (await widget.auth.repository.api.patchJson(
          '/api/v1/admin/user-model-limits/$id',
          {'expected_revision': previous?.revision ?? 0, 'max_concurrent_jobs': value},
          UserModelLimit.fromJson,
          headers: headers,
        )).data;
      });
      if (mounted && scope == _identity() && _can(_readPermission)) {
        setState(() {
          _userLimits = [...?_userLimits?.where((item) => item.userId != id), ?saved];
        });
      }
    } catch (error) {
      if (mounted && scope == _identity()) {
        setState(() => _error = error is ApiFailure ? error.code : 'INVALID_REQUEST');
      }
    } finally {
      user.dispose();
      if (mounted && scope == _identity()) setState(() => _submitting = false);
    }
  }

  Widget _jobList() => HarukaSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('任务摘要', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('只显示运维元数据；不读取个人 Key、模型回复或材料正文。'),
        if (_jobs?.isEmpty == true)
          const Padding(padding: EdgeInsets.all(18), child: Text('暂无任务。')),
        if (_jobs != null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('任务引用')),
                DataColumn(label: Text('类型')),
                DataColumn(label: Text('状态')),
                DataColumn(label: Text('操作')),
              ],
              rows: [
                for (final job in _jobs!)
                  DataRow(
                    cells: [
                      DataCell(Text(job.id)),
                      DataCell(Text(job.operationKind)),
                      DataCell(Text(modelStateTitle(job.state))),
                      DataCell(
                        TextButton(onPressed: () => _jobDialog(job), child: const Text('查看摘要')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  Future<void> _jobDialog(AdminModelJob job) async {
    await showHarukaDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('运维摘要'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.id),
              Text('当前状态：${modelStateTitle(job.state)}'),
              Text('代次：${job.generation} · 序号：${job.sequence}'),
              if (job.errorCode != null) Text(modelErrorTitle(job.errorCode)),
              if (job.state == 'unknown') const Text('供应商结果待核对，管理员不能重新调用。'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭')),
          if (job.canCancel && _can('admin.job.cancel'))
            TextButton(
              onPressed: _submitting
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      unawaited(_jobAction(job, 'cancel'));
                    },
              child: const Text('取消任务'),
            ),
          if (job.canRetry && _can('admin.job.retry') && job.state != 'unknown')
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      unawaited(_jobAction(job, 'retry'));
                    },
              child: const Text('恢复安全阶段'),
            ),
        ],
      ),
    );
  }

  Future<void> _jobAction(AdminModelJob job, String action) async {
    final scope = _identity();
    final yes = await showHarukaDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action == 'cancel' ? '确认取消' : '确认安全恢复'),
        content: Text(
          action == 'cancel' ? '取消在执行边界生效；已经发出的供应商请求可能仍完成。' : '只恢复服务端明确允许的非模型调用阶段，不创建供应商 attempt。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('返回')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || scope != _identity() || !_can('admin.job.$action')) return;
    setState(() => _submitting = true);
    try {
      final updated = await widget.auth.authorizedWrite(
        (headers) async => (await widget.auth.repository.api.postJson(
          '/api/v1/admin/jobs/${job.id}/$action',
          {'expected_revision': job.revision},
          AdminModelJob.fromJson,
          headers: headers,
        )).data,
      );
      if (mounted && scope == _identity()) {
        setState(() => _jobs = [for (final j in _jobs!) j.id == updated.id ? updated : j]);
      }
    } catch (error) {
      if (mounted && scope == _identity()) {
        setState(() => _error = error is ApiFailure ? error.code : 'SERVICE_UNAVAILABLE');
      }
    } finally {
      if (mounted && scope == _identity()) setState(() => _submitting = false);
    }
  }

  Widget _usageView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HarukaSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 天')),
                ButtonSegment(value: 30, label: Text('30 天')),
                ButtonSegment(value: 90, label: Text('90 天')),
              ],
              selected: {_days},
              onSelectionChanged: (v) => setState(() => _days = v.first),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(labelText: '供应商'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
              ],
              onChanged: (v) => setState(() => _provider = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _capability,
              decoration: const InputDecoration(labelText: '能力'),
              items: [
                const DropdownMenuItem(value: null, child: Text('全部')),
                for (final v in const ['text', 'vision', 'tts'])
                  DropdownMenuItem(value: v, child: Text(capabilityTitle(v))),
              ],
              onChanged: (v) => setState(() => _capability = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: '模型 ID（可选）'),
              onSubmitted: (_) => unawaited(_load()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _operation,
              decoration: const InputDecoration(labelText: '操作类别'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: 'credential_test', child: Text('凭据能力测试')),
              ],
              onChanged: (value) => setState(() => _operation = value),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: _loading ? null : _load, child: const Text('应用筛选')),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_usage != null) ModelUsageSummary(usage: _usage!, wide: true),
    ],
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/model_settings_models.dart';
import '../../../core/api/request_ids.dart';
import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../../jobs/data/job_socket.dart';
import '../data/model_configuration_repository.dart';

/// Account-bound memory only. UI overlays and layout changes never invalidate reads.
final class ModelConfigurationController extends ChangeNotifier {
  ModelConfigurationController({required this.repository, required this.allows, this.auth}) {
    _scopeKey = _identity();
    _permissionKey = _permissions();
    auth?.addListener(_authChanged);
  }
  final ModelConfigurationRepository repository;
  final bool Function(String permission) allows;
  final AuthController? auth;
  List<ProviderCredential>? credentials;
  ModelDirectory? directory;
  PersonalModelSettings? settings;
  final Map<String, ModelBinding?> bindings = {};
  final Map<String, ModelJob> jobs = {};
  final Map<String, CredentialTestResult> results = {};
  ModelUsage? usage;
  Map<String, String> usageFilters = {};
  String usageModelDraft = '';
  String? usageProviderDraft, usageCapabilityDraft, usageOperationDraft;
  int usageDaysDraft = 30;
  String provider = 'openrouter';
  String? selectedCredentialId;
  String? errorCode;
  String? jobsErrorCode;
  String? usageErrorCode;
  String connectionState = 'idle';
  AcceptedModelTest? accepted;
  String? acceptedCredentialId;
  bool loading = false,
      submitting = false,
      dirty = false,
      jobsLoading = false,
      usageLoading = false;
  bool _disposed = false, _jobsRequested = false;
  int _generation = 0, _reconnectAttempt = 0, _usageSequence = 0;
  String? _scopeKey;
  String _permissionKey = '';
  String _permissions() => const [
    'client.credential.read',
    'client.credential.test',
    'client.credential.manage',
    'client.profile.read',
    'client.profile.update',
    'client.job.read',
    'client.job.cancel',
    'client.job.retry',
  ].map((p) => allows(p)).join(':');
  Future<void>? _loadFlight, _jobsFlight;
  JobSocket? _socket;
  StreamSubscription<String>? _socketEvents;
  Timer? _reconnect;
  final Set<String> _resultFlights = {};

  String? _identity() {
    final access = auth?.access;
    if (auth == null) return 'test';
    return auth!.isAuthenticated && !auth!.admin && access != null
        ? '${auth!.boundInstanceId}:${access.userId}:${access.sessionRef}'
        : null;
  }

  void _authChanged() {
    final identity = _identity();
    final permissions = _permissions();
    if (identity != _scopeKey || permissions != _permissionKey) {
      reset();
      _scopeKey = identity;
      _permissionKey = permissions;
      return;
    }
    if (!allows('client.credential.read')) {
      credentials = null;
      results.clear();
      usage = null;
      settings = null;
      bindings.clear();
    }
    if (!allows('client.job.read')) {
      jobs.clear();
      accepted = null;
      _jobsRequested = false;
      unawaited(_closeSocket());
    }
    _notify();
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ProviderCredential? get selectedCredential =>
      credentials?.where((c) => c.id == selectedCredentialId && c.status == 'active').firstOrNull;
  bool get canTest =>
      allows('client.credential.test') &&
      selectedCredential != null &&
      !submitting &&
      directory?.limits.enabled == true;
  bool get testOutcomeUncertain => errorCode == 'TEST_ACCEPTANCE_UNKNOWN';
  void selectProvider(String value) {
    provider = value;
    selectedCredentialId = credentials
        ?.where((c) => c.provider == value && c.status == 'active')
        .firstOrNull
        ?.id;
    _notify();
  }

  void selectCredential(String? id) {
    selectedCredentialId = id;
    _notify();
  }

  void editBinding(String capability, ModelBinding? binding) {
    bindings[capability] = binding;
    dirty = true;
    _notify();
  }

  String _error(Object error) => error is ApiFailure ? error.code : 'SERVICE_UNAVAILABLE';

  Future<void> ensureConfiguration({bool refresh = false}) {
    if (_loadFlight != null) return _loadFlight!;
    if (!refresh &&
        directory != null &&
        credentials != null &&
        (settings != null || !allows('client.profile.read'))) {
      return Future.value();
    }
    final flight = _load(refresh);
    _loadFlight = flight;
    return flight.whenComplete(() {
      if (identical(_loadFlight, flight)) _loadFlight = null;
    });
  }

  Future<void> _load(bool refresh) async {
    final generation = _generation;
    loading = true;
    errorCode = null;
    _notify();
    try {
      final loaded = await Future.wait<Object>([
        repository.credentials(),
        repository.directory(),
        if (allows('client.profile.read')) repository.settings(),
      ]);
      if (!_current(generation)) return;
      credentials = loaded[0] as List<ProviderCredential>;
      directory = loaded[1] as ModelDirectory;
      if (loaded.length > 2) {
        settings = loaded[2] as PersonalModelSettings;
        if (!dirty) {
          bindings
            ..clear()
            ..addAll(settings!.bindings);
        }
      }
      if (selectedCredential == null) {
        selectedCredentialId = credentials!
            .where((c) => c.provider == provider && c.status == 'active')
            .firstOrNull
            ?.id;
      }
    } catch (error) {
      if (_current(generation)) errorCode = _error(error);
    } finally {
      if (_current(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> saveCredential(String label, String key, {ProviderCredential? previous}) async {
    final generation = _generation;
    if (submitting) return;
    submitting = true;
    errorCode = null;
    _notify();
    try {
      final saved = await repository.saveCredential(
        previous?.provider ?? provider,
        label,
        key,
        previous: previous,
      );
      if (!_current(generation)) return;
      credentials = [
        for (final c in credentials ?? <ProviderCredential>[])
          if (c.id != saved.id) c,
        saved,
      ];
      selectedCredentialId = saved.id;
      provider = saved.provider;
      if (previous != null) results.removeWhere((_, result) => result.credentialId == previous.id);
    } catch (error) {
      if (_current(generation)) errorCode = _error(error);
      rethrow;
    } finally {
      if (_current(generation)) {
        submitting = false;
        _notify();
      }
    }
  }

  Future<void> removeCredential(ProviderCredential credential) async {
    final generation = _generation;
    if (submitting) return;
    submitting = true;
    errorCode = null;
    _notify();
    try {
      await repository.deleteCredential(credential);
      if (!_current(generation)) return;
      credentials = credentials?.where((c) => c.id != credential.id).toList();
      results.removeWhere((_, r) => r.credentialId == credential.id);
      for (final capability in bindings.keys.toList()) {
        if (bindings[capability]?.credentialId == credential.id) bindings[capability] = null;
      }
      settings = null;
      dirty = false;
      selectedCredentialId = null;
      // Only the affected settings and jobs are re-read after confirmed deletion.
      await ensureConfiguration(refresh: true);
      if (_jobsRequested) await ensureJobs(refresh: true);
    } catch (error) {
      if (_current(generation)) errorCode = _error(error);
      rethrow;
    } finally {
      if (_current(generation)) {
        submitting = false;
        _notify();
      }
    }
  }

  Future<void> saveBindings() async {
    if (settings == null || submitting) return;
    final generation = _generation;
    submitting = true;
    errorCode = null;
    _notify();
    try {
      final saved = await repository.saveBindings(settings!.revision, bindings);
      if (!_current(generation)) return;
      settings = saved;
      bindings
        ..clear()
        ..addAll(saved.bindings);
      dirty = false;
    } catch (error) {
      if (_current(generation)) errorCode = _error(error);
      rethrow;
    } finally {
      if (_current(generation)) {
        submitting = false;
        _notify();
      }
    }
  }

  Future<void> submitTest(String capability, ModelBinding binding) async {
    final credential = selectedCredential;
    if (credential == null || submitting || testOutcomeUncertain) return;
    final generation = _generation;
    submitting = true;
    errorCode = null;
    _notify();
    try {
      final reference = await repository.test(credential, capability, binding, newRequestId());
      if (!_current(generation)) return;
      accepted = reference;
      acceptedCredentialId = credential.id;
      _notify();
      await ensureJobs(refresh: true);
    } catch (error) {
      if (_current(generation)) {
        errorCode = error is ApiFailure && !error.retryableTransport
            ? _error(error)
            : 'TEST_ACCEPTANCE_UNKNOWN';
      }
      rethrow;
    } finally {
      if (_current(generation)) {
        submitting = false;
        _notify();
      }
    }
  }

  Future<void> ensureJobs({bool refresh = false}) {
    if (!allows('client.job.read')) return Future.value();
    if (_jobsFlight != null) return _jobsFlight!;
    if (_jobsRequested && !refresh) return Future.value();
    _jobsRequested = true;
    final flight = _loadJobs();
    _jobsFlight = flight;
    return flight.whenComplete(() {
      if (identical(_jobsFlight, flight)) _jobsFlight = null;
    });
  }

  Future<void> readAcceptedResult() async {
    final reference = accepted;
    final credential = acceptedCredentialId;
    if (reference == null || credential == null || !allows('client.credential.read')) return;
    final generation = _generation;
    try {
      final result = await repository.testResult(credential, reference.runId);
      if (_current(generation)) {
        results[result.runId] = result;
        _notify();
      }
    } catch (error) {
      if (_current(generation)) {
        errorCode = _error(error);
        _notify();
      }
    }
  }

  Future<void> _loadJobs() async {
    final generation = _generation;
    jobsLoading = true;
    jobsErrorCode = null;
    _notify();
    try {
      final loaded = await repository.jobs();
      if (!_current(generation)) return;
      jobs
        ..clear()
        ..addEntries(loaded.map((j) => MapEntry(j.id, j)));
      for (final job in loaded) {
        if (job.terminal) unawaited(_loadResult(job));
      }
      if (_socket == null) {
        unawaited(_connect());
      } else {
        _subscribe();
      }
    } catch (error) {
      if (_current(generation)) jobsErrorCode = _error(error);
    } finally {
      if (_current(generation)) {
        jobsLoading = false;
        _notify();
      }
    }
  }

  Future<void> refreshJob(String id) async {
    final generation = _generation;
    try {
      final snapshot = await repository.job(id);
      if (_current(generation)) _acceptJob(snapshot, force: true);
    } catch (error) {
      if (_current(generation)) {
        jobsErrorCode = _error(error);
        _notify();
      }
    }
  }

  void _acceptJob(ModelJob snapshot, {bool force = false}) {
    final old = jobs[snapshot.id];
    if (old != null &&
        (snapshot.generation < old.generation ||
            (snapshot.generation == old.generation && snapshot.sequence < old.sequence))) {
      return;
    }
    if (old != null && !snapshot.newerThan(old) && !force) return;
    jobs[snapshot.id] = snapshot;
    if (snapshot.terminal) unawaited(_loadResult(snapshot));
    _notify();
  }

  Future<void> _loadResult(ModelJob job) async {
    if (!allows('client.credential.read') ||
        results.containsKey(job.runId) ||
        !_resultFlights.add(job.runId)) {
      return;
    }
    final generation = _generation;
    try {
      final result = await repository.result(job);
      if (_current(generation)) {
        results[job.runId] = result;
        usage = null;
        _notify();
      }
    } catch (error) {
      if (_current(generation)) {
        jobsErrorCode = _error(error);
        _notify();
      }
    } finally {
      if (_current(generation)) _resultFlights.remove(job.runId);
    }
  }

  Future<void> cancel(ModelJob job) async => _jobWrite(() => repository.cancel(job));
  Future<void> retry(ModelJob job, bool confirmation) async =>
      _jobWrite(() => repository.retry(job, confirmation, newRequestId()));
  Future<void> _jobWrite(Future<ModelJob> Function() action) async {
    if (submitting) return;
    final generation = _generation;
    submitting = true;
    jobsErrorCode = null;
    _notify();
    try {
      final snapshot = await action();
      if (_current(generation)) {
        _acceptJob(snapshot, force: true);
        _subscribe();
      }
    } catch (error) {
      if (_current(generation)) jobsErrorCode = _error(error);
      rethrow;
    } finally {
      if (_current(generation)) {
        submitting = false;
        _notify();
      }
    }
  }

  Future<void> ensureUsage({Map<String, String>? filters, bool refresh = false}) async {
    if (!allows('client.credential.read')) return;
    if (filters == null && !refresh && usageLoading) return;
    if (filters == null && !refresh && usage != null) return;
    final query =
        filters ??
        (usageFilters.isEmpty
            ? <String, String>{
                'since': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(days: 30))
                    .toIso8601String(),
              }
            : usageFilters);
    final request = ++_usageSequence;
    final generation = _generation;
    usageFilters = Map.of(query);
    usageLoading = true;
    usageErrorCode = null;
    _notify();
    try {
      final loaded = await repository.usage(query);
      if (_current(generation) && request == _usageSequence) usage = loaded;
    } catch (error) {
      if (_current(generation) && request == _usageSequence) usageErrorCode = _error(error);
    } finally {
      if (_current(generation) && request == _usageSequence) {
        usageLoading = false;
        _notify();
      }
    }
  }

  Future<void> _connect() async {
    if (_disposed ||
        _socket != null ||
        connectionState == 'connecting' ||
        !allows('client.job.read')) {
      return;
    }
    final generation = _generation;
    connectionState = 'connecting';
    _notify();
    try {
      final socket = await repository.connect();
      if (!_current(generation) || !allows('client.job.read')) {
        await socket.close();
        return;
      }
      _socket = socket;
      connectionState = 'connected';
      _reconnectAttempt = 0;
      _socketEvents = socket.messages.listen(
        (message) {
          if (_current(generation)) _event(message);
        },
        onError: (Object error) {
          if (_current(generation)) _disconnected();
        },
        onDone: () {
          if (_current(generation)) _disconnected();
        },
      );
      _subscribe();
      _notify();
    } catch (_) {
      if (_current(generation)) _disconnected();
    }
  }

  void _subscribe() {
    if (_socket == null) return;
    final selected = jobs.values
        .take(directory?.limits.values['websocket_max_jobs'] ?? 100)
        .toList();
    _socket!.send(
      jsonEncode({
        'schema_version': 1,
        'type': 'subscribe',
        'job_ids': selected.map((j) => j.id).toList(),
        'cursors': {
          for (final j in selected) j.id: {'generation': j.generation, 'sequence': j.sequence},
        },
      }),
    );
  }

  void _event(String message) {
    try {
      final j = wireObject(jsonDecode(message));
      if (j['schema_version'] != 1) return;
      final id = j['job_id'];
      if (id is! String || !jobs.containsKey(id)) return;
      if (j['type'] == 'resync_required') {
        unawaited(refreshJob(id));
        return;
      }
      final snapshot = ModelJobEvent.fromJson(j).payload;
      final old = jobs[id]!;
      if (snapshot.generation > old.generation || snapshot.sequence > old.sequence + 1) {
        unawaited(refreshJob(id));
        return;
      }
      _acceptJob(snapshot);
    } catch (_) {
      jobsErrorCode = 'INVALID_RESPONSE';
      _notify();
    }
  }

  void _disconnected() {
    unawaited(_socketEvents?.cancel());
    _socketEvents = null;
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
    if (_disposed || !_jobsRequested || !allows('client.job.read')) return;
    connectionState = 'disconnected';
    _notify();
    _reconnect?.cancel();
    final delay = Duration(seconds: (1 << _reconnectAttempt.clamp(0, 5)));
    _reconnectAttempt++;
    _reconnect = Timer(delay, () => unawaited(_reconnectJobs()));
  }

  Future<void> _reconnectJobs() async {
    // Recover persisted snapshots. Reconnection never repeats the model POST.
    final generation = _generation;
    for (final id in jobs.keys.toList()) {
      await refreshJob(id);
      if (!_current(generation)) return;
    }
    await _connect();
  }

  Future<void> _closeSocket() async {
    _reconnect?.cancel();
    _reconnect = null;
    final events = _socketEvents;
    _socketEvents = null;
    final socket = _socket;
    _socket = null;
    connectionState = 'idle';
    await events?.cancel();
    await socket?.close();
  }

  void reset() {
    ++_generation;
    ++_usageSequence;
    _loadFlight = null;
    _jobsFlight = null;
    _jobsRequested = false;
    _resultFlights.clear();
    unawaited(_closeSocket());
    credentials = null;
    directory = null;
    settings = null;
    bindings.clear();
    jobs.clear();
    results.clear();
    usage = null;
    usageFilters = {};
    usageModelDraft = '';
    usageProviderDraft = null;
    usageCapabilityDraft = null;
    usageOperationDraft = null;
    usageDaysDraft = 30;
    accepted = null;
    acceptedCredentialId = null;
    selectedCredentialId = null;
    provider = 'openrouter';
    errorCode = null;
    jobsErrorCode = null;
    usageErrorCode = null;
    loading = false;
    submitting = false;
    dirty = false;
    jobsLoading = false;
    usageLoading = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    auth?.removeListener(_authChanged);
    ++_generation;
    unawaited(_closeSocket());
    super.dispose();
  }
}

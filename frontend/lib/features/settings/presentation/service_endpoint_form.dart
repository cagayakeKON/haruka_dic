import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../generated/ui_test_ids.dart';
import '../domain/service_endpoint.dart';

/// Native service switching. Web keeps the current deployment and does not probe.
final class ServiceEndpointController extends ChangeNotifier {
  ServiceEndpointController({
    required this.canSwitch,
    required this.allowDevelopmentHttp,
    required this.currentEndpoint,
    required this.currentInstance,
    required this.signedIn,
    required this.probe,
    required this.signOut,
    required this.stopOldActions,
    required this.resumeActions,
    required this.clearCache,
    required this.retarget,
    required this.bindInstance,
    required this.verify,
    this.recordProbe,
    this.recordSwitch,
  });

  final bool canSwitch;
  final bool allowDevelopmentHttp;
  final Uri Function() currentEndpoint;
  final String Function() currentInstance;
  final bool Function() signedIn;
  final Future<ServiceProbe> Function(Uri endpoint, {Dio? client}) probe;
  final Future<void> Function() signOut;
  final void Function() stopOldActions;
  final void Function() resumeActions;
  final Future<void> Function() clearCache;
  final void Function(Uri endpoint, String instanceId) retarget;
  final void Function(Uri endpoint, String instanceId) bindInstance;
  final Future<void> Function() verify;
  final void Function({required String result, required int durationMs})? recordProbe;
  final void Function({required String result})? recordSwitch;

  ServiceProbe? pending;
  bool busy = false;
  bool attempted = false;
  bool revokeFailed = false;
  String? failure;
  int _probeGeneration = 0;

  void resetProbeFeedback() {
    // A form can be left while an HTTP probe is still pending. Its result must
    // not become the confirmation or error of the newly opened form.
    _probeGeneration += 1;
    pending = null;
    attempted = false;
    revokeFailed = false;
    failure = null;
  }

  void addressChanged() {
    if (busy) return;
    if (pending == null && !attempted && failure == null) return;
    pending = null;
    attempted = false;
    failure = null;
    notifyListeners();
  }

  Future<void> probeAddress(String raw) async {
    if (!canSwitch || busy) return;
    final generation = ++_probeGeneration;
    attempted = true;
    pending = null;
    failure = null;
    revokeFailed = false;
    final endpoint = parseServiceEndpoint(raw, allowDevelopmentHttp: allowDevelopmentHttp);
    if (endpoint == null) {
      failure = 'invalid';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    final started = Stopwatch()..start();
    try {
      final result = await probe(endpoint);
      if (generation != _probeGeneration) return;
      pending = result;
      failure = null;
      recordProbe?.call(result: 'success', durationMs: started.elapsedMilliseconds);
    } on Object {
      if (generation != _probeGeneration) return;
      pending = null;
      failure = 'probe';
      recordProbe?.call(result: 'failure', durationMs: started.elapsedMilliseconds);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> adopt() async {
    final next = pending;
    if (!canSwitch || busy || next == null) return false;
    busy = true;
    failure = null;
    notifyListeners();
    final previousEndpoint = currentEndpoint();
    final previousInstanceId = currentInstance();
    try {
      final result = await commitInstanceSwitch(
        signedIn: signedIn(),
        stopOldActions: stopOldActions,
        resumeActions: resumeActions,
        signOut: signOut,
        clearLocalScope: clearCache,
        retarget: retarget,
        bindInstance: bindInstance,
        previousEndpoint: previousEndpoint,
        previousInstanceId: previousInstanceId,
        probe: next,
        verify: verify,
      );
      pending = null;
      revokeFailed = result.revokeFailed;
      recordSwitch?.call(result: 'success');
      return true;
    } on Object {
      pending = null;
      failure = 'adopt';
      recordSwitch?.call(result: 'failure');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class ServiceEndpointScope extends InheritedNotifier<ServiceEndpointController> {
  const ServiceEndpointScope({
    required ServiceEndpointController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ServiceEndpointController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServiceEndpointScope>()?.notifier;
}

class ServiceEndpointForm extends StatefulWidget {
  const ServiceEndpointForm({
    required this.controller,
    this.onAdopted,
    this.authPresentation = false,
    super.key,
  });

  final ServiceEndpointController controller;
  final VoidCallback? onAdopted;
  final bool authPresentation;

  @override
  State<ServiceEndpointForm> createState() => _ServiceEndpointFormState();
}

class _ServiceEndpointFormState extends State<ServiceEndpointForm> {
  late final TextEditingController _address = TextEditingController(
    text: widget.controller.currentEndpoint().toString(),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.resetProbeFeedback();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.controller, builder: (context, _) => _fields(context));

  Widget _fields(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    if (!controller.canSwitch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(controller.currentEndpoint().toString()),
          const SizedBox(height: 12),
          Text(l10n.serviceSwitchWebFixed),
        ],
      );
    }
    final pending = controller.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.authPresentation) ...[
          Text(l10n.mockAuthServiceField, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _address,
          enabled: !controller.busy,
          onChanged: (_) => controller.addressChanged(),
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: widget.authPresentation ? null : l10n.mockSettingServiceAddress,
            hintText: widget.authPresentation ? l10n.mockAuthServicePlaceholder : null,
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.authPresentation) ...[
          const SizedBox(height: 8),
          Text(l10n.mockAuthServiceConstraint),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey(UiTestIds.settingsServiceProbe),
          onPressed: controller.busy ? null : () => controller.probeAddress(_address.text),
          child: Text(
            widget.authPresentation ? l10n.mockAuthProbe : l10n.mockSettingProbeConnection,
          ),
        ),
        if (!controller.busy &&
            controller.attempted &&
            controller.failure != null &&
            pending == null) ...[
          const SizedBox(height: 12),
          Text(switch (controller.failure) {
            'invalid' => l10n.mockSettingAddressInvalid,
            'adopt' => l10n.serviceSwitchFailed,
            _ => l10n.serviceSwitchProbeFailed,
          }),
        ],
        if (pending != null) ...[
          const SizedBox(height: 12),
          SelectableText(pending.endpoint.toString()),
          Text(l10n.serviceSwitchIdentity(pending.meta.instanceId, pending.meta.apiVersion)),
          Text(pending.meta.release),
          if (controller.signedIn()) ...[
            const SizedBox(height: 8),
            Text(l10n.serviceSwitchWarning),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey(UiTestIds.settingsServiceConfirm),
            onPressed: controller.busy
                ? null
                : () async {
                    final ok = await controller.adopt();
                    if (!ok || !context.mounted) return;
                    if (controller.revokeFailed) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(l10n.serviceSwitchRevokeFailed)));
                    }
                    widget.onAdopted?.call();
                  },
            child: Text(l10n.serviceSwitchConfirm),
          ),
        ],
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/api/responses.dart';
import '../../core/api/auth_models.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import 'auth_frame.dart';

class RecoveryRequestPage extends StatefulWidget {
  const RecoveryRequestPage({
    required this.onSubmit,
    this.onManual,
    this.emailChannel = true,
    this.admin = false,
    super.key,
  });

  final Future<void> Function(String email) onSubmit;
  final Future<void> Function(String email)? onManual;
  final bool emailChannel;
  final bool admin;

  @override
  State<RecoveryRequestPage> createState() => _RecoveryRequestPageState();
}

class _RecoveryRequestPageState extends State<RecoveryRequestPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit({bool manual = false}) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (manual) {
        await widget.onManual!(email);
      } else {
        await widget.onSubmit(email);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _safeError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AuthFrame(
      id: UiTestIds.recoveryRequestPage,
      title: strings.authRecoveryTitle,
      heroTitle: strings.authHeroRecovery,
      description: widget.emailChannel ? strings.authRecoveryHint : strings.authRecoveryManualHint,
      backLocation: widget.admin ? AppRoutes.adminLogin : AppRoutes.login,
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: strings.authEmail,
                child: Identified(
                  id: UiTestIds.recoveryRequestEmail,
                  merge: true,
                  child: TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: authInputDecoration(
                      context: context,
                      hint: 'name@example.com',
                      icon: Icons.person_outline,
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? strings.authRequired : null,
                    onFieldSubmitted: (_) => _submit(manual: !widget.emailChannel),
                  ),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 16), _FormError(message: _error!)],
              const SizedBox(height: 24),
              if (widget.emailChannel)
                Identified(
                  id: UiTestIds.recoveryRequestSubmit,
                  merge: true,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(
                        MediaQuery.sizeOf(context).width >= 760 ? 48 : 54,
                      ),
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: _busy ? null : () => _submit(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_busy ? strings.authRequestingRecovery : strings.authRequestRecovery),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ),
              if (widget.onManual != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.fromHeight(MediaQuery.sizeOf(context).width >= 760 ? 48 : 54),
                  ),
                  onPressed: _busy ? null : () => _submit(manual: true),
                  child: Text(strings.authRequestManualRecovery),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ActivationPage extends StatefulWidget {
  const ActivationPage({required this.onStatus, required this.onResend, super.key});
  final Future<ActivationStatus> Function() onStatus;
  final Future<void> Function(String email) onResend;

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await widget.onStatus();
      if (mounted) {
        setState(() {
          _state = status.state;
          _message = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = _safeError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _email.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.onResend(_email.text.trim());
      if (mounted) setState(() => _message = AppLocalizations.of(context).authResendReceived);
    } on Object catch (error) {
      if (mounted) setState(() => _message = _safeError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final title = switch (_state) {
      'pending_email' => strings.authPendingEmail,
      'pending_approval' => strings.authActivationApprovalTitle,
      'rejected' => strings.authApprovalRejected,
      'active' => strings.authVerified,
      _ => strings.authActivationProgressTitle,
    };
    final description = switch (_state) {
      'pending_email' => strings.authPendingEmailHint,
      'pending_approval' => strings.authPendingApproval,
      'rejected' || 'active' => strings.authBackToLogin,
      _ => strings.authActivationProgressHint,
    };
    return AuthFrame(
      id: UiTestIds.activationResendPage,
      title: title,
      description: description,
      backLocation: AppRoutes.login,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _check,
            child: Text(strings.authCheckActivation),
          ),
          if (_state == 'pending_email') ...[
            const SizedBox(height: 24),
            Identified(
              id: UiTestIds.activationResendEmail,
              merge: true,
              child: TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: strings.authEmail),
              ),
            ),
            const SizedBox(height: 12),
            Identified(
              id: UiTestIds.activationResendSubmit,
              merge: true,
              child: FilledButton(
                onPressed: _busy ? null : _resend,
                child: Text(strings.authResendVerification),
              ),
            ),
          ],
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
        ],
      ),
    );
  }
}

class AuthResultPage extends StatelessWidget {
  const AuthResultPage({
    required this.title,
    required this.message,
    this.backLocation = AppRoutes.login,
    this.actionLocation,
    this.actionLabel,
    this.actionId,
    super.key,
  });

  final String title;
  final String message;
  final String backLocation;
  final String? actionLocation;
  final String? actionLabel;
  final String? actionId;

  @override
  Widget build(BuildContext context) => AuthFrame(
    id: UiTestIds.authResultPage,
    title: title,
    description: message,
    backLocation: backLocation,
    child: actionLocation == null || actionLabel == null || actionId == null
        ? const SizedBox.shrink()
        : Identified(
            id: actionId!,
            merge: true,
            child: FilledButton(
              onPressed: () => context.go(actionLocation!),
              child: Text(actionLabel!),
            ),
          ),
  );
}

class AuthUnavailablePage extends StatelessWidget {
  const AuthUnavailablePage({required this.loading, required this.onRetry, super.key});
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AuthFrame(
      id: UiTestIds.authResultPage,
      title: loading ? strings.authLoading : strings.authUnavailable,
      description: loading ? strings.authLoading : strings.authServiceUnavailable,
      backLocation: AppRoutes.login,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : FilledButton(onPressed: onRetry, child: Text(strings.authCheckAgain)),
    );
  }
}

String _safeError(BuildContext context, Object error) {
  final strings = AppLocalizations.of(context);
  if (error is ApiFailure) return ApiCatalog.message(strings, error.code);
  return strings.authServiceUnavailable;
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Identified(
    id: UiTestIds.authFormError,
    child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/responses.dart';
import '../../core/api/auth_models.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import 'auth_frame.dart';

enum CredentialMode { clientLogin, register, adminLogin }

/// Identity forms never infer success from an HTTP acceptance response.
/// The action layer supplies the real server operation and destination.
class CredentialFormPage extends StatefulWidget {
  const CredentialFormPage({
    required this.mode,
    required this.onSubmit,
    this.registrationEnabled = false,
    this.passwordMinLength = 15,
    this.passwordMaxLength = 128,
    super.key,
  });

  final CredentialMode mode;
  final Future<void> Function(String email, String password) onSubmit;
  final bool registrationEnabled;
  final int passwordMinLength;
  final int passwordMaxLength;

  @override
  State<CredentialFormPage> createState() => _CredentialFormPageState();
}

class _CredentialFormPageState extends State<CredentialFormPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_email.text.trim(), _password.text);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _safeError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final register = widget.mode == CredentialMode.register;
    final admin = widget.mode == CredentialMode.adminLogin;
    final submitLabel = _busy
        ? register
              ? strings.authCreatingAccount
              : strings.authSigningIn
        : register
        ? strings.authCreateAccount
        : strings.authSignIn;
    final id = admin
        ? UiTestIds.adminLoginPage
        : register
        ? UiTestIds.registerPage
        : UiTestIds.loginPage;
    return AuthFrame(
      id: id,
      admin: admin,
      heroTitle: admin
          ? strings.authAdminHero
          : register
          ? strings.authHeroRegister
          : strings.authHeroLogin,
      showServiceLink: !admin && !register,
      showMobileDescription: false,
      backLocation: register ? '/login' : null,
      title: admin
          ? strings.authAdminLoginTitle
          : register
          ? strings.authRegisterTitle
          : strings.authLoginTitle,
      description: admin
          ? strings.authAdminLoginHint
          : register
          ? strings.authRegisterHint
          : strings.authLoginHint,
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: strings.authEmail,
                child: Identified(
                  id: admin
                      ? UiTestIds.adminLoginEmail
                      : register
                      ? UiTestIds.registerEmail
                      : UiTestIds.loginEmail,
                  merge: true,
                  child: TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: authInputDecoration(
                      hint: 'name@example.com',
                      icon: Icons.person_outline,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return strings.authRequired;
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
                        return strings.authInvalidEmail;
                      }
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AuthField(
                label: strings.authPassword,
                child: Identified(
                  id: admin
                      ? UiTestIds.adminLoginPassword
                      : register
                      ? UiTestIds.registerPassword
                      : UiTestIds.loginPassword,
                  merge: true,
                  child: TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_passwordVisible,
                    textInputAction: register ? TextInputAction.next : TextInputAction.done,
                    autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: authInputDecoration(
                      hint: strings.authPassword,
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        tooltip: _passwordVisible
                            ? strings.authHidePassword
                            : strings.authShowPassword,
                        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return strings.authRequired;
                      if (register &&
                          (value.runes.length < widget.passwordMinLength ||
                              value.runes.length > widget.passwordMaxLength)) {
                        return strings.authPasswordLength(
                          widget.passwordMinLength,
                          widget.passwordMaxLength,
                        );
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!register) unawaited(_submit());
                    },
                  ),
                ),
              ),
              if (register) ...[
                const SizedBox(height: 8),
                Text(
                  strings.authPasswordLength(widget.passwordMinLength, widget.passwordMaxLength),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              if (register) ...[
                const SizedBox(height: 18),
                AuthField(
                  label: strings.authConfirmPassword,
                  child: Identified(
                    id: UiTestIds.registerConfirm,
                    merge: true,
                    child: TextFormField(
                      controller: _confirmation,
                      enabled: !_busy,
                      obscureText: !_passwordVisible,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: authInputDecoration(
                        hint: strings.authConfirmPassword,
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          tooltip: _passwordVisible
                              ? strings.authHidePassword
                              : strings.authShowPassword,
                          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return strings.authRequired;
                        if (value != _password.text) return strings.authPasswordMismatch;
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[const SizedBox(height: 16), _FormError(message: _error!)],
              if (!register && !wide) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _RecoveryLink(admin: admin, busy: _busy),
                ),
              ],
              const SizedBox(height: 24),
              Identified(
                id: admin
                    ? UiTestIds.adminLoginSubmit
                    : register
                    ? UiTestIds.registerSubmit
                    : UiTestIds.loginSubmit,
                merge: true,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(wide ? 48 : 54),
                    visualDensity: VisualDensity.standard,
                  ),
                  onPressed: _busy ? null : _submit,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [Text(submitLabel), const Icon(Icons.arrow_forward, size: 18)],
                  ),
                ),
              ),
              if (!register) ...[
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    children: [
                      _RecoveryLink(admin: admin, busy: _busy),
                      const Spacer(),
                      if (!admin && widget.registrationEnabled)
                        Identified(
                          id: UiTestIds.loginRegisterLink,
                          merge: true,
                          child: TextButton(
                            onPressed: _busy ? null : () => context.go('/register'),
                            child: Text(strings.authCreateAccount),
                          ),
                        ),
                    ],
                  )
                else if (!admin && widget.registrationEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: Identified(
                        id: UiTestIds.loginRegisterLink,
                        merge: true,
                        child: TextButton(
                          onPressed: _busy ? null : () => context.go('/register'),
                          child: Text(strings.authCreateAccount),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryLink extends StatelessWidget {
  const _RecoveryLink({required this.admin, required this.busy});

  final bool admin;
  final bool busy;

  @override
  Widget build(BuildContext context) => Identified(
    id: UiTestIds.loginRecoveryLink,
    merge: true,
    child: TextButton(
      onPressed: busy ? null : () => context.go(admin ? '/recovery?from=admin' : '/recovery'),
      child: Text(AppLocalizations.of(context).authForgotPassword),
    ),
  );
}

class RecoveryRequestPage extends StatefulWidget {
  const RecoveryRequestPage({required this.onSubmit, this.admin = false, super.key});

  final Future<void> Function(String email) onSubmit;
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

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_email.text.trim());
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
      description: strings.authRecoveryHint,
      backLocation: widget.admin ? '/admin/login' : '/login',
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
                      hint: 'name@example.com',
                      icon: Icons.person_outline,
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? strings.authRequired : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 16), _FormError(message: _error!)],
              const SizedBox(height: 24),
              Identified(
                id: UiTestIds.recoveryRequestSubmit,
                merge: true,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(MediaQuery.sizeOf(context).width >= 760 ? 48 : 54),
                    visualDensity: VisualDensity.standard,
                  ),
                  onPressed: _busy ? null : _submit,
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
        setState(
          () => _message = status.active
              ? AppLocalizations.of(context).authVerified
              : AppLocalizations.of(context).authStillPending,
        );
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
    return AuthFrame(
      id: UiTestIds.activationResendPage,
      title: strings.authPendingEmail,
      description: strings.authPendingEmailHint,
      backLocation: '/login',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _check,
            child: Text(strings.authCheckActivation),
          ),
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
    this.backLocation = '/login',
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
      backLocation: '/login',
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

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/api/responses.dart';
import '../../core/auth/email_action_link.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import 'auth_frame.dart';

enum EmailActionKind { verify, resetPassword }

/// Consumes a fragment token only after explicit confirmation. On native, the
/// user may paste a complete, trusted email link; the token is never shown.
class EmailActionPage extends StatefulWidget {
  const EmailActionPage({
    required this.kind,
    required this.trustedActionBase,
    required this.onSubmit,
    this.passwordMinLength = 15,
    this.passwordMaxLength = 128,
    this.initialToken,
    super.key,
  });

  final EmailActionKind kind;
  final Uri trustedActionBase;
  final Future<void> Function(String token, String? newPassword) onSubmit;
  final String? initialToken;
  final int passwordMinLength;
  final int passwordMaxLength;

  @override
  State<EmailActionPage> createState() => _EmailActionPageState();
}

class _EmailActionPageState extends State<EmailActionPage> {
  final _form = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late String? _token;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _token = widget.initialToken;
  }

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final strings = AppLocalizations.of(context);
    final token =
        _token ??
        tokenFromPastedActionLink(
          pasted: _link.text,
          trustedBase: widget.trustedActionBase,
          actionPath: widget.kind == EmailActionKind.verify
              ? AppRoutes.verifyEmail
              : AppRoutes.resetPassword,
        );
    if (token == null) {
      setState(() => _error = strings.authInvalidActionLink);
      return;
    }
    // The source URL/link text is no longer needed after validation.
    _link.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        token,
        widget.kind == EmailActionKind.resetPassword ? _password.text : null,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiFailure
              ? ApiCatalog.message(strings, error.code)
              : strings.authServiceUnavailable;
          // A lost response may follow a successful one-time consumption. Do
          // not silently replay or keep the submitted new password in memory.
          _token = null;
          _password.clear();
          _confirmation.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final reset = widget.kind == EmailActionKind.resetPassword;
    return AuthFrame(
      id: reset ? UiTestIds.recoveryCompletePage : UiTestIds.verificationPage,
      title: reset ? strings.authResetTitle : strings.authVerifyTitle,
      description: reset ? strings.authResetHint : strings.authVerifyHint,
      backLocation: AppRoutes.login,
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_token == null) ...[
                Identified(
                  id: reset ? UiTestIds.recoveryCompleteToken : UiTestIds.verificationToken,
                  merge: true,
                  child: TextFormField(
                    controller: _link,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: reset ? strings.authRecoveryToken : strings.authVerificationToken,
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? strings.authRequired : null,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (reset) ...[
                Identified(
                  id: UiTestIds.recoveryCompletePassword,
                  merge: true,
                  child: TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: strings.authNewPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return strings.authRequired;
                      if (value.runes.length < widget.passwordMinLength ||
                          value.runes.length > widget.passwordMaxLength) {
                        return strings.authPasswordLength(
                          widget.passwordMinLength,
                          widget.passwordMaxLength,
                        );
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Identified(
                  id: UiTestIds.recoveryCompleteConfirm,
                  merge: true,
                  child: TextFormField(
                    controller: _confirmation,
                    enabled: !_busy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(labelText: strings.authConfirmPassword),
                    validator: (value) {
                      if (value == null || value.isEmpty) return strings.authRequired;
                      return value == _password.text ? null : strings.authPasswordMismatch;
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (_error != null) ...[
                Identified(
                  id: UiTestIds.authActionError,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Identified(
                id: reset ? UiTestIds.recoveryCompleteSubmit : UiTestIds.verificationSubmit,
                merge: true,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? reset
                              ? strings.authResettingPassword
                              : strings.authVerifying
                        : reset
                        ? strings.authCompleteRecovery
                        : strings.authVerify,
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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/responses.dart';
import '../../core/config/app_config.dart';
import '../settings/domain/service_endpoint.dart';
import '../settings/presentation/service_endpoint_form.dart';
import '../../generated/api_catalog.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';
import 'auth_frame.dart';

/// The confirmed service-connection surface backed by the real endpoint
/// controller. Web shows its fixed deployment and the same live health check.
class ServiceConnectionPage extends StatefulWidget {
  const ServiceConnectionPage({
    required this.config,
    required this.api,
    required this.onBack,
    this.controller,
    this.onAdopted,
    super.key,
  }) : preview = false;

  const ServiceConnectionPage.preview({required this.onBack, super.key})
    : config = null,
      api = null,
      controller = null,
      onAdopted = null,
      preview = true;

  final AppConfig? config;
  final ApiClient? api;
  final VoidCallback onBack;
  final ServiceEndpointController? controller;
  final VoidCallback? onAdopted;
  final bool preview;

  @override
  State<ServiceConnectionPage> createState() => _ServiceConnectionPageState();
}

class _ServiceConnectionPageState extends State<ServiceConnectionPage> {
  final _previewAddress = TextEditingController(text: 'https://haruka.example.test');
  bool _previewProbed = false;
  bool _previewValid = false;
  CancelToken? _healthToken;
  bool _healthy = false;
  String? _healthFailure;

  Future<void> _checkHealth() async {
    if (_healthToken != null) return;
    final token = CancelToken();
    setState(() {
      _healthToken = token;
      _healthy = false;
      _healthFailure = null;
    });
    try {
      await widget.api!.checkReadiness(cancelToken: token);
      if (mounted && identical(_healthToken, token)) setState(() => _healthy = true);
    } on ApiFailure catch (error) {
      if (mounted && identical(_healthToken, token)) {
        setState(() => _healthFailure = error.code);
      }
    } on Object {
      if (mounted && identical(_healthToken, token)) {
        setState(() => _healthFailure = 'NETWORK_UNAVAILABLE');
      }
    } finally {
      if (mounted && identical(_healthToken, token)) {
        setState(() => _healthToken = null);
      }
    }
  }

  @override
  void dispose() {
    _healthToken?.cancel();
    _previewAddress.dispose();
    super.dispose();
  }

  void _probePreview() {
    final parsed = parseServiceEndpoint(_previewAddress.text, allowDevelopmentHttp: false);
    setState(() {
      _previewProbed = true;
      _previewValid = parsed != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final endpoint = controller?.currentEndpoint() ?? widget.config?.apiBaseUrl;
    final instance = controller?.currentInstance() ?? widget.config?.instanceId;
    return Identified(
      id: UiTestIds.environmentPage,
      child: Scaffold(
        backgroundColor: HarukaColors.of(context).canvas,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: strings.authBackToLogin,
                          onPressed: widget.onBack,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          strings.mockAuthServiceConnectionTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 35),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: widget.preview
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    strings.mockAuthServiceField,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _previewAddress,
                                    keyboardType: TextInputType.url,
                                    decoration: InputDecoration(
                                      hintText: strings.mockAuthServicePlaceholder,
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (_) {
                                      if (_previewProbed) setState(() => _previewProbed = false);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(strings.mockAuthServiceConstraint),
                                  const SizedBox(height: 22),
                                  FilledButton(
                                    onPressed: _probePreview,
                                    child: Text(strings.mockAuthProbe),
                                  ),
                                ],
                              )
                            : controller == null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(strings.mockAuthServiceField),
                                  const SizedBox(height: 12),
                                  SelectableText(endpoint.toString()),
                                  const SizedBox(height: 8),
                                  Text(strings.serviceSwitchWebFixed),
                                ],
                              )
                            : ServiceEndpointForm(
                                controller: controller,
                                authPresentation: true,
                                onAdopted: widget.onAdopted,
                              ),
                      ),
                    ),
                    if (widget.preview && _previewProbed) ...[
                      const SizedBox(height: 20),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _previewValid
                                ? strings.mockSettingAddressValid
                                : strings.mockAuthServiceInvalid,
                          ),
                        ),
                      ),
                    ],
                    if (!widget.preview) ...[
                      const SizedBox(height: 20),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                strings.environment,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text('${strings.instanceLabel}: $instance'),
                              const SizedBox(height: 8),
                              SelectableText('${strings.apiLabel}: $endpoint'),
                              const SizedBox(height: 16),
                              Identified(
                                id: UiTestIds.checkConnection,
                                merge: true,
                                child: OutlinedButton(
                                  onPressed: _healthToken == null ? _checkHealth : null,
                                  child: Text(
                                    _healthToken == null
                                        ? strings.checkConnection
                                        : strings.checkingConnection,
                                  ),
                                ),
                              ),
                              if (_healthy || _healthFailure != null) ...[
                                const SizedBox(height: 12),
                                Identified(
                                  id: UiTestIds.connectionStatus,
                                  child: Text(
                                    _healthy
                                        ? strings.connectionReady
                                        : ApiCatalog.message(strings, _healthFailure!),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The confirmed compact/wide mock composition, now backed by real identity actions.
/// Route owners decide destinations after the server operation and action epoch check.
class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.onLogin,
    required this.onOpenRecovery,
    required this.onOpenRegistration,
    required this.onOpenService,
    required this.registrationEnabled,
    required this.recoveryEnabled,
    this.admin = false,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final VoidCallback onOpenRecovery;
  final VoidCallback onOpenRegistration;
  final VoidCallback onOpenService;
  final bool registrationEnabled;
  final bool recoveryEnabled;
  final bool admin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _visible = false;
  bool _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _actionError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final strings = AppLocalizations.of(context);
    final email = _email.text.trim();
    final emailError = _emailErrorFor(email, strings);
    final passwordError = _password.text.isEmpty ? strings.authRequired : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _actionError = null;
    });
    if (emailError != null) {
      _emailFocus.requestFocus();
      return;
    }
    if (passwordError != null) {
      _passwordFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onLogin(email, _password.text);
    } on Object catch (error) {
      if (mounted) setState(() => _actionError = _safeAuthError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return AuthFrame(
      id: widget.admin ? UiTestIds.adminLoginPage : UiTestIds.loginPage,
      title: widget.admin
          ? strings.authAdminLoginTitle
          : wide
          ? strings.mockAuthDesktopLoginTitle
          : strings.authLoginTitle,
      heroTitle: widget.admin ? strings.authAdminHero : strings.authHeroLogin,
      description: strings.authLoginHint,
      showMobileDescription: false,
      showDesktopDescription: false,
      admin: widget.admin,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              label: wide ? strings.mockAuthDesktopEmail : strings.authEmail,
              child: Identified(
                id: widget.admin ? UiTestIds.adminLoginEmail : UiTestIds.loginEmail,
                merge: true,
                child: TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  decoration: authInputDecoration(
                    context: context,
                    hint: wide
                        ? strings.mockAuthDesktopEmailPlaceholder
                        : strings.mockAuthMobileEmailPlaceholder,
                    icon: Icons.person_outline,
                  ).copyWith(errorText: _emailError),
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                ),
              ),
            ),
            SizedBox(height: wide ? 18 : 21),
            AuthField(
              label: strings.authPassword,
              child: Identified(
                id: widget.admin ? UiTestIds.adminLoginPassword : UiTestIds.loginPassword,
                merge: true,
                child: TextField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !_busy,
                  obscureText: !_visible,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: authInputDecoration(
                    context: context,
                    hint: wide
                        ? strings.mockAuthDesktopPasswordPlaceholder
                        : strings.mockAuthMobilePasswordPlaceholder,
                    icon: Icons.lock_outline,
                    suffix: wide
                        ? null
                        : IconButton(
                            tooltip: _visible ? strings.authHidePassword : strings.authShowPassword,
                            onPressed: _busy ? null : () => setState(() => _visible = !_visible),
                            icon: Icon(
                              _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            ),
                          ),
                  ).copyWith(errorText: _passwordError),
                  onChanged: (_) {
                    if (_passwordError != null) setState(() => _passwordError = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            if (!wide && widget.recoveryEnabled) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Identified(
                  id: UiTestIds.loginRecoveryLink,
                  merge: true,
                  child: TextButton(
                    onPressed: _busy ? null : widget.onOpenRecovery,
                    child: Text(strings.authForgotPassword),
                  ),
                ),
              ),
            ],
            if (_actionError != null) ...[
              const SizedBox(height: 12),
              Text(_actionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            SizedBox(height: wide ? 16 : 10),
            Identified(
              id: widget.admin ? UiTestIds.adminLoginSubmit : UiTestIds.loginSubmit,
              merge: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(wide ? 48 : 54),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy
                      ? strings.authSigningIn
                      : wide && !widget.admin
                      ? strings.mockAuthEnterWorkspace
                      : strings.authSignIn,
                ),
              ),
            ),
            if (wide) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.registrationEnabled && !widget.admin)
                    Identified(
                      id: UiTestIds.loginRegisterLink,
                      merge: true,
                      child: TextButton(
                        onPressed: _busy ? null : widget.onOpenRegistration,
                        child: Text(strings.authCreateAccount),
                      ),
                    ),
                  if (widget.recoveryEnabled)
                    Identified(
                      id: UiTestIds.loginRecoveryLink,
                      merge: true,
                      child: TextButton(
                        onPressed: _busy ? null : widget.onOpenRecovery,
                        child: Text(strings.authForgotPassword),
                      ),
                    ),
                  if (!widget.admin)
                    TextButton(
                      onPressed: _busy ? null : widget.onOpenService,
                      child: Text(strings.mockAuthServiceTitle),
                    ),
                ],
              ),
            ] else ...[
              if (widget.registrationEnabled && !widget.admin) ...[
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(strings.mockAuthNoAccount),
                    Identified(
                      id: UiTestIds.loginRegisterLink,
                      merge: true,
                      child: TextButton(
                        onPressed: _busy ? null : widget.onOpenRegistration,
                        child: Text(strings.authCreateAccount),
                      ),
                    ),
                  ],
                ),
              ],
              if (!widget.admin) ...[
                const SizedBox(height: 12),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_outlined, size: 20),
                  title: Text(strings.mockAuthServiceTitle),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: _busy ? null : widget.onOpenService,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({
    required this.onRegister,
    required this.onBackToLogin,
    required this.passwordMinLength,
    required this.passwordMaxLength,
    this.approvalRequired = false,
    super.key,
  });

  final Future<void> Function(String email, String password) onRegister;
  final VoidCallback onBackToLogin;
  final int passwordMinLength;
  final int passwordMaxLength;
  final bool approvalRequired;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _actionError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final strings = AppLocalizations.of(context);
    final email = _email.text.trim();
    final emailError = _emailErrorFor(email, strings);
    final passwordLength = _password.text.runes.length;
    final passwordError = _password.text.isEmpty
        ? strings.authRequired
        : passwordLength < widget.passwordMinLength || passwordLength > widget.passwordMaxLength
        ? strings.authPasswordLength(widget.passwordMinLength, widget.passwordMaxLength)
        : null;
    final confirmError = _confirm.text.isEmpty
        ? strings.authRequired
        : _confirm.text != _password.text
        ? strings.authPasswordMismatch
        : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _actionError = null;
    });
    if (emailError != null) {
      _emailFocus.requestFocus();
      return;
    }
    if (passwordError != null) {
      _passwordFocus.requestFocus();
      return;
    }
    if (confirmError != null) {
      _confirmFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onRegister(email, _password.text);
    } on Object catch (error) {
      if (mounted) setState(() => _actionError = _safeAuthError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return AuthFrame(
      id: UiTestIds.registerPage,
      title: wide ? strings.mockAuthDesktopRegisterTitle : strings.authRegisterTitle,
      heroTitle: strings.authHeroRegister,
      description: strings.authRegisterHint,
      showMobileDescription: false,
      showDesktopDescription: false,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.approvalRequired) ...[
              Text(strings.authApprovalRequired),
              const SizedBox(height: 16),
            ],
            AuthField(
              label: wide ? strings.mockAuthDesktopEmail : strings.authEmail,
              child: Identified(
                id: UiTestIds.registerEmail,
                merge: true,
                child: TextField(
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: authInputDecoration(
                    context: context,
                    hint: wide
                        ? strings.mockAuthDesktopEmailPlaceholder
                        : strings.mockAuthMobileEmailPlaceholder,
                    icon: Icons.person_outline,
                  ).copyWith(errorText: _emailError),
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                ),
              ),
            ),
            SizedBox(height: wide ? 18 : 21),
            AuthField(
              label: strings.authPassword,
              child: Identified(
                id: UiTestIds.registerPassword,
                merge: true,
                child: TextField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !_busy,
                  obscureText: !_passwordVisible,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: authInputDecoration(
                    context: context,
                    hint: wide
                        ? strings.mockAuthDesktopPasswordPlaceholder
                        : strings.mockAuthSetPassword,
                    icon: Icons.lock_outline,
                    suffix: wide
                        ? null
                        : IconButton(
                            tooltip: _passwordVisible
                                ? strings.authHidePassword
                                : strings.authShowPassword,
                            onPressed: _busy
                                ? null
                                : () => setState(() => _passwordVisible = !_passwordVisible),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                  ).copyWith(errorText: _passwordError),
                  onChanged: (_) {
                    if (_passwordError != null) setState(() => _passwordError = null);
                  },
                ),
              ),
            ),
            if (!wide) ...[
              const SizedBox(height: 7),
              Text(
                strings.authPasswordLength(widget.passwordMinLength, widget.passwordMaxLength),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            SizedBox(height: wide ? 18 : 22),
            AuthField(
              label: strings.authConfirmPassword,
              child: Identified(
                id: UiTestIds.registerConfirm,
                merge: true,
                child: TextField(
                  controller: _confirm,
                  focusNode: _confirmFocus,
                  enabled: !_busy,
                  obscureText: !_confirmVisible,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: authInputDecoration(
                    context: context,
                    hint: wide
                        ? strings.mockAuthDesktopConfirmPlaceholder
                        : strings.mockAuthConfirmPasswordPlaceholder,
                    icon: Icons.lock_outline,
                    suffix: wide
                        ? null
                        : IconButton(
                            tooltip: _confirmVisible
                                ? strings.authHidePassword
                                : strings.authShowPassword,
                            onPressed: _busy
                                ? null
                                : () => setState(() => _confirmVisible = !_confirmVisible),
                            icon: Icon(
                              _confirmVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                  ).copyWith(errorText: _confirmError),
                  onChanged: (_) {
                    if (_confirmError != null) setState(() => _confirmError = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 12),
              Text(_actionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            SizedBox(height: wide ? 16 : 18),
            Identified(
              id: UiTestIds.registerSubmit,
              merge: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(wide ? 48 : 54),
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? strings.authCreatingAccount : strings.authCreateAccount),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: wide ? Alignment.centerLeft : Alignment.center,
              child: TextButton.icon(
                onPressed: _busy ? null : widget.onBackToLogin,
                icon: const Icon(Icons.chevron_left),
                label: Text(strings.authBackToLogin),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _emailErrorFor(String value, AppLocalizations strings) {
  if (value.isEmpty) return strings.authRequired;
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return strings.authInvalidEmail;
  return null;
}

String _safeAuthError(BuildContext context, Object error) {
  final strings = AppLocalizations.of(context);
  if (error is ApiFailure) return ApiCatalog.message(strings, error.code);
  return strings.authServiceUnavailable;
}

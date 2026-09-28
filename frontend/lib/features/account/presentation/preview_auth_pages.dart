import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:haruka/app/routes.dart';
import 'package:haruka/app/theme.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

/// The preview accepts fictional input only. It never creates a real session.
class PreviewLoginPage extends StatefulWidget {
  const PreviewLoginPage({super.key});

  @override
  State<PreviewLoginPage> createState() => _PreviewLoginPageState();
}

enum _LoginStep { login, recovery, recoveryReceived, service }

class _PreviewLoginPageState extends State<PreviewLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final service = TextEditingController(text: 'https://haruka.example.test');
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();
  _LoginStep step = _LoginStep.login;
  String? emailError;
  String? passwordError;
  String? serviceError;
  bool passwordVisible = false;
  bool probeComplete = false;

  void clearEmailError() => setState(() => emailError = null);
  void clearPasswordError() => setState(() => passwordError = null);
  void togglePassword() => setState(() => passwordVisible = !passwordVisible);

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    service.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void showStep(_LoginStep next) => setState(() {
    step = next;
    emailError = null;
    passwordError = null;
    serviceError = null;
    probeComplete = false;
  });

  void submitLogin() {
    final l10n = AppLocalizations.of(context);
    final nextEmailError = _validateEmail(email.text, l10n);
    final nextPasswordError = password.text.isEmpty ? l10n.mockAuthPasswordRequired : null;
    setState(() {
      emailError = nextEmailError;
      passwordError = nextPasswordError;
    });
    if (nextEmailError != null) {
      emailFocus.requestFocus();
    } else if (nextPasswordError != null) {
      passwordFocus.requestFocus();
    } else {
      context.go(AppRoutes.mockLibrary);
    }
  }

  void submitRecovery() {
    final error = _validateEmail(email.text, AppLocalizations.of(context));
    setState(() => emailError = error);
    if (error == null) {
      showStep(_LoginStep.recoveryReceived);
    } else {
      emailFocus.requestFocus();
    }
  }

  void probeService() {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.tryParse(service.text.trim());
    final valid =
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
    setState(() {
      serviceError = valid ? null : l10n.mockAuthServiceInvalid;
      probeComplete = valid;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth < 700 ? _MobileLoginView(state: this) : _DesktopLoginView(state: this),
  );
}

class PreviewRegisterPage extends StatefulWidget {
  const PreviewRegisterPage({super.key});

  @override
  State<PreviewRegisterPage> createState() => _PreviewRegisterPageState();
}

class _PreviewRegisterPageState extends State<PreviewRegisterPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();
  final confirmFocus = FocusNode();
  String? emailError;
  String? passwordError;
  String? confirmError;
  bool passwordVisible = false;
  bool confirmVisible = false;
  bool accepted = false;

  void clearEmailError() => setState(() => emailError = null);
  void clearPasswordError() => setState(() => passwordError = null);
  void clearConfirmError() => setState(() => confirmError = null);
  void togglePassword() => setState(() => passwordVisible = !passwordVisible);
  void toggleConfirm() => setState(() => confirmVisible = !confirmVisible);

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    confirmFocus.dispose();
    super.dispose();
  }

  void submit() {
    final l10n = AppLocalizations.of(context);
    final nextEmailError = _validateEmail(email.text, l10n);
    final nextPasswordError = password.text.isEmpty
        ? l10n.mockAuthPasswordRequired
        : password.text.runes.length < 15 || password.text.runes.length > 128
        ? l10n.mockAuthPasswordLength
        : null;
    final nextConfirmError = confirmPassword.text.isEmpty
        ? l10n.mockAuthConfirmRequired
        : password.text != confirmPassword.text
        ? l10n.authPasswordMismatch
        : null;
    setState(() {
      emailError = nextEmailError;
      passwordError = nextPasswordError;
      confirmError = nextConfirmError;
      accepted = nextEmailError == null && nextPasswordError == null && nextConfirmError == null;
    });
    if (nextEmailError != null) {
      emailFocus.requestFocus();
    } else if (nextPasswordError != null) {
      passwordFocus.requestFocus();
    } else if (nextConfirmError != null) {
      confirmFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 700
        ? _MobileRegisterView(state: this)
        : _DesktopRegisterView(state: this),
  );
}

String? _validateEmail(String value, AppLocalizations l10n) {
  if (value.trim().isEmpty) return l10n.mockAuthEmailRequired;
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
    return l10n.authInvalidEmail;
  }
  return null;
}

class _MobileAuthFrame extends StatelessWidget {
  const _MobileAuthFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.result = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: roles.canvas,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ColoredBox(
            color: roles.canvas,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            'h',
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 28,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l10n.mockAuthBrand,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    if (result) ...[
                      const SizedBox(height: 48),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 60,
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: roles.selected,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.check, size: 30, color: scheme.primary),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ] else ...[
                      const SizedBox(height: 34),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 28,
                          height: 5,
                          decoration: BoxDecoration(
                            color: roles.signal,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 29,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        subtitle!,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 28),
                    child,
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

class _MobileLoginView extends StatelessWidget {
  const _MobileLoginView({required this.state});
  final _PreviewLoginPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (state.step == _LoginStep.recoveryReceived) {
      return _MobileAuthFrame(
        title: l10n.mockAuthRecoveryReceived,
        result: true,
        child: _MobileResult(
          message: null,
          button: l10n.authBackToLogin,
          onPressed: () => state.showStep(_LoginStep.login),
        ),
      );
    }
    if (state.step == _LoginStep.service) {
      return _MobileServiceView(state: state);
    }
    if (state.step == _LoginStep.recovery) {
      return _MobileAuthFrame(
        title: l10n.authRecoveryTitle,
        subtitle: l10n.mockAuthRecoveryIntro,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileField(
              label: l10n.authEmail,
              hint: l10n.mockAuthMobileEmailPlaceholder,
              controller: state.email,
              focusNode: state.emailFocus,
              error: state.emailError,
              icon: Icons.person_outline,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => state.clearEmailError(),
            ),
            const SizedBox(height: 18),
            _PrimaryAction(label: l10n.authRequestRecovery, onPressed: state.submitRecovery),
            const SizedBox(height: 22),
            _TextAction(
              label: l10n.authBackToLogin,
              icon: Icons.chevron_left,
              onPressed: () => state.showStep(_LoginStep.login),
            ),
          ],
        ),
      );
    }
    return _MobileAuthFrame(
      title: l10n.authLoginTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileField(
            label: l10n.authEmail,
            hint: l10n.mockAuthMobileEmailPlaceholder,
            controller: state.email,
            focusNode: state.emailFocus,
            error: state.emailError,
            icon: Icons.person_outline,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => state.clearEmailError(),
          ),
          const SizedBox(height: 21),
          _MobileField(
            label: l10n.authPassword,
            hint: l10n.mockAuthMobilePasswordPlaceholder,
            controller: state.password,
            focusNode: state.passwordFocus,
            error: state.passwordError,
            icon: Icons.lock_outline,
            obscure: !state.passwordVisible,
            toggleLabel: state.passwordVisible ? l10n.authHidePassword : l10n.authShowPassword,
            onToggle: state.togglePassword,
            onChanged: (_) => state.clearPasswordError(),
            onSubmitted: (_) => state.submitLogin(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => state.showStep(_LoginStep.recovery),
              child: Text(l10n.authForgotPassword),
            ),
          ),
          const SizedBox(height: 10),
          _PrimaryAction(label: l10n.authSignIn, onPressed: state.submitLogin),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.mockAuthNoAccount,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.mockRegister),
                child: Text(l10n.authCreateAccount),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: scheme.outline),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_outlined, size: 20),
              title: Text(l10n.mockAuthServiceTitle),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => state.showStep(_LoginStep.service),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileServiceView extends StatelessWidget {
  const _MobileServiceView({required this.state});

  final _PreviewLoginPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Scaffold(
      backgroundColor: roles.canvas,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: l10n.authBackToLogin,
                        onPressed: () => state.showStep(_LoginStep.login),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        l10n.mockAuthServiceConnectionTitle,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 35),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MobileField(
                          label: l10n.mockAuthServiceField,
                          hint: l10n.mockAuthServicePlaceholder,
                          controller: state.service,
                          error: state.serviceError,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.mockAuthServiceConstraint,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                        const SizedBox(height: 22),
                        _PrimaryAction(label: l10n.mockAuthProbe, onPressed: state.probeService),
                      ],
                    ),
                  ),
                  if (state.probeComplete) ...[
                    const SizedBox(height: 20),
                    _InfoPanel(text: l10n.mockAuthProbeComplete),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileRegisterView extends StatelessWidget {
  const _MobileRegisterView({required this.state});
  final _PreviewRegisterPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (state.accepted) {
      return _MobileAuthFrame(
        title: l10n.authRegisterReceived,
        result: true,
        child: _MobileResult(
          message: null,
          button: l10n.authBackToLogin,
          onPressed: () => context.go(AppRoutes.mockLogin),
        ),
      );
    }
    return _MobileAuthFrame(
      title: l10n.authRegisterTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MobileField(
            label: l10n.authEmail,
            hint: l10n.mockAuthMobileEmailPlaceholder,
            controller: state.email,
            focusNode: state.emailFocus,
            error: state.emailError,
            icon: Icons.person_outline,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => state.clearEmailError(),
          ),
          const SizedBox(height: 21),
          _MobileField(
            label: l10n.authPassword,
            hint: l10n.mockAuthSetPassword,
            controller: state.password,
            focusNode: state.passwordFocus,
            error: state.passwordError,
            icon: Icons.lock_outline,
            obscure: !state.passwordVisible,
            toggleLabel: state.passwordVisible ? l10n.authHidePassword : l10n.authShowPassword,
            onToggle: state.togglePassword,
            onChanged: (_) => state.clearPasswordError(),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.mockAuthPasswordLengthHint,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 22),
          _MobileField(
            label: l10n.authConfirmPassword,
            hint: l10n.mockAuthConfirmPasswordPlaceholder,
            controller: state.confirmPassword,
            focusNode: state.confirmFocus,
            error: state.confirmError,
            icon: Icons.lock_outline,
            obscure: !state.confirmVisible,
            toggleLabel: state.confirmVisible
                ? l10n.mockAuthHideConfirmPassword
                : l10n.mockAuthShowConfirmPassword,
            onToggle: state.toggleConfirm,
            onChanged: (_) => state.clearConfirmError(),
            onSubmitted: (_) => state.submit(),
          ),
          const SizedBox(height: 18),
          _PrimaryAction(label: l10n.authCreateAccount, onPressed: state.submit),
          const SizedBox(height: 22),
          _TextAction(
            label: l10n.authBackToLogin,
            icon: Icons.chevron_left,
            onPressed: () => context.go(AppRoutes.mockLogin),
          ),
        ],
      ),
    );
  }
}

class _MobileResult extends StatelessWidget {
  const _MobileResult({required this.message, required this.button, required this.onPressed});
  final String? message;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 6),
      if (message != null) ...[
        Text(
          message!,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
        ),
        const SizedBox(height: 28),
      ],
      _PrimaryAction(label: button, onPressed: onPressed),
    ],
  );
}

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.label,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.error,
    this.icon,
    this.obscure = false,
    this.toggleLabel,
    this.onToggle,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? error;
  final IconData? icon;
  final bool obscure;
  final String? toggleLabel;
  final VoidCallback? onToggle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: onToggle == null
                ? null
                : IconButton(
                    tooltip: toggleLabel,
                    onPressed: onToggle,
                    icon: Icon(
                      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                  ),
            filled: true,
            fillColor: scheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 5),
          Text(error!, style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ],
    );
  }
}

class _DesktopAuthFrame extends StatelessWidget {
  const _DesktopAuthFrame({required this.hero, required this.child});
  final String hero;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final roles = HarukaColors.of(context);
    return Scaffold(
      backgroundColor: roles.canvas,
      body: Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: scheme.primary,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(72, 72, 72, 72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.onPrimary.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'h',
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.mockAuthBrand,
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 5,
                          decoration: BoxDecoration(
                            color: roles.signal,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.mockAuthClearSignal,
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      hero,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 58,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 570),
                      child: Text(
                        l10n.mockAuthHeroDescription,
                        style: TextStyle(
                          color: scheme.onPrimary.withValues(alpha: .9),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLoginView extends StatelessWidget {
  const _DesktopLoginView({required this.state});
  final _PreviewLoginPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.step == _LoginStep.recoveryReceived) {
      return _DesktopAuthFrame(
        hero: l10n.mockAuthRecoveryReceived,
        child: _DesktopResult(
          title: l10n.mockAuthNextStep,
          message: null,
          button: l10n.mockAuthBackToLoginDemo,
          onPressed: () => state.showStep(_LoginStep.login),
        ),
      );
    }
    if (state.step == _LoginStep.recovery) {
      return _DesktopAuthFrame(
        hero: l10n.authHeroRecovery,
        child: _DesktopForm(
          title: l10n.mockAuthRecoverAccount,
          fields: [
            _DesktopField(
              label: l10n.mockAuthDesktopEmail,
              hint: l10n.mockAuthDesktopEmailPlaceholder,
              controller: state.email,
              focusNode: state.emailFocus,
              error: state.emailError,
              onChanged: (_) => state.clearEmailError(),
            ),
          ],
          action: l10n.mockAuthViewResult,
          onSubmit: state.submitRecovery,
          links: [
            TextButton(
              onPressed: () => state.showStep(_LoginStep.login),
              child: Text(l10n.authBackToLogin),
            ),
          ],
        ),
      );
    }
    if (state.step == _LoginStep.service) {
      return _DesktopAuthFrame(
        hero: l10n.mockAuthServiceTitle,
        child: _DesktopForm(
          title: l10n.mockAuthServiceField,
          fields: [
            _DesktopField(
              label: l10n.mockAuthServiceField,
              hint: l10n.mockAuthServicePlaceholder,
              controller: state.service,
              error: state.serviceError,
            ),
            if (state.probeComplete) ...[
              const SizedBox(height: 16),
              _InfoPanel(text: l10n.mockAuthProbeComplete),
            ],
          ],
          action: l10n.mockAuthProbe,
          onSubmit: state.probeService,
          links: [
            TextButton(
              onPressed: () => state.showStep(_LoginStep.login),
              child: Text(l10n.authBackToLogin),
            ),
          ],
        ),
      );
    }
    return _DesktopAuthFrame(
      hero: l10n.authHeroLogin,
      child: _DesktopForm(
        title: l10n.mockAuthDesktopLoginTitle,
        fields: [
          _DesktopField(
            label: l10n.mockAuthDesktopEmail,
            hint: l10n.mockAuthDesktopEmailPlaceholder,
            controller: state.email,
            focusNode: state.emailFocus,
            error: state.emailError,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => state.clearEmailError(),
          ),
          const SizedBox(height: 18),
          _DesktopField(
            label: l10n.authPassword,
            hint: l10n.mockAuthDesktopPasswordPlaceholder,
            controller: state.password,
            focusNode: state.passwordFocus,
            error: state.passwordError,
            obscure: true,
            onChanged: (_) => state.clearPasswordError(),
            onSubmitted: (_) => state.submitLogin(),
          ),
        ],
        action: l10n.mockAuthEnterWorkspace,
        onSubmit: state.submitLogin,
        links: [
          TextButton(
            onPressed: () => context.go(AppRoutes.mockRegister),
            child: Text(l10n.authCreateAccount),
          ),
          TextButton(
            onPressed: () => state.showStep(_LoginStep.recovery),
            child: Text(l10n.mockAuthForgotPasswordDesktop),
          ),
        ],
      ),
    );
  }
}

class _DesktopRegisterView extends StatelessWidget {
  const _DesktopRegisterView({required this.state});
  final _PreviewRegisterPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.accepted) {
      return _DesktopAuthFrame(
        hero: l10n.mockAuthRegistrationAcceptedDesktop,
        child: _DesktopResult(
          title: l10n.mockAuthNextStep,
          message: null,
          button: l10n.mockAuthBackToLoginDemo,
          onPressed: () => context.go(AppRoutes.mockLogin),
        ),
      );
    }
    return _DesktopAuthFrame(
      hero: l10n.authHeroRegister,
      child: _DesktopForm(
        title: l10n.mockAuthDesktopRegisterTitle,
        fields: [
          _DesktopField(
            label: l10n.mockAuthDesktopEmail,
            hint: l10n.mockAuthDesktopEmailPlaceholder,
            controller: state.email,
            focusNode: state.emailFocus,
            error: state.emailError,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => state.clearEmailError(),
          ),
          const SizedBox(height: 18),
          _DesktopField(
            label: l10n.authPassword,
            hint: l10n.mockAuthDesktopPasswordPlaceholder,
            controller: state.password,
            focusNode: state.passwordFocus,
            error: state.passwordError,
            obscure: true,
            onChanged: (_) => state.clearPasswordError(),
          ),
          const SizedBox(height: 18),
          _DesktopField(
            label: l10n.authConfirmPassword,
            hint: l10n.mockAuthDesktopConfirmPlaceholder,
            controller: state.confirmPassword,
            focusNode: state.confirmFocus,
            error: state.confirmError,
            obscure: true,
            onChanged: (_) => state.clearConfirmError(),
            onSubmitted: (_) => state.submit(),
          ),
        ],
        action: l10n.mockAuthDesktopSubmitRegister,
        onSubmit: state.submit,
        links: [
          TextButton(
            onPressed: () => context.go(AppRoutes.mockLogin),
            child: Text(l10n.authBackToLogin),
          ),
        ],
      ),
    );
  }
}

class _DesktopForm extends StatelessWidget {
  const _DesktopForm({
    required this.title,
    required this.fields,
    required this.action,
    required this.onSubmit,
    required this.links,
  });
  final String title;
  final List<Widget> fields;
  final String action;
  final VoidCallback onSubmit;
  final List<Widget> links;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 5,
              decoration: BoxDecoration(
                color: HarukaColors.of(context).signal,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.mockAuthPersonalWorkspace,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 30),
        ),
        const SizedBox(height: 32),
        ...fields,
        const SizedBox(height: 16),
        _PrimaryAction(label: action, onPressed: onSubmit, showArrow: false),
        const SizedBox(height: 18),
        Wrap(spacing: 12, children: links),
      ],
    );
  }
}

class _DesktopField extends StatelessWidget {
  const _DesktopField({
    required this.label,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? error;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: scheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: scheme.outline),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 5),
          Text(error!, style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ],
    );
  }
}

class _DesktopResult extends StatelessWidget {
  const _DesktopResult({
    required this.title,
    required this.message,
    required this.button,
    required this.onPressed,
  });
  final String title;
  final String? message;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(color: scheme.onSurface, fontSize: 30, fontWeight: FontWeight.w800),
        ),
        if (message != null) ...[
          const SizedBox(height: 20),
          Text(message!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
        ],
        const SizedBox(height: 18),
        _PrimaryAction(label: button, onPressed: onPressed, showArrow: false),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed, this.showArrow = true});
  final String label;
  final VoidCallback onPressed;
  final bool showArrow;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (showArrow) ...[const SizedBox(width: 10), const Icon(Icons.arrow_forward, size: 18)],
        ],
      ),
    ),
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label)),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HarukaColors.of(context).selected,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

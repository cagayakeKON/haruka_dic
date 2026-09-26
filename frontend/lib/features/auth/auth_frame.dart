import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../generated/ui_test_ids.dart';
import '../../shared/identified.dart';

/// The compact and wide presentations share the action child and its owning state.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    required this.id,
    required this.title,
    required this.description,
    required this.child,
    this.backLocation,
    this.admin = false,
    this.heroTitle,
    this.showServiceLink = false,
    this.showMobileDescription = true,
    super.key,
  });

  final String id;
  final String title;
  final String description;
  final Widget child;
  final String? backLocation;
  final bool admin;
  final String? heroTitle;
  final bool showServiceLink;
  final bool showMobileDescription;

  @override
  Widget build(BuildContext context) => Identified(
    id: id,
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => viewport.maxWidth >= 760
              ? _DesktopAuthFrame(
                  title: title,
                  description: description,
                  backLocation: backLocation,
                  admin: admin,
                  heroTitle: heroTitle,
                  child: child,
                )
              : _MobileAuthFrame(
                  title: title,
                  description: description,
                  backLocation: backLocation,
                  showServiceLink: showServiceLink,
                  showDescription: showMobileDescription,
                  child: child,
                ),
        ),
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.onBlue});

  final bool onBlue;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onBlue ? const Color(0xff4675f2) : const Color(0xff2457ed),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Text(
          'h',
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'haruka',
          style: TextStyle(
            fontSize: 23,
            letterSpacing: -0.9,
            fontWeight: FontWeight.w800,
            color: onBlue ? Colors.white : const Color(0xff152b42),
          ),
        ),
      ),
    ],
  );
}

class _Signal extends StatelessWidget {
  const _Signal({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 23,
        height: 6,
        decoration: BoxDecoration(
          color: const Color(0xffd8f36a),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      if (label != null) ...[
        const SizedBox(width: 9),
        Text(label!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    ],
  );
}

class _MobileAuthFrame extends StatelessWidget {
  const _MobileAuthFrame({
    required this.title,
    required this.description,
    required this.backLocation,
    required this.showServiceLink,
    required this.showDescription,
    required this.child,
  });

  final String title;
  final String description;
  final String? backLocation;
  final bool showServiceLink;
  final bool showDescription;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(23, 23, 23, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(alignment: Alignment.centerLeft, child: _BrandMark(onBlue: false)),
            const SizedBox(height: 35),
            const Align(alignment: Alignment.centerLeft, child: _Signal()),
            const SizedBox(height: 17),
            _AuthHeading(title: title, description: description, showDescription: showDescription),
            const SizedBox(height: 28),
            child,
            if (backLocation != null) _BackToLogin(backLocation: backLocation!),
            if (showServiceLink) ...[
              const SizedBox(height: 26),
              const Divider(),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language),
                title: Text(AppLocalizations.of(context).apiLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/environment'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DesktopAuthFrame extends StatelessWidget {
  const _DesktopAuthFrame({
    required this.title,
    required this.description,
    required this.backLocation,
    required this.admin,
    required this.heroTitle,
    required this.child,
  });

  final String title;
  final String description;
  final String? backLocation;
  final bool admin;
  final String? heroTitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ColoredBox(
          color: const Color(0xff2457ed),
          child: LayoutBuilder(
            builder: (context, size) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(86, 84, 48, 84),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _BrandMark(onBlue: true),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefaultTextStyle(
                            style: const TextStyle(color: Colors.white),
                            child: _Signal(label: admin ? 'ADMIN / HARUKA' : 'CLEAR SIGNAL'),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            heroTitle ??
                                (admin
                                    ? AppLocalizations.of(context).authAdminLoginTitle
                                    : AppLocalizations.of(context).authLoginTitle),
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            AppLocalizations.of(context).authBrandLine,
                            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                          ),
                        ],
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, size) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _Signal(
                            label: admin ? AppLocalizations.of(context).authAdminEntry : null,
                          ),
                        ),
                        const SizedBox(height: 17),
                        _AuthHeading(title: title, description: description),
                        const SizedBox(height: 28),
                        child,
                        if (backLocation != null) _BackToLogin(backLocation: backLocation!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _AuthHeading extends StatelessWidget {
  const _AuthHeading({required this.title, required this.description, this.showDescription = true});

  final String title;
  final String description;
  final bool showDescription;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      if (showDescription) ...[
        const SizedBox(height: 10),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ],
  );
}

class _BackToLogin extends StatelessWidget {
  const _BackToLogin({required this.backLocation});

  final String backLocation;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Identified(
      id: UiTestIds.authBackLogin,
      merge: true,
      child: TextButton.icon(
        onPressed: () => context.go(backLocation),
        icon: const Icon(Icons.arrow_back),
        label: Text(AppLocalizations.of(context).authBackToLogin),
      ),
    ),
  );
}

class AuthField extends StatelessWidget {
  const AuthField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 9),
      child,
    ],
  );
}

InputDecoration authInputDecoration({
  required String hint,
  required IconData icon,
  Widget? suffix,
}) => InputDecoration(
  hintText: hint,
  prefixIcon: Icon(icon, size: 21),
  suffixIcon: suffix,
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xffd9e3ef)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xff2457ed), width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xffb42335)),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xffb42335), width: 1.5),
  ),
);

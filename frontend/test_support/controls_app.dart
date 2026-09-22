// A separately compiled UI prototype. This library is never imported by lib/main.dart.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:haruka/app/haruka_app.dart';
import 'package:haruka/core/layout/adaptive_policy.dart';
import 'package:haruka/generated/ui_test_ids.dart';
import 'package:haruka/shared/identified.dart';

class ControlsApp extends StatefulWidget {
  const ControlsApp({super.key});

  @override
  State<ControlsApp> createState() => _ControlsAppState();
}

class _ControlsAppState extends State<ControlsApp> {
  final _text = TextEditingController();
  late final GoRouter _router;
  late final SemanticsHandle _semantics;

  @override
  void initState() {
    super.initState();
    _semantics = SemanticsBinding.instance.ensureSemantics();
    _router = GoRouter(
      routes: [
        for (final base in ['/fixture', '/admin/fixture']) ...[
          GoRoute(
            path: base,
            builder: (context, state) => _ControlsPage(text: _text, base: base),
          ),
          GoRoute(
            path: '$base/next',
            builder: (context, state) => Scaffold(
              appBar: AppBar(title: const Text('路由刷新原型')),
              body: Center(
                child: Identified(
                  id: UiTestIds.backHome,
                  child: TextButton(onPressed: () => context.go(base), child: const Text('返回控件')),
                ),
              ),
            ),
          ),
        ],
      ],
      initialLocation: '/fixture',
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _text.dispose();
    _semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Haruka 控件原型',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: _router,
  );
}

class _ControlsPage extends StatefulWidget {
  const _ControlsPage({required this.text, required this.base});
  final TextEditingController text;
  final String base;

  @override
  State<_ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<_ControlsPage> {
  final _formKey = GlobalKey();
  final _inputFocus = FocusNode();
  String? _submitted;

  @override
  void dispose() {
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _showConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Identified(
        id: UiTestIds.fixtureDialog,
        child: AlertDialog(
          title: const Text('确认原型输入'),
          content: Text(widget.text.text),
          actions: [
            Identified(
              id: UiTestIds.fixtureConfirm,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认'),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && confirmed == true) setState(() => _submitted = widget.text.text);
  }

  @override
  Widget build(BuildContext context) => Identified(
    id: UiTestIds.fixturePage,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.base.startsWith('/admin') ? '管理布局原型' : '用户布局原型')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = AdaptivePolicy.forWidth(constraints.maxWidth) == LayoutSize.expanded;
            final form = Padding(
              key: _formKey,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Identified(
                    id: UiTestIds.fixtureInput,
                    child: TextField(
                      controller: widget.text,
                      focusNode: _inputFocus,
                      decoration: const InputDecoration(
                        labelText: '原型输入',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Identified(
                    id: UiTestIds.fixtureSubmit,
                    child: FilledButton(
                      onPressed: widget.text.text.trim().isEmpty ? null : _showConfirmation,
                      child: const Text('打开确认'),
                    ),
                  ),
                  if (_submitted != null) Text('已确认：$_submitted'),
                  Identified(
                    id: UiTestIds.fixtureNavigate,
                    child: TextButton(
                      onPressed: () => context.go('${widget.base}/next'),
                      child: const Text('检查路由'),
                    ),
                  ),
                ],
              ),
            );
            final list = Identified(
              id: UiTestIds.fixtureList,
              child: ListView.builder(
                itemCount: 80,
                itemBuilder: (context, index) {
                  final tile = ListTile(title: Text('控件样本 ${index + 1}'));
                  return index == 79 ? Identified(id: UiTestIds.fixtureLastRow, child: tile) : tile;
                },
              ),
            );
            return wide
                ? Row(
                    children: [
                      SizedBox(width: 360, child: SingleChildScrollView(child: form)),
                      Expanded(child: list),
                    ],
                  )
                : Column(
                    children: [
                      Flexible(child: SingleChildScrollView(child: form)),
                      Expanded(child: list),
                    ],
                  );
          },
        ),
      ),
    ),
  );
}

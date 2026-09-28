import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/responses.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../generated/ui_test_ids.dart';
import '../data/cached_settings_repository.dart';
import '../domain/avatar_upload.dart';
import '../domain/settings_snapshot.dart';
import 'settings_chrome.dart';

const _imageTypes = XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
  uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'org.webmproject.webp'],
);

/// Private avatar on the signed-in profile page. Bytes stay in this widget.
class OwnerAvatarRow extends StatefulWidget {
  const OwnerAvatarRow({
    required this.api,
    required this.repository,
    required this.auth,
    this.badgeOnly = false,
    super.key,
  });

  final ApiClient api;
  final CachedSettingsRepository repository;
  final AuthController auth;
  final bool badgeOnly;

  @override
  State<OwnerAvatarRow> createState() => _OwnerAvatarRowState();
}

class _OwnerAvatarRowState extends State<OwnerAvatarRow> {
  Uint8List? _bytes;
  String? _shownAssetId;
  String? _shownScope;
  String? _requestedAssetKey;
  bool _busy = false;

  bool _sameScope(int epoch, int generation, String instance, String? userId) =>
      mounted &&
      widget.auth.actionEpoch == epoch &&
      widget.repository.scopeGeneration == generation &&
      widget.auth.boundInstanceId == instance &&
      widget.auth.access?.userId == userId &&
      widget.auth.isAuthenticated;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onProfile);
    widget.auth.addListener(_onProfile);
    _onProfile();
  }

  @override
  void didUpdateWidget(OwnerAvatarRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_onProfile);
      widget.repository.addListener(_onProfile);
      _onProfile();
    }
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth.removeListener(_onProfile);
      widget.auth.addListener(_onProfile);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onProfile);
    widget.auth.removeListener(_onProfile);
    super.dispose();
  }

  String? get _assetId {
    final value = widget.repository.snapshot(SettingsGroup.profile)?.fields['avatar_asset_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  void _onProfile() {
    final assetId = _assetId;
    final scopeKey =
        '${widget.auth.boundInstanceId}:${widget.auth.access?.userId}:${widget.repository.scopeGeneration}';
    if (_shownScope != scopeKey) {
      _shownScope = scopeKey;
      _shownAssetId = null;
      _requestedAssetKey = null;
      _bytes = null;
      if (mounted) setState(() {});
    }
    if (assetId == _shownAssetId || _requestedAssetKey == '$scopeKey:$assetId') return;
    if (assetId == null) {
      _shownAssetId = null;
      if (_bytes != null && mounted) setState(() => _bytes = null);
      _bytes = null;
      return;
    }
    if (_shownAssetId != assetId && _bytes != null) {
      _bytes = null;
      if (mounted) setState(() {});
    }
    final requested = assetId;
    _requestedAssetKey = '$scopeKey:$assetId';
    final epoch = widget.auth.actionEpoch;
    final generation = widget.repository.scopeGeneration;
    final instance = widget.auth.boundInstanceId;
    final userId = widget.auth.access?.userId;
    unawaited(
      Future<void>(() async {
        try {
          final bytes = await readOwnerAvatar(
            download: (headers) => widget.api.download('/api/v1/users/me/avatar', headers: headers),
            authorize: widget.auth.authorizedRead,
          );
          if (!_sameScope(epoch, generation, instance, userId) || _assetId != requested) return;
          setState(() {
            _requestedAssetKey = null;
            _shownAssetId = requested;
            _bytes = bytes;
          });
        } on ApiFailure catch (error) {
          if (!_sameScope(epoch, generation, instance, userId) || _assetId != requested) return;
          if (error.code != 'RESOURCE_NOT_FOUND') {
            if (_requestedAssetKey == '$scopeKey:$requested') _requestedAssetKey = null;
            return;
          }
          setState(() {
            _requestedAssetKey = null;
            _shownAssetId = requested;
            _bytes = null;
          });
        } on Object {
          // A later profile notification can try the private read again.
          if (_sameScope(epoch, generation, instance, userId) &&
              _requestedAssetKey == '$scopeKey:$requested') {
            _requestedAssetKey = null;
          }
        }
      }),
    );
  }

  Future<void> _replace() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final profile = widget.repository.snapshot(SettingsGroup.profile);
    if (profile == null) return;
    final epoch = widget.auth.actionEpoch;
    final generation = widget.repository.scopeGeneration;
    final instance = widget.auth.boundInstanceId;
    final userId = widget.auth.access?.userId;
    final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (file == null || !_sameScope(epoch, generation, instance, userId)) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (!_sameScope(epoch, generation, instance, userId)) return;
      await publishOwnerAvatar(
        bytes: bytes,
        expectedRevision: profile.revision,
        authorize: widget.auth.authorizedWrite,
        post: (path, body, headers) async {
          if (!_sameScope(epoch, generation, instance, userId)) throw StateError('scope changed');
          final response = await widget.api.postJson<Object?>(
            path,
            body,
            (data) => data,
            headers: headers,
          );
          return response.data;
        },
      );
      if (!_sameScope(epoch, generation, instance, userId)) return;
      await widget.repository.reconcileExternalCommit(
        SettingsGroup.profile,
        expectedScopeGeneration: generation,
      );
      if (!_sameScope(epoch, generation, instance, userId)) return;
      if (!mounted) return;
      trackSettingsMutation(context, 'profile.avatar.updated');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.mockProfileAvatarUpdated)));
    } on Object {
      if (!_sameScope(epoch, generation, instance, userId)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.apiUnknownError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final profile = widget.repository.snapshot(SettingsGroup.profile);
    if (profile == null || _assetId == null) return;
    final epoch = widget.auth.actionEpoch;
    final generation = widget.repository.scopeGeneration;
    final instance = widget.auth.boundInstanceId;
    final userId = widget.auth.access?.userId;
    setState(() => _busy = true);
    try {
      await widget.auth.authorizedWrite((headers) async {
        if (!_sameScope(epoch, generation, instance, userId)) throw StateError('scope changed');
        await widget.api.deleteJson<Object?>(
          '/api/v1/users/me/avatar',
          {'expected_revision': profile.revision},
          (data) => data,
          headers: headers,
        );
      });
      if (!_sameScope(epoch, generation, instance, userId)) return;
      await widget.repository.reconcileExternalCommit(
        SettingsGroup.profile,
        expectedScopeGeneration: generation,
      );
      if (mounted && _sameScope(epoch, generation, instance, userId)) {
        trackSettingsMutation(context, 'profile.avatar.deleted');
      }
    } on Object {
      if (!_sameScope(epoch, generation, instance, userId)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).apiUnknownError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roles = HarukaColors.of(context);
    final bytes = _bytes;
    final avatar = CircleAvatar(
      radius: 26,
      backgroundColor: roles.signal,
      backgroundImage: bytes == null ? null : MemoryImage(bytes),
      child: bytes == null ? Text(_glyph(), style: TextStyle(color: roles.onSignal)) : null,
    );
    if (widget.badgeOnly) return avatar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.mockProfileCurrentAvatar)),
          ],
        ),
        if (_canUpdateAvatar(context))
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              children: [
                TextButton(
                  key: const ValueKey(UiTestIds.settingsAvatarReplace),
                  onPressed: _busy ? null : _replace,
                  child: Text(l10n.mockProfileChangeAvatar),
                ),
                if (_assetId != null)
                  TextButton(
                    key: const ValueKey(UiTestIds.settingsAvatarDelete),
                    onPressed: _busy ? null : _delete,
                    child: const Text('删除头像'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _glyph() {
    final name = widget.repository.snapshot(SettingsGroup.profile)?.fields['display_name'];
    final text = name is String ? name.trim() : '';
    return text.isEmpty ? '·' : text.characters.first;
  }
}

bool _canUpdateAvatar(BuildContext context) {
  final auth = sessionAuth(context);
  return auth?.access?.allows('client.profile.avatar.update') ?? false;
}

AuthController? sessionAuth(BuildContext context) {
  try {
    return ProviderScope.containerOf(context, listen: false).read(authControllerProvider);
  } on Object {
    return null;
  }
}

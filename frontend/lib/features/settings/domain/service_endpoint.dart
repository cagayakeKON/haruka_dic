import 'package:dio/dio.dart';

import '../../../core/api/responses.dart';

/// A confirmed service origin. Credentials, query, and fragment are never kept.
Uri? parseServiceEndpoint(String raw, {required bool allowDevelopmentHttp}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.isAbsolute || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  final host = uri.host.toLowerCase();
  final developmentHttp =
      uri.scheme == 'http' &&
      allowDevelopmentHttp &&
      const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(host);
  if (uri.scheme != 'https' && !developmentHttp) return null;
  return Uri(scheme: uri.scheme, host: host, port: uri.hasPort ? uri.port : null);
}

final class ServiceProbe {
  const ServiceProbe({required this.endpoint, required this.meta});

  final Uri endpoint;
  final MetaRead meta;
}

final class InstanceSwitchCommit {
  const InstanceSwitchCommit({required this.revokeFailed});

  final bool revokeFailed;
}

/// Public meta probe. The client is created without a session, cookie, or key.
Future<ServiceProbe> probeServiceEndpoint(Uri endpoint, {Dio? client}) async {
  final dio =
      client ??
      Dio(
        BaseOptions(
          baseUrl: endpoint.toString(),
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
          headers: const {'Accept': 'application/json', 'Accept-Language': 'zh-Hans'},
        ),
      );
  final owned = client == null;
  try {
    final response = await dio.get<Object?>('/api/v1/meta');
    final names = response.requestOptions.headers.keys.map((key) => key.toLowerCase());
    if (names.contains('authorization') || names.contains('cookie')) {
      throw StateError('probe included credentials');
    }
    if (response.statusCode != 200) throw const FormatException('probe failed');
    final meta = SuccessResponse.fromJson(response.data, MetaRead.fromJson).data;
    if (meta.apiVersion != 'v1' || !RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(meta.instanceId)) {
      throw const FormatException('incompatible service');
    }
    return ServiceProbe(endpoint: endpoint, meta: meta);
  } finally {
    if (owned) dio.close();
  }
}

/// Sign out the old instance, drop its cache generation, then point at the probe.
/// A failed new connection puts the origin back and leaves the session signed out.
Future<InstanceSwitchCommit> commitInstanceSwitch({
  required bool signedIn,
  required void Function() stopOldActions,
  required void Function() resumeActions,
  required Future<void> Function() signOut,
  required Future<void> Function() clearLocalScope,
  required void Function(Uri endpoint, String instanceId) retarget,
  required void Function(Uri endpoint, String instanceId) bindInstance,
  required Uri previousEndpoint,
  required String previousInstanceId,
  required ServiceProbe probe,
  required Future<void> Function() verify,
}) async {
  stopOldActions();
  try {
    var revokeFailed = false;
    if (signedIn) {
      try {
        await signOut();
      } on Object {
        revokeFailed = true;
      }
    }
    await clearLocalScope();
    retarget(probe.endpoint, probe.meta.instanceId);
    try {
      bindInstance(probe.endpoint, probe.meta.instanceId);
      await verify();
    } on Object {
      retarget(previousEndpoint, previousInstanceId);
      try {
        bindInstance(previousEndpoint, previousInstanceId);
      } on Object {
        // The origin is back on the previous service. Credentials stay cleared.
      }
      rethrow;
    }
    return InstanceSwitchCommit(revokeFailed: revokeFailed);
  } finally {
    resumeActions();
  }
}

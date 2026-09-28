import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/service_endpoint.dart';
import 'service_endpoint_store.dart';

final class PlatformServiceEndpointStore implements ServiceEndpointStore {
  PlatformServiceEndpointStore({this.directoryPath});

  final String? directoryPath;

  Future<File> _file() async {
    final root = directoryPath ?? (await getApplicationSupportDirectory()).path;
    return File(path.join(root, 'haruka-service-endpoint.json'));
  }

  @override
  Future<ServiceEndpointRecord?> read({required bool allowDevelopmentHttp}) async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final raw = json['endpoint'];
      final instanceId = json['instance_id'];
      if (raw is! String || instanceId is! String) return null;
      final endpoint = parseServiceEndpoint(raw, allowDevelopmentHttp: allowDevelopmentHttp);
      if (endpoint == null || !RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(instanceId)) {
        return null;
      }
      return ServiceEndpointRecord(endpoint: endpoint, instanceId: instanceId);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(Uri endpoint, String instanceId) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final next = File('${file.path}.tmp');
    await next.writeAsString(
      jsonEncode({'endpoint': endpoint.toString(), 'instance_id': instanceId}),
    );
    if (file.existsSync()) await file.delete();
    await next.rename(file.path);
  }
}

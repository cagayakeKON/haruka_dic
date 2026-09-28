import 'service_endpoint_store.dart';

final class PlatformServiceEndpointStore implements ServiceEndpointStore {
  PlatformServiceEndpointStore({String? directoryPath});

  @override
  Future<ServiceEndpointRecord?> read({required bool allowDevelopmentHttp}) async => null;

  @override
  Future<void> save(Uri endpoint, String instanceId) async {}
}

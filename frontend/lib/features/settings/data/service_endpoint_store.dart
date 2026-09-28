import 'service_endpoint_store_native.dart'
    if (dart.library.js_interop) 'service_endpoint_store_web.dart'
    as implementation;

/// Confirmed native service origin. The address is not a credential and is not logged.
abstract interface class ServiceEndpointStore {
  factory ServiceEndpointStore({String? directoryPath}) =
      implementation.PlatformServiceEndpointStore;

  Future<ServiceEndpointRecord?> read({required bool allowDevelopmentHttp});

  Future<void> save(Uri endpoint, String instanceId);
}

final class ServiceEndpointRecord {
  const ServiceEndpointRecord({required this.endpoint, required this.instanceId});

  final Uri endpoint;
  final String instanceId;
}

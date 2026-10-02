import '../../../core/api/responses.dart';
import '../../../core/api/wire.dart';
import '../../../core/auth/auth_controller.dart';
import '../domain/material_metadata.dart';
import '../domain/material_summary.dart';

abstract interface class MaterialRepository {
  Future<PageResponse<MaterialMetadata>> list({
    LearningMaterialType? type,
    String? language,
    String search = '',
    String? cursor,
  });
  Future<MaterialMetadata> find(String id);
  Future<MaterialMetadata> rename(String id, int revision, String title);
  Future<void> delete(String id, int revision);
}

/// The server projects owner-scoped safe metadata. No user/object key/URL is
/// accepted from the UI, and every request uses current confirmed access.
final class HttpMaterialRepository implements MaterialRepository {
  const HttpMaterialRepository(this.auth);
  final AuthController auth;

  @override
  Future<PageResponse<MaterialMetadata>> list({
    LearningMaterialType? type,
    String? language,
    String search = '',
    String? cursor,
  }) => auth.authorizedRead((headers) {
    final query = Uri(
      queryParameters: {
        'limit': '20',
        if (type != null) 'material_type': type.name,
        'language': ?language,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'cursor': ?cursor,
      },
    ).query;
    return auth.repository.api.getPage(
      '/api/v1/materials?$query',
      MaterialMetadata.fromJson,
      headers: headers,
    );
  });

  @override
  Future<MaterialMetadata> find(String id) => auth.authorizedRead(
    (headers) async => (await auth.repository.api.getJson(
      '/api/v1/materials/${wireUuid(id)}',
      MaterialMetadata.fromJson,
      headers: headers,
    )).data,
  );

  @override
  Future<MaterialMetadata> rename(String id, int revision, String title) => auth.authorizedWrite(
    (headers) async => (await auth.repository.api.patchJson(
      '/api/v1/materials/${wireUuid(id)}',
      {'expected_revision': revision, 'title': title.trim()},
      MaterialMetadata.fromJson,
      headers: headers,
    )).data,
  );

  @override
  Future<void> delete(String id, int revision) => auth.authorizedWrite(
    (headers) => auth.repository.api.deleteEmpty(
      '/api/v1/materials/${wireUuid(id)}?expected_revision=$revision',
      headers: headers,
    ),
  );
}

import 'dart:convert';

import 'support/generated/api_compatibility_samples.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/auth_models.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/auth/auth_repository.dart';
import 'package:haruka/core/config/app_config.dart';

import 'support/sample_adapter.dart';

void main() {
  final samples = jsonDecode(apiCompatibilitySamplesJson) as Map<String, dynamic>;
  final access = SuccessResponse<AccessRead>.fromJson(
    samples['auth_admin_access'],
    AccessRead.fromJson,
  ).data;
  final config = AppConfig.parse(
    platform: AppPlatform.web,
    environment: 'dev',
    instanceId: access.instanceId,
    apiBaseUrl: 'http://localhost:18443',
  );

  ResponseBody response(String sample) => ResponseBody.fromString(
    jsonEncode(samples[sample]),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'X-Haruka-Instance-ID': [access.instanceId],
      'X-Haruka-Session-Ref': [access.sessionRef],
    },
  );

  test(
    'published menu catalog and authorized preview preserve registered permission floors',
    () async {
      final paths = <String>[];
      final api = ApiClient(
        config,
        requireSessionBinding: true,
        adapter: SampleAdapter((options, stream) async {
          paths.add('${options.method} ${options.uri.path}');
          expect(options.headers['X-Haruka-Expected-Session'], access.sessionRef);
          switch (options.uri.path) {
            case '/api/v1/admin/menu-catalog':
              expect(options.method, 'GET');
              return response('admin_menu_catalog');
            case '/api/v1/admin/menus/preview':
              expect(options.method, 'POST');
              if (stream == null) throw StateError('Missing preview request JSON');
              final chunks = await stream.toList();
              expect(jsonDecode(utf8.decode([for (final chunk in chunks) ...chunk])), {
                'user_id': access.userId,
                'audience': 'admin',
              });
              return response('admin_menu_preview');
            default:
              throw StateError('Unexpected administration request');
          }
        }),
      );
      addTearDown(api.close);
      api.bindConfirmedAccess(access);
      final repository = AuthRepository(api, config);
      final catalog = await repository.adminMenuCatalog(const {});
      final preview = await repository.previewAdminMenus(access.userId, 'admin', const {});
      expect(catalog.pages, isNotEmpty);
      expect(preview.navigation, isNotEmpty);
      for (final page in catalog.pages) {
        expect(catalog.icons, contains(page.iconKey));
        for (final floor in page.floor) {
          expect(
            catalog.permissionCodes.any((permission) => permission.code == floor),
            isTrue,
            reason: 'Published permission floor must resolve to the registry',
          );
        }
      }
      for (final item in preview.navigation) {
        expect(
          catalog.pages.any((page) => page.audience == 'admin' && page.routeKey == item.routeKey),
          isTrue,
          reason: 'Authorized navigation cannot invent an unpublished route',
        );
      }
      expect(() => catalog.pages.clear(), throwsUnsupportedError);
      expect(() => catalog.permissionCodes.clear(), throwsUnsupportedError);
      expect(() => preview.navigation.clear(), throwsUnsupportedError);
      expect(paths, ['GET /api/v1/admin/menu-catalog', 'POST /api/v1/admin/menus/preview']);
    },
  );

  test(
    'administration role read preserves enabled parent identity and committed revision',
    () async {
      final sampleData =
          (samples['admin_role_with_parent'] as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      final roleId = sampleData['id'] as String;
      var reads = 0;
      final api = ApiClient(
        config,
        requireSessionBinding: true,
        adapter: SampleAdapter((options, _) async {
          reads++;
          expect(options.method, 'GET');
          expect(options.uri.path, '/api/v1/admin/roles/$roleId');
          expect(options.headers['X-Haruka-Expected-Session'], access.sessionRef);
          return response('admin_role_with_parent');
        }),
      );
      addTearDown(api.close);
      api.bindConfirmedAccess(access);
      final role = await AuthRepository(api, config).adminRole(roleId, const {});
      expect(role.revision, 2);
      expect(role.parents, hasLength(1));
      expect(role.parents.single.enabled, isTrue);
      expect(role.parents.single.roleId, '018f1234-5678-7123-8123-123456789abd');
      expect(role.parents.single.code, 'client_readonly');
      expect(() => role.parents.clear(), throwsUnsupportedError);
      expect(reads, 1);
    },
  );
}

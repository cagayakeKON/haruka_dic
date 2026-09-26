import '../../generated/build_targets.dart';

enum AppPlatform { android, windows, web }

/// Public deployment identity only. Credentials never enter compile-time defines.
final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.instanceId,
    required this.apiBaseUrl,
    required this.platform,
  });

  factory AppConfig.fromEnvironment({required AppPlatform platform, String? flavor}) =>
      AppConfig.parse(
        platform: platform,
        flavor: flavor,
        environment: const String.fromEnvironment('HARUKA_ENV', defaultValue: 'dev'),
        instanceId: const String.fromEnvironment('HARUKA_INSTANCE_ID'),
        apiBaseUrl: const String.fromEnvironment('HARUKA_API_BASE_URL'),
      );

  factory AppConfig.parse({
    required AppPlatform platform,
    required String environment,
    String instanceId = '',
    String apiBaseUrl = '',
    String? flavor,
  }) {
    if (!BuildTargets.displayNames.containsKey(environment)) {
      throw const FormatException('Unknown environment');
    }
    if (platform == AppPlatform.android && flavor != environment) {
      throw const FormatException('Android flavor does not match environment');
    }
    final isDevelopment = environment == 'dev';
    final resolvedInstance = instanceId.isEmpty && isDevelopment
        ? BuildTargets.developmentInstanceId
        : instanceId;
    final resolvedUrl = apiBaseUrl.isEmpty && isDevelopment && platform != AppPlatform.android
        ? BuildTargets.developmentApiBaseUrl
        : apiBaseUrl;
    final uri = Uri.tryParse(resolvedUrl);
    if (!RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(resolvedInstance) ||
        uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Invalid instance or API origin');
    }
    final testInstance = RegExp(BuildTargets.testInstancePattern).hasMatch(resolvedInstance);
    if (isDevelopment) {
      final ordinaryDev =
          resolvedInstance == BuildTargets.developmentInstanceId &&
          BuildTargets.developmentApiBaseUrls.contains(resolvedUrl);
      final isolatedTest =
          testInstance &&
          (BuildTargets.testApiBaseUrls[platform.name]?.contains(resolvedUrl) ?? false);
      if (!ordinaryDev && !isolatedTest) {
        throw const FormatException('Development target is not an isolated declared instance');
      }
    } else if (resolvedInstance == BuildTargets.developmentInstanceId ||
        testInstance ||
        uri.scheme != 'https' ||
        const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host)) {
      throw const FormatException('Production requires an explicit HTTPS target');
    }
    return AppConfig._(
      environment: environment,
      instanceId: resolvedInstance,
      apiBaseUrl: uri,
      platform: platform,
    );
  }

  final String environment;
  final String instanceId;
  final Uri apiBaseUrl;
  final AppPlatform platform;

  String get displayName => BuildTargets.displayNames[environment]!;
  String get applicationId => platform == AppPlatform.web
      ? 'web:$environment'
      : BuildTargets.applicationIds[platform.name]![environment]!;
}

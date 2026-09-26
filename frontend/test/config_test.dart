import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/config/app_config.dart';
import 'package:haruka/core/layout/adaptive_policy.dart';

void main() {
  group('SCF-FE-CONFIG unit: public target validation', () {
    test('desktop development defaults are isolated and production has no defaults', () {
      final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');
      expect(config.instanceId, 'haruka-local-dev');
      expect(config.apiBaseUrl.toString(), 'http://127.0.0.1:8000');
      expect(config.applicationId, 'haruka.dictionary.dev');
      expect(
        () => AppConfig.parse(platform: AppPlatform.web, environment: 'production'),
        throwsFormatException,
      );
    });

    test('Android requires explicit reachable address and matching flavor', () {
      expect(
        () => AppConfig.parse(platform: AppPlatform.android, environment: 'dev', flavor: 'dev'),
        throwsFormatException,
      );
      expect(
        () => AppConfig.parse(
          platform: AppPlatform.android,
          environment: 'dev',
          flavor: 'production',
          apiBaseUrl: 'http://10.0.2.2:8000',
        ),
        throwsFormatException,
      );
      final config = AppConfig.parse(
        platform: AppPlatform.android,
        environment: 'dev',
        flavor: 'dev',
        apiBaseUrl: 'http://10.0.2.2:8000',
      );
      expect(config.applicationId, 'app.haruka.dictionary.dev');
    });

    test('development rejects undeclared targets and production accepts explicit HTTPS', () {
      for (final values in [
        ('staging', 'haruka-local-dev', 'http://127.0.0.1:8000'),
        ('dev', 'another-instance', 'http://127.0.0.1:8000'),
        ('dev', 'haruka-local-dev', 'https://service.example'),
        ('production', 'haruka-public', 'http://service.example'),
        ('production', 'haruka-local-dev', 'https://service.example'),
        ('production', 'haruka-public', 'https://localhost'),
        ('production', 'haruka-public', 'https://user:secret@service.example'),
        ('production', 'haruka-public', 'https://service.example?key=secret'),
        ('production', 'haruka-public', 'https://service.example/private'),
      ]) {
        expect(
          () => AppConfig.parse(
            platform: AppPlatform.web,
            environment: values.$1,
            instanceId: values.$2,
            apiBaseUrl: values.$3,
          ),
          throwsFormatException,
        );
      }
      final production = AppConfig.parse(
        platform: AppPlatform.windows,
        environment: 'production',
        instanceId: 'haruka-public',
        apiBaseUrl: 'https://service.example',
      );
      expect(production.applicationId, 'haruka.dictionary');
    });

    test('run-scoped identity requires an exact suffix and platform-specific origin', () {
      const instance = 'haruka-test-0123456789abcdef0123456789abcdef';
      for (final target in [
        (AppPlatform.web, 'https://localhost:18443'),
        (AppPlatform.windows, 'http://127.0.0.1:18081'),
        (AppPlatform.android, 'http://10.0.2.2:18081'),
      ]) {
        final config = AppConfig.parse(
          platform: target.$1,
          environment: 'dev',
          flavor: target.$1 == AppPlatform.android ? 'dev' : null,
          instanceId: instance,
          apiBaseUrl: target.$2,
        );
        expect(config.instanceId, instance);
      }
      for (final invalid in [
        ('haruka-test-0123456789abcdef0123456789abcdeg', 'https://localhost:18443'),
        ('haruka-test-0123456789abcdef0123456789abcdef-extra', 'https://localhost:18443'),
        ('haruka-test-0123456789abcdef0123456789abcdef', 'http://127.0.0.1:8000'),
        ('haruka-local-dev', 'https://localhost:18443'),
      ]) {
        expect(
          () => AppConfig.parse(
            platform: AppPlatform.web,
            environment: 'dev',
            instanceId: invalid.$1,
            apiBaseUrl: invalid.$2,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AppConfig.parse(
          platform: AppPlatform.windows,
          environment: 'production',
          instanceId: instance,
          apiBaseUrl: 'https://service.example',
        ),
        throwsFormatException,
      );
    });
  });

  test('SCF-FE-LAYOUT unit: layout boundary decisions use available width', () {
    expect(AdaptivePolicy.forWidth(599), LayoutSize.compact);
    expect(AdaptivePolicy.forWidth(600), LayoutSize.medium);
    expect(AdaptivePolicy.forWidth(1023), LayoutSize.medium);
    expect(AdaptivePolicy.forWidth(1024), LayoutSize.expanded);
  });
}

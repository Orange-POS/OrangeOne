import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';

void main() {
  test('honors compile-time timeout configuration', () {
    final container = ProviderContainer.test(
      overrides: [
        environmentProvider.overrideWithValue(AppEnvironment.development),
      ],
    );
    final config = container.read(apiConfigurationProvider);
    expect(
      config.connectTimeout,
      const Duration(
        milliseconds: int.fromEnvironment(
          'ODOO_CONNECT_TIMEOUT_MS',
          defaultValue: 15000,
        ),
      ),
    );
    expect(
      config.responseTimeout,
      const Duration(
        milliseconds: int.fromEnvironment(
          'ODOO_RESPONSE_TIMEOUT_MS',
          defaultValue: 20000,
        ),
      ),
    );
  });
  for (final environment in AppEnvironment.values) {
    test('${environment.name} accepts changing HTTPS POS hosts and ports', () {
      final config = ApiConfiguration(
        baseUrl: 'https://previous.example',
        environment: environment,
      );
      for (final server in [
        'https://192.168.1.3:8080',
        'https://192.168.1.9:8443',
        'https://another-pos.example',
      ]) {
        expect(config.validateOrigin(server), Uri.parse(server));
      }
    });
    test('${environment.name} accepts configured HTTPS origins', () {
      final config = ApiConfiguration(
        baseUrl: 'https://pos.example/',
        environment: environment,
      );
      expect(config.trustedOrigin, Uri.parse('https://pos.example'));
    });
    test('${environment.name} accepts HTTP POS servers', () {
      final config = ApiConfiguration(
        baseUrl: 'http://pos.example',
        environment: environment,
      );
      expect(config.trustedOrigin.scheme, 'http');
      expect(config.validateOrigin('http://192.168.1.3:8080').port, 8080);
    });
  }
  group('Mobile API v2 base', () {
    const config = ApiConfiguration(
      baseUrl: 'http://192.168.1.3:8069',
      environment: AppEnvironment.production,
    );

    test('derives the fallback base from the configured origin', () {
      expect(
        config.trustedApiBase,
        Uri.parse('http://192.168.1.3:8069/api/orangeone/mobile/v1'),
      );
    });

    for (final entry in {
      'https://pos.example/api/orangeone/mobile/v1':
          'https://pos.example/api/orangeone/mobile/v1',
      'https://pos.example:8443/api/orangeone/mobile/v1/':
          'https://pos.example:8443/api/orangeone/mobile/v1',
      'http://192.168.1.2/odoo/api/orangeone/mobile/v1':
          'http://192.168.1.2/odoo/api/orangeone/mobile/v1',
    }.entries) {
      test('accepts the QR api_base ${entry.key}', () {
        expect(config.validateApiBase(entry.key), Uri.parse(entry.value));
      });
    }

    for (final value in [
      '',
      'https://pos.example',
      'https://pos.example/api/orangeone/mobile/v2',
      'https://pos.example/api/orangeone/mobile/v1/extra',
      'https://pos.example/a//api/orangeone/mobile/v1',
      'ftp://pos.example/api/orangeone/mobile/v1',
      'https://user:pass@pos.example/api/orangeone/mobile/v1',
      'https://pos.example/api/orangeone/mobile/v1?db=untrusted',
      'https://pos.example/api/orangeone/mobile/v1#fragment',
    ]) {
      test('rejects the api_base "$value"', () {
        expect(
          () => config.validateApiBase(value),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.unsupportedQr,
            ),
          ),
        );
      });
    }
  });

  for (final value in [
    '',
    'ftp://pos.example',
    'https://user:pass@pos.example',
    'https://pos.example/path',
    'https://pos.example?db=untrusted',
    'https://pos.example#fragment',
  ]) {
    test('rejects unsupported configured origins without exposing them', () {
      final config = ApiConfiguration(
        baseUrl: value,
        environment: AppEnvironment.production,
      );
      expect(
        () => config.trustedOrigin,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.unsupportedQr,
          ),
        ),
      );
    });
  }
}

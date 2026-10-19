import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/errors/app_failure.dart';

void main() {
  for (final environment in AppEnvironment.values) {
    for (final debug in [true, false]) {
      test(
        '${environment.name} debug=$debug logging and diagnostics policy',
        () {
          final settings = ApplicationSettings.parse(environment, {
            'APP_ENVIRONMENT': environment.name,
            'APP_DEBUG_LOGGING': 'true',
          }, debugBuild: debug);
          expect(
            settings.loggingEnabled,
            debug && environment != AppEnvironment.production,
          );
          expect(
            settings.diagnosticsEnabled,
            debug && environment == AppEnvironment.development,
          );
        },
      );
    }
    test(
      '${environment.name} loads nonsecret endpoint and timeout overrides',
      () {
        final settings = ApplicationSettings.parse(environment, {
          'APP_ENVIRONMENT': environment.name,
          'ODOO_BASE_URL': 'https://pos.example:8443',
          'ODOO_CONNECT_TIMEOUT_MS': '1234',
          'ODOO_RESPONSE_TIMEOUT_MS': '5678',
        }, debugBuild: true);
        expect(settings.baseUrl, 'https://pos.example:8443');
        expect(settings.connectTimeout.inMilliseconds, 1234);
        expect(settings.responseTimeout.inMilliseconds, 5678);
      },
    );
  }
  test(
    'QR discovery needs no origin; logging defaults to development only',
    () {
      for (final environment in AppEnvironment.values) {
        final settings = ApplicationSettings.parse(
          environment,
          {},
          debugBuild: true,
        );
        expect(settings.baseUrl, isEmpty);
        expect(
          settings.loggingEnabled,
          environment == AppEnvironment.development,
        );
      }
    },
  );
  for (final values in [
    {'APP_ENVIRONMENT': 'production'},
    {'APP_ENVIRONMENT': ''},
    {'ODOO_BASE_URL': ''},
    {'ODOO_BASE_URL': 'https://user:private@pos.example'},
    {'ODOO_BASE_URL': 'https://pos.example?token=private'},
    {'ODOO_BASE_URL': 'not-a-url'},
    {'ODOO_CONNECT_TIMEOUT_MS': 'abc'},
    {'ODOO_CONNECT_TIMEOUT_MS': ''},
    {'ODOO_CONNECT_TIMEOUT_MS': '0'},
    {'ODOO_RESPONSE_TIMEOUT_MS': '-1'},
    {'ODOO_RESPONSE_TIMEOUT_MS': '600001'},
    {'APP_DEBUG_LOGGING': 'yes'},
  ]) {
    test('invalid configuration fails safely: ${values.keys.single}', () {
      expect(
        () => ApplicationSettings.parse(
          AppEnvironment.development,
          values,
          debugBuild: true,
        ),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.kind, 'kind', FailureKind.configuration)
              .having(
                (e) => e.message.contains('private'),
                'no input echoed',
                false,
              ),
        ),
      );
    });
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/errors/app_failure.dart';

class ApiConfiguration {
  const new({
    required this.baseUrl,
    required this.environment,
    this.connectTimeout = const Duration(seconds: 15),
    this.responseTimeout = const Duration(seconds: 20),
  });

  /// Path of the OrangeONE Mobile API v2 below the Odoo origin.
  static const mobileApiPath = '/api/orangeone/mobile/v1';

  final String baseUrl;
  final AppEnvironment environment;
  final Duration connectTimeout;
  final Duration responseTimeout;

  Uri get trustedOrigin {
    return validateOrigin(baseUrl);
  }

  /// Validates an origin supplied by a POS QR or encrypted session record.
  Uri validateOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.port <= 0 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const AppFailure(
        FailureKind.unsupportedQr,
        'This Odoo server address is unsupported. Use HTTP or HTTPS '
        'with a valid server address and port.',
      );
    }
    return uri.replace(path: '');
  }

  /// Mobile API v2 base URL derived from the build-time fallback origin.
  Uri get trustedApiBase => trustedOrigin.replace(path: mobileApiPath);

  /// Validates a Mobile API v2 base URL, such as a POS QR `api_base`.
  ///
  /// The origin follows [validateOrigin]. Its path must end with
  /// [mobileApiPath], optionally below a plain prefix such as `/odoo`.
  Uri validateApiBase(String value) {
    const unsupported = AppFailure(
      FailureKind.unsupportedQr,
      'This Odoo server address is unsupported. Use HTTP or HTTPS '
      'with a valid server address and port.',
    );
    final uri = Uri.tryParse(value);
    if (uri == null) throw unsupported;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    if (!path.endsWith(mobileApiPath)) throw unsupported;
    final prefix = path.substring(0, path.length - mobileApiPath.length);
    if (!RegExp(r'^(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$').hasMatch(prefix)) {
      throw unsupported;
    }
    return validateOrigin(uri.replace(path: '').toString()).replace(path: path);
  }
}

final apiConfigurationProvider = Provider<ApiConfiguration>((ref) {
  final settings = ref.watch(applicationSettingsProvider);
  return ApiConfiguration(
    baseUrl: settings.baseUrl,
    environment: settings.environment,
    connectTimeout: settings.connectTimeout,
    responseTimeout: settings.responseTimeout,
  );
}, name: 'apiConfigurationProvider');
final utcNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
  name: 'utcNowProvider',
);

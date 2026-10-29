import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/data/models/login_qr_model.dart';

import '../../../support/auth_fakes.dart';

void main() {
  const configuration = ApiConfiguration(
    baseUrl: '',
    environment: AppEnvironment.development,
  );

  void expectRejected(Map<String, dynamic> changes, FailureKind kind) => expect(
    () => LoginQrModel.parse(
      jsonEncode({...qrFields(), ...changes}),
      configuration,
      testNow,
    ),
    throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', kind)),
  );

  test('maps the v2 POS QR contract without leaking secrets', () {
    final challenge = LoginQrModel.parse(validQr(), configuration, testNow);

    expect(challenge.challengeId, qrFields()['challenge_id']);
    expect(challenge.nonce, qrFields()['nonce']);
    expect(challenge.posConfigId, 1);
    expect(challenge.apiBase, testApiBase);
    expect(challenge.expiresAt, testNow.add(const Duration(minutes: 2)));
    expect(challenge.toString(), 'LoginChallenge(redacted)');
  });

  for (final base in [
    'http://192.168.1.3:8080/api/orangeone/mobile/v1',
    'http://192.168.1.9:8069/odoo/api/orangeone/mobile/v1',
    'https://another-pos.example:8443/api/orangeone/mobile/v1/',
  ]) {
    test('accepts the dynamic POS API base $base', () {
      final challenge = LoginQrModel.parse(
        jsonEncode({...qrFields(), 'api_base': base}),
        configuration,
        testNow,
      );
      expect(
        challenge.apiBase.toString(),
        base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      );
    });
  }

  for (final value in [
    '',
    'not json',
    '[]',
    '{}',
    'null',
    '{"v":true}',
    '{"v":2}',
    '{"v":"2","type":"orangeone.pos-login"}',
  ]) {
    test('rejects malformed payload "$value"', () {
      expect(
        () => LoginQrModel.parse(value, configuration, testNow),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.validation,
          ),
        ),
      );
    });
  }

  test('rejects oversized payloads', () {
    expect(
      () => LoginQrModel.parse('x' * 8193, configuration, testNow),
      throwsA(same(invalidQr)),
    );
  });

  test('explains that a version 1 QR comes from an outdated POS', () {
    final v1 = jsonEncode({
      'challenge': List.filled(43, 'a').join(),
      'nonce': List.filled(43, 'b').join(),
      'pos_session_id': 106,
      'pos_config_id': 1,
      'backend_url': 'https://pos.example',
      'rest_endpoint_url':
          'https://pos.example/mupi/mobile/auth/challenge/validate',
      'expires_at': testNow.add(const Duration(minutes: 5)).toIso8601String(),
    });

    expect(
      () => LoginQrModel.parse(v1, configuration, testNow),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.unsupportedQr,
        ),
      ),
    );
  });

  for (final entry in <String, (Map<String, dynamic>, FailureKind)>{
    'future version': ({'v': 3}, FailureKind.unsupportedQr),
    'unknown type': ({'type': 'other'}, FailureKind.unsupportedQr),
    'expired': (
      {'expires_at': testNow.toIso8601String()},
      FailureKind.expiredQr,
    ),
    'missing timezone': (
      {'expires_at': '2030-01-01T13:00:00'},
      FailureKind.validation,
    ),
    'calendar overflow': (
      {'expires_at': '2030-02-31T13:00:00Z'},
      FailureKind.validation,
    ),
    'hour overflow': (
      {'expires_at': '2030-01-01T25:00:00Z'},
      FailureKind.validation,
    ),
    'timezone overflow': (
      {'expires_at': '2030-01-01T13:00:00+99:00'},
      FailureKind.validation,
    ),
    'short challenge id': ({'challenge_id': 'chl_'}, FailureKind.validation),
    'challenge id characters': (
      {'challenge_id': 'chl_<script>xx'},
      FailureKind.validation,
    ),
    'short nonce': ({'nonce': 'short'}, FailureKind.validation),
    'nonpositive config': ({'pos_config_id': 0}, FailureKind.validation),
    'boolean config': ({'pos_config_id': true}, FailureKind.validation),
    'string config': ({'pos_config_id': '1'}, FailureKind.validation),
    'missing api base': ({'api_base': null}, FailureKind.validation),
    'api base without API path': (
      {'api_base': 'https://pos.example'},
      FailureKind.unsupportedQr,
    ),
    'unsupported scheme': (
      {'api_base': 'ftp://pos.example/api/orangeone/mobile/v1'},
      FailureKind.unsupportedQr,
    ),
    'invalid port': (
      {'api_base': 'https://pos.example:65536/api/orangeone/mobile/v1'},
      FailureKind.unsupportedQr,
    ),
    'api base query': (
      {'api_base': 'https://pos.example/api/orangeone/mobile/v1?db=other'},
      FailureKind.unsupportedQr,
    ),
    'api base credentials': (
      {'api_base': 'https://user@pos.example/api/orangeone/mobile/v1'},
      FailureKind.unsupportedQr,
    ),
  }.entries) {
    test('rejects ${entry.key}', () {
      expectRejected(entry.value.$1, entry.value.$2);
    });
  }
}

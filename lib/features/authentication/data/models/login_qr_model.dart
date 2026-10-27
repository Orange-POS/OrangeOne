import 'dart:convert';

import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/formatting/utc_timestamp.dart';
import 'package:orange_one/features/authentication/domain/entities/login_challenge.dart';

/// POS login QR payload v2 (`QrPayload` in the Mobile API contract).
class LoginQrModel {
  static const version = 2;
  static const type = 'orangeone.pos-login';

  static LoginChallenge parse(
    String raw,
    ApiConfiguration configuration,
    DateTime now,
  ) {
    try {
      if (raw.isEmpty || raw.length > 8192) throw invalidQr;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) throw invalidQr;
      if (!json.containsKey('v')) {
        // Version 1 POS QR codes carried `challenge` and `backend_url`.
        if (json.containsKey('challenge')) throw _outdatedQr;
        throw invalidQr;
      }
      if (json['v'] is! int || json['type'] is! String) throw invalidQr;
      if (json['v'] != version || json['type'] != type) {
        throw const AppFailure(
          FailureKind.unsupportedQr,
          'This QR code version is not supported. Generate a compatible '
          'POS QR code.',
        );
      }
      final challengeId = json['challenge_id'];
      final nonce = json['nonce'];
      final config = json['pos_config_id'];
      final apiBase = json['api_base'];
      final expiry = json['expires_at'];
      if (challengeId is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(challengeId) ||
          nonce is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(nonce) ||
          config is! int ||
          config <= 0 ||
          apiBase is! String ||
          expiry is! String ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(expiry)) {
        throw invalidQr;
      }
      final base = configuration.validateApiBase(apiBase);
      final expiresAt = parseUtcTimestamp(expiry);
      if (!expiresAt.isAfter(now)) {
        throw const AppFailure(
          FailureKind.expiredQr,
          'This QR code has expired. Generate a new QR code '
          'on your POS machine.',
        );
      }
      return LoginChallenge(
        challengeId: challengeId,
        nonce: nonce,
        posConfigId: config,
        apiBase: base,
        expiresAt: expiresAt,
      );
    } on FormatException {
      throw invalidQr;
    }
  }

  static const _outdatedQr = AppFailure(
    FailureKind.unsupportedQr,
    'This QR code comes from an older POS version. Update the POS and '
    'generate a new QR code.',
  );
}

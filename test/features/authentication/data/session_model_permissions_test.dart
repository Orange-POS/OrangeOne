import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/features/authentication/data/models/session_model.dart';

import '../../../support/auth_fakes.dart';

void main() {
  test('session permissions are read from the token grant', () {
    final credentials = SessionModel.fromGrant(
      tokenGrant(
        session: {
          ...sessionPayload(),
          'permissions': {
            'product_read': true,
            'stock_adjust': false,
            'unexpected': 'yes',
          },
        },
      ),
      testApiBase,
    );
    expect(credentials.session.permissions, {
      'product_read': true,
      'stock_adjust': false,
    });
  });

  test('missing permissions are unknown, never a sign-in failure', () {
    final payload = sessionPayload()..remove('permissions');
    final session = SessionModel.fromSession(payload, testApiBase, 'oa_x');
    expect(session.permissions, isEmpty);
  });

  test('permissions never reach the stored session record', () {
    final credentials = SessionModel.fromGrant(tokenGrant(), testApiBase);
    expect(credentials.session.permissions, isNotEmpty);
    final stored = SessionModel.encode(credentials);
    expect(stored.contains('permissions'), isFalse);
    expect(stored.contains('product_read'), isFalse);
    final restored = SessionModel.decode(
      stored,
      ApiConfiguration(
        baseUrl: testOrigin.toString(),
        environment: AppEnvironment.production,
      ),
    );
    expect(restored.session.permissions, isEmpty);
  });
}

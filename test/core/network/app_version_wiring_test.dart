import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/config/app_version.dart';
import 'package:orange_one/core/network/dio_provider.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';

void main() {
  test(
    'the app wiring sends one installed version in header and device',
    () async {
      final dio = Dio();
      final server = FakeMobileApiServer()
        ..on(
          'POST /auth/qr-exchange',
          (_) => FakeReply(200, successEnvelope(tokenGrant())),
        )
        ..on(
          'GET /auth/session',
          (_) => FakeReply(200, successEnvelope(sessionPayload())),
        );
      dio.httpClientAdapter = server;
      final container = ProviderContainer.test(
        overrides: [
          appVersionProvider.overrideWithValue('2.4.1'),
          environmentProvider.overrideWithValue(AppEnvironment.development),
          dioProvider.overrideWithValue(dio),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          apiConfigurationProvider.overrideWithValue(
            const ApiConfiguration(
              baseUrl: 'https://fallback.example',
              environment: AppEnvironment.development,
            ),
          ),
          utcNowProvider.overrideWithValue(() => testNow),
        ],
      );
      addTearDown(() => dio.close(force: true));

      await container.read(authRepositoryProvider).signIn(validQr());

      final request = server.called('POST /auth/qr-exchange').single;
      final device = requestBody(request)['device'] as Map<String, dynamic>;
      expect(request.headers['X-App-Version'], '2.4.1');
      expect(device['app_version'], '2.4.1');
    },
  );
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/network/dio_provider.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';

import '../support/auth_fakes.dart';
import '../support/product_fakes.dart';

void main() {
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
  ]) {
    test('first $type clears session and lookup without retries', () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final auth = FakeAuthRepository()..restored = testSession;
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(DioException(requestOptions: options, type: type));
          },
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          productRepositoryOverride,
          authenticatedMobileApiOverride,
          environmentProvider.overrideWithValue(AppEnvironment.production),
          authRepositoryProvider.overrideWithValue(auth),
          utcNowProvider.overrideWithValue(() => testNow),
          dioProvider.overrideWithValue(dio),
        ],
      );
      await container.read(sessionControllerProvider.future);
      container.listen(productLookupControllerProvider, (previous, next) {});
      await container
          .read(productLookupControllerProvider.notifier)
          .scan(fixtureProduct.barcode);
      await container.pump();
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(auth.signOuts, 1);
      expect(requests, 1);
      expect(container.read(productLookupControllerProvider).value, isNull);
    });
  }

  test(
    'backend session rejection clears auth and suppresses product results',
    () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final auth = FakeAuthRepository()..restored = testSession;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 401,
                data: errorEnvelope('TOKEN_REVOKED'),
              ),
            );
          },
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          productRepositoryOverride,
          authenticatedMobileApiOverride,
          environmentProvider.overrideWithValue(AppEnvironment.production),
          authRepositoryProvider.overrideWithValue(auth),
          utcNowProvider.overrideWithValue(() => testNow),
          dioProvider.overrideWithValue(dio),
        ],
      );
      await container.read(sessionControllerProvider.future);
      container.listen(productLookupControllerProvider, (previous, next) {});
      await container
          .read(productLookupControllerProvider.notifier)
          .scan(fixtureProduct.barcode);
      await container.pump();
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(auth.signOuts, 1);
      expect(
        container.read(productLookupControllerProvider).value?.product,
        isNull,
      );
    },
  );

  test(
    'disposing a lookup cancels its authenticated network request',
    () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final requested = Completer<RequestOptions>();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requested.complete(options);
            // Simulate a request in flight until CancelToken aborts it.
          },
        ),
      );
      final container = ProviderContainer.test(
        overrides: [
          productRepositoryOverride,
          authenticatedMobileApiOverride,
          environmentProvider.overrideWithValue(AppEnvironment.production),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restored = testSession,
          ),
          utcNowProvider.overrideWithValue(() => testNow),
          dioProvider.overrideWithValue(dio),
        ],
      );
      await container.read(sessionControllerProvider.future);
      final subscription = container.listen(
        productLookupControllerProvider,
        (previous, next) {},
      );
      final pending = container
          .read(productLookupControllerProvider.notifier)
          .scan(fixtureProduct.barcode);
      final request = await requested.future;
      expect(request.uri.origin, testOrigin.toString());
      subscription.close();
      await container.pump();
      expect(request.cancelToken?.isCancelled, isTrue);
      await pending;
    },
  );
}

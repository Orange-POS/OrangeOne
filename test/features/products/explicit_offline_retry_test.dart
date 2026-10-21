import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';

import '../../support/product_fakes.dart';

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  late Dio dio;
  WidgetTester? widgetTester;
  late ProviderContainer container;
  late OdooProductRepository lookup;
  late OdooProductDetailsRepository details;
  late List<String> paths;
  late bool available;
  late bool rejected;
  late bool failSave;
  late String scopes;
  late int signOuts;
  Map<String, dynamic>? found;
  const code = '0010101010';

  setUp(() {
    widgetTester = null;
    database = ReadCacheDatabase(NativeDatabase.memory());
    cache = EncryptedReadCache(database, sessionSecret: 'test-session');
    dio = Dio();
    available = true;
    rejected = false;
    failSave = false;
    signOuts = 0;
    scopes = 'product:name_update product:price_update reference:read';
    found = null;
    paths = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          paths.add(request.uri.path);
          if (!available ||
              (failSave && request.path.endsWith('/products/save'))) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          final path = request.path;
          // Reject unexpected routes: these tests must never perform a write.
          if (!path.endsWith('/token/check') &&
              !path.endsWith('/products/find') &&
              !path.endsWith('/products/references')) {
            fail('Unexpected write or other endpoint: $path');
          }
          final result = rejected
              ? {'ok': false, 'error': 'Token is not active.'}
              : path.endsWith('/token/check')
              ? {'ok': true, 'scopes': scopes}
              : path.endsWith('/products/references')
              ? {'ok': true, 'taxes': <Object?>[]}
              : {'ok': true, 'product': found};
          handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'jsonrpc': '2.0',
                'id': (request.data as Map)['id'],
                'result': result,
              },
            ),
          );
        },
      ),
    );
    final client = JsonRpcClient(
      dio,
      const ApiConfiguration(
        baseUrl: 'https://unused.test',
        environment: AppEnvironment.development,
      ),
    );
    Future<void> onRejected() async {
      signOuts++;
    }

    lookup = OdooProductRepository(
      ProductRemoteDataSource(
        client,
        origin: Uri.parse('https://pos.test'),
        accessToken: 'test-session',
        cancelToken: CancelToken(),
      ),
      cache: cache,
      onSessionRejected: onRejected,
    );
    details = OdooProductDetailsRepository(
      ProductDetailsRemoteDataSource(
        client,
        origin: Uri.parse('https://pos.test'),
        token: 'test-session',
        cancelToken: CancelToken(),
      ),
      cache: cache,
      onSessionRejected: onRejected,
    );
    container = ProviderContainer.test(
      overrides: [
        readCacheProvider.overrideWithValue(cache),
        productRepositoryProvider.overrideWithValue(lookup),
        productDetailsRepositoryProvider.overrideWithValue(details),
      ],
    );
    addTearDown(() async {
      Future<void> cleanup() async {
        container.dispose();
        dio.close(force: true);
        await cache.close();
        await database.close();
      }

      if (widgetTester case final tester?) {
        await tester.runAsync(cleanup);
      } else {
        await cleanup();
      }
    });
  });

  for (final screen in ['creation', 'edit', 'price']) {
    testWidgets('$screen initial error retry probes on the same Wi-Fi', (
      tester,
    ) async {
      widgetTester = tester;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      available = false;
      found = screen == 'creation' ? null : productJson();
      final page = switch (screen) {
        'creation' => const ProductCreationPage(barcode: code),
        'edit' => const ProductEditPage(barcode: code),
        _ => const ProductPriceUpdatePage(barcode: code),
      };
      Future<Object?> currentLoad() => switch (screen) {
        'creation' => container.read(
          productCreationControllerProvider(code).future,
        ),
        'edit' => container.read(productEditControllerProvider(code).future),
        _ => container.read(priceUpdateControllerProvider(code).future),
      };
      await tester.runAsync(() async {
        switch (screen) {
          case 'creation':
            container.listen(
              productCreationControllerProvider(code),
              (_, _) {},
            );
          case 'edit':
            container.listen(productEditControllerProvider(code), (_, _) {});
          case 'price':
            container.listen(priceUpdateControllerProvider(code), (_, _) {});
        }
        await expectLater(currentLoad(), throwsA(isA<AppFailure>()));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(cache.offline, isTrue);
      expect(paths, ['/mupi/mobile/auth/token/check']);

      // Ordinary reads stay local; a failed tap makes just one probe.
      await tester.runAsync(() async {
        await expectLater(details.load(code), throwsA(isA<AppFailure>()));
      });
      expect(paths.length, 1);
      await tester.runAsync(() async {
        await tester.tap(find.text('Try again'));
        await expectLater(currentLoad(), throwsA(isA<AppFailure>()));
      });
      await tester.pumpAndSettle();
      expect(paths.length, 2);
      expect(cache.offline, isTrue);

      available = true; // No connectivity-interface event.
      final before = paths.length;
      await tester.runAsync(() async {
        await tester.tap(find.text('Try again'));
        await currentLoad();
      });
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(cache.offline, isFalse);
      expect(cache.status(code).phase, ReadSyncPhase.online);
      expect(paths.skip(before), [
        '/mupi/mobile/auth/token/check',
        '/mupi/mobile/api/products/find',
        if (screen != 'price') '/mupi/mobile/api/products/references',
      ]);
      switch (screen) {
        case 'creation':
          expect(
            container
                .read(productCreationControllerProvider(code))
                .requireValue
                .context
                .canCreate,
            isTrue,
          );
        case 'edit':
          expect(
            container
                .read(productEditControllerProvider(code))
                .requireValue
                .canEdit,
            isTrue,
          );
        case 'price':
          expect(
            container
                .read(priceUpdateControllerProvider(code))
                .requireValue
                .details
                .access
                .updatePrice,
            isTrue,
          );
      }
      expect(signOuts, 0);
      // The transport rejects all write endpoints.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('scanner retries probe once per action on the same interface', () async {
    container.listen(productLookupControllerProvider, (_, _) {});
    await container.read(productLookupControllerProvider.future);
    final controller = container.read(productLookupControllerProvider.notifier);
    available = false;
    await controller.scan(code);
    expect(
      container.read(productLookupControllerProvider).error,
      isA<AppFailure>(),
    );
    expect(cache.offline, isTrue);
    expect(paths.length, 1);

    // Failed explicit retry sends one read, then ordinary reads short-circuit.
    await controller.retry();
    expect(paths.length, 2);
    expect(cache.offline, isTrue);
    await expectLater(lookup.findByBarcode(code), throwsA(isA<AppFailure>()));
    expect(paths.length, 2);

    available = true; // Same interface: no connectionChanged notification.
    found = productJson()..['name'] = 'Fresh server product';
    await controller.retry();
    expect(paths.length, 3);
    expect(
      container
          .read(productLookupControllerProvider)
          .requireValue
          ?.product
          ?.name,
      'Fresh server product',
    );
    expect(cache.offline, isFalse);
    expect(cache.status(code).phase, ReadSyncPhase.online);
    expect(signOuts, 0);
  });

  test('creation Check restores permissions and preserves drafts', () async {
    final provider = productCreationControllerProvider(code);
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    final controller = container.read(provider.notifier)
      ..edit(name: 'Draft name', price: '12.50', taxIds: []);
    paths.clear();
    available = false;
    await controller.check();
    expect(cache.offline, isTrue);
    expect(
      container.read(provider).requireValue.phase,
      ProductCreationPhase.uncertain,
    );
    expect(paths, ['/mupi/mobile/auth/token/check']);

    await controller.check();
    expect(paths.length, 2);
    expect(cache.offline, isTrue);
    await expectLater(
      details.prepareCreation(code),
      throwsA(isA<AppFailure>()),
    );
    expect(paths.length, 2);

    available = true;
    await controller.check();
    expect(paths.skip(2), [
      '/mupi/mobile/auth/token/check',
      '/mupi/mobile/api/products/find',
      '/mupi/mobile/api/products/references',
    ]);
    final state = container.read(provider).requireValue;
    expect(state.phase, ProductCreationPhase.editing);
    expect(state.canSubmit, isTrue);
    expect(state.name, 'Draft name');
    expect(state.price, '12.50');
    expect(state.taxIds, isEmpty);
    expect(cache.offline, isFalse);
    expect(signOuts, 0);
  });

  test(
    'Check discovers an existing product and does not replay creation',
    () async {
      final provider = productCreationControllerProvider(code);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final controller = container.read(provider.notifier)
        ..edit(name: 'Preserved', price: '10', taxIds: []);
      available = false;
      await controller.check();
      available = true;
      found = productJson();
      paths.clear();
      await controller.check();
      final state = container.read(provider).requireValue;
      expect(state.context.details.product?.id, fixtureProduct.id);
      expect(state.canSubmit, isFalse);
      expect(state.name, 'Preserved');
      expect(paths, [
        '/mupi/mobile/auth/token/check',
        '/mupi/mobile/api/products/find',
      ]);
    },
  );

  test(
    'Check after an uncertain save probes but never replays the write',
    () async {
      final provider = productCreationControllerProvider(code);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final controller = container.read(provider.notifier)
        ..edit(name: 'Uncertain draft', price: '12.50', taxIds: []);
      failSave = true;
      await controller.save();
      expect(
        container.read(provider).requireValue.phase,
        ProductCreationPhase.uncertain,
      );
      expect(cache.offline, isTrue);
      expect(paths.where((path) => path.endsWith('/products/save')).length, 1);
      final before = paths.length;
      // Simulate a lost acknowledgement: the product now exists on the server.
      found = productJson();
      failSave = false;
      await controller.check();
      expect(paths.skip(before), [
        '/mupi/mobile/auth/token/check',
        '/mupi/mobile/api/products/find',
      ]);
      expect(paths.where((path) => path.endsWith('/products/save')).length, 1);
      final state = container.read(provider).requireValue;
      expect(state.context.details.product?.id, fixtureProduct.id);
      expect(state.name, 'Uncertain draft');
      expect(state.canSubmit, isFalse);
      expect(cache.offline, isFalse);
    },
  );

  test('explicit creation probe still enforces fresh permissions', () async {
    available = false;
    await expectLater(
      details.prepareCreation(code),
      throwsA(isA<AppFailure>()),
    );
    available = true;
    scopes = 'product:read';
    final result = await details.prepareCreation(code, refresh: true);
    expect(result.canCreate, isFalse);
    expect(cache.offline, isFalse);
    expect(paths.where((path) => path.endsWith('/references')), isEmpty);
  });

  test('explicit retry never falls back on authentication rejection', () async {
    found = productJson();
    await lookup.findByBarcode(code);
    available = false;
    await lookup.findByBarcode(code);
    expect(cache.offline, isTrue);
    available = true;
    rejected = true;
    await expectLater(
      lookup.findByBarcode(code, refresh: true),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.unauthenticated,
        ),
      ),
    );
    expect(signOuts, 1);
    expect(await cache.read(code), isNull);
  });
}

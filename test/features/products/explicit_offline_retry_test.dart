import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/home/data/data_sources/product_remote_data_source.dart';
import 'package:orange_one/features/home/data/repositories/odoo_product_repository.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';
import 'package:orange_one/l10n/l10n.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_fakes.dart';

const _api = '/api/orangeone/mobile/v1';
const _byBarcode = '$_api/products/by-barcode/0010101010';
const _session = '$_api/auth/session';
const _taxes = '$_api/taxes';
const _categories = '$_api/categories';
const _create = '$_api/products';

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  WidgetTester? widgetTester;
  late ProviderContainer container;
  late OdooProductRepository lookup;
  late OdooProductDetailsRepository details;
  late List<String> paths;
  late bool available;
  late bool rejected;
  late bool failSave;
  late Map<String, bool> permissions;
  late int signOuts;
  Map<String, dynamic>? found;
  const code = '0010101010';

  setUp(() {
    widgetTester = null;
    database = ReadCacheDatabase(NativeDatabase.memory());
    cache = EncryptedReadCache(database, sessionSecret: 'test-session');
    available = true;
    rejected = false;
    failSave = false;
    signOuts = 0;
    permissions = productPermissions();
    found = null;
    paths = [];
    FakeReply read(RequestOptions request) {
      paths.add(request.uri.path);
      if (!available) {
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      }
      if (rejected) return FakeReply(401, errorEnvelope('TOKEN_REVOKED'));
      if (request.uri.path == _session) {
        return FakeReply(200, successEnvelope(sessionData(permissions)));
      }
      if (request.uri.path == _taxes) {
        return FakeReply(
          200,
          successEnvelope({'taxes': <Object>[], 'default_tax_ids': <int>[]}),
        );
      }
      if (request.uri.path == _categories) {
        return const FakeReply(200, {
          'data': <Object>[
            {'id': 4, 'name': 'Spices'},
          ],
          'meta': {'next_cursor': null},
        });
      }
      return found == null
          ? FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND'))
          : FakeReply(200, successEnvelope(found));
    }

    final server = FakeMobileApiServer()
      ..on('GET /products/by-barcode/$code', read)
      ..on('GET /products/10', read)
      ..on('GET /auth/session', read)
      ..on('GET /taxes', read)
      ..on('GET /categories', read)
      ..on('POST /products', (request) {
        paths.add(request.uri.path);
        // These tests must never complete a write.
        if (!failSave) fail('Unexpected write: ${request.uri.path}');
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      });
    final api = fakeProductApi(server);
    Future<void> onRejected() async {
      signOuts++;
    }

    lookup = OdooProductRepository(
      ProductRemoteDataSource(api, cancelToken: CancelToken()),
      cache: cache,
      onSessionRejected: onRejected,
    );
    details = OdooProductDetailsRepository(
      ProductCatalogRemoteDataSource(api, cancelToken: CancelToken()),
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
      found = screen == 'creation' ? null : v2Product();
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
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(cache.offline, isTrue);
      expect(paths, [_byBarcode]);

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
        _byBarcode,
        if (screen == 'creation') _session,
        if (screen != 'price') _taxes,
        if (screen != 'price') _categories,
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
    found = v2Product(name: 'Fresh server product');
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
      ..edit(name: 'Draft name', price: '12.50', taxIds: [], categoryId: 4);
    paths.clear();
    available = false;
    await controller.check();
    expect(cache.offline, isTrue);
    expect(
      container.read(provider).requireValue.phase,
      ProductCreationPhase.uncertain,
    );
    expect(paths, [_byBarcode]);

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
    expect(paths.skip(2), [_byBarcode, _session, _taxes, _categories]);
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
        ..edit(name: 'Preserved', price: '10', taxIds: [], categoryId: 4);
      available = false;
      await controller.check();
      available = true;
      found = v2Product();
      paths.clear();
      await controller.check();
      final state = container.read(provider).requireValue;
      expect(state.context.details.product?.id, fixtureProduct.id);
      expect(state.canSubmit, isFalse);
      expect(state.name, 'Preserved');
      expect(paths, [_byBarcode]);
    },
  );

  test(
    'Check after an uncertain save probes but never replays the write',
    () async {
      final provider = productCreationControllerProvider(code);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final controller = container.read(provider.notifier)
        ..edit(
          name: 'Uncertain draft',
          price: '12.50',
          taxIds: [],
          categoryId: 4,
        );
      failSave = true;
      await controller.save();
      expect(
        container.read(provider).requireValue.phase,
        ProductCreationPhase.uncertain,
      );
      expect(cache.offline, isTrue);
      expect(paths.where((path) => path == _create).length, 1);
      final before = paths.length;
      // Simulate a lost acknowledgement: the product now exists on the server.
      found = v2Product();
      failSave = false;
      await controller.check();
      expect(paths.skip(before), [_byBarcode]);
      expect(paths.where((path) => path == _create).length, 1);
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
    permissions = productPermissions({
      for (final key in productPermissions().keys) key: key == 'product_read',
    });
    final result = await details.prepareCreation(code, refresh: true);
    expect(result.canCreate, isFalse);
    expect(cache.offline, isFalse);
    expect(paths.where((path) => path == _taxes), isEmpty);
  });

  test('explicit retry never falls back on authentication rejection', () async {
    found = v2Product();
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

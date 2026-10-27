import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/features/products/data/data_sources/product_catalog_remote_data_source.dart';
import 'package:orange_one/features/products/data/data_sources/product_details_remote_data_source.dart';
import 'package:orange_one/features/products/data/repositories/odoo_product_details_repository.dart';

import '../../support/auth_fakes.dart';
import '../../support/mobile_api_fakes.dart';
import '../../support/product_api_fakes.dart';
import '../../support/product_fakes.dart';

void main() {
  late ReadCacheDatabase database;
  late EncryptedReadCache cache;
  late Dio dio;
  late OdooProductDetailsRepository repository;
  late bool available;
  late Map<String, bool> permissions;
  late List<String> requests;
  Map<String, dynamic>? found;
  const code = '0010101010';

  setUp(() {
    database = ReadCacheDatabase(NativeDatabase.memory());
    cache = EncryptedReadCache(database, sessionSecret: 'synthetic-session');
    dio = Dio();
    available = true;
    found = v2Product();
    permissions = productPermissions();
    requests = [];
    // Writes use the v1 client; none may reach the transport in this test.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request.uri.path);
          fail('A mutation must not reach the transport in this test.');
        },
      ),
    );
    FakeReply read(RequestOptions request) {
      requests.add(request.uri.path);
      if (!available) {
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        );
      }
      if (request.uri.path.endsWith('/auth/session')) {
        return FakeReply(200, successEnvelope(sessionData(permissions)));
      }
      return found == null
          ? FakeReply(404, errorEnvelope('PRODUCT_NOT_FOUND'))
          : FakeReply(
              200,
              successEnvelope({...found!, 'permissions': permissions}),
            );
    }

    final server = FakeMobileApiServer()
      ..on('GET /products/by-barcode/$code', read)
      ..on('GET /products/10', read)
      ..on('GET /auth/session', read);
    repository = OdooProductDetailsRepository(
      ProductDetailsRemoteDataSource(
        JsonRpcClient(
          dio,
          const ApiConfiguration(
            baseUrl: 'https://unused.test',
            environment: AppEnvironment.development,
          ),
        ),
        origin: Uri.parse('https://pos.test'),
        token: () async => 'synthetic-session',
        cancelToken: CancelToken(),
      ),
      catalog: ProductCatalogRemoteDataSource(
        fakeProductApi(server),
        cancelToken: CancelToken(),
      ),
      cache: cache,
      onSessionRejected: () async {},
    );
    addTearDown(() async {
      await database.customStatement('DROP TRIGGER IF EXISTS fail_insert');
      await database.customStatement('DROP TRIGGER IF EXISTS fail_delete');
      await cache.close();
      await database.close();
      dio.close(force: true);
    });
  });

  Future<void> failSql(String operation) => database.customStatement('''
    CREATE TRIGGER fail_${operation.toLowerCase()}
    BEFORE $operation ON product_reads
    BEGIN SELECT RAISE(ABORT, 'Injected SQLite failure'); END
  ''');

  for (final recovering in [false, true]) {
    test(
      'fresh permissions survive failed INSERT, recovering=$recovering',
      () async {
        await repository.load(code);
        if (recovering) {
          available = false;
          final stale = await repository.load(code);
          expect(stale.access.updatePrice, isFalse);
          expect(cache.offline, isTrue);
          available = true;
          cache.retryRead();
        }
        await failSql('INSERT');
        found = v2Product(name: 'Fresh result');
        final fresh = await repository.load(code);
        expect(fresh.product?.name, 'Fresh result');
        expect(fresh.access.updatePrice, isTrue);
        expect(fresh.access.editName, isTrue);
        expect(cache.offline, isFalse);
        expect(cache.status(code).phase, ReadSyncPhase.failed);
        expect(cache.status(code).verifiedAt, isNotNull);
        expect(await cache.read(code), isNull);

        // A new instance must be safe even before the old cache is closed.
        final replacement = EncryptedReadCache(
          database,
          sessionSecret: 'synthetic-session',
        )..connectionChanged(connected: false);
        var probes = 0;
        await expectLater(
          replacement.load(code, () async {
            probes++;
            return productJson();
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(probes, 0);
        expect(
          await database.customSelect('SELECT * FROM product_reads').get(),
          isEmpty,
        );
        await replacement.close();

        // Old SQLite contents cannot be reused after failed replacement.
        available = false;
        await expectLater(repository.load(code), throwsA(isA<AppFailure>()));
        expect(cache.offline, isTrue);
        available = true;
        cache.retryRead();
        await database.customStatement('DROP TRIGGER fail_insert');
        final recovered = await repository.load(code);
        expect(recovered.access.updatePrice, isTrue);
        expect(cache.status(code).phase, ReadSyncPhase.online);
        expect((await cache.read(code))?['name'], 'Fresh result');
      },
    );
  }

  test(
    'failed durable cleanup keeps local guard until persistence recovers',
    () async {
      await repository.load(code);
      await failSql('INSERT');
      await failSql('DELETE');
      found = v2Product(name: 'Fresh but not cached');
      final fresh = await repository.load(code);
      expect(fresh.product?.name, 'Fresh but not cached');
      expect(fresh.access.updatePrice, isTrue);
      expect(cache.offline, isFalse);
      expect(cache.status(code).phase, ReadSyncPhase.failed);
      expect(
        await database.customSelect('SELECT * FROM product_reads').get(),
        hasLength(1),
      );
      expect(await cache.read(code), isNull);
      available = false;
      await expectLater(repository.load(code), throwsA(isA<AppFailure>()));
      await database.customStatement('DROP TRIGGER fail_insert');
      await database.customStatement('DROP TRIGGER fail_delete');
      available = true;
      cache.retryRead();
      await repository.load(code);
      expect(cache.status(code).phase, ReadSyncPhase.online);
      expect((await cache.read(code))?['name'], 'Fresh but not cached');
    },
  );

  test(
    'failed DELETE preserves fresh not-found and blocks unsafe writes',
    () async {
      await repository.load(code);
      cache
        ..connectionChanged(connected: false)
        ..retryRead();
      await failSql('DELETE');
      found = null;
      final fresh = await repository.load(code);
      expect(fresh.product, isNull);
      expect(fresh.access.editName, isTrue);
      expect(cache.offline, isFalse);
      expect(cache.status(code).phase, ReadSyncPhase.failed);
      expect(await cache.read(code), isNull);
      final before = requests.length;
      await expectLater(
        repository.updatePrice(10, 12),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.kind,
            'kind',
            FailureKind.storage,
          ),
        ),
      );
      expect(requests.length, before);
      expect(cache.offline, isFalse);
      expect(cache.status(code).phase, ReadSyncPhase.failed);
      await database.customStatement('DROP TRIGGER fail_delete');
      await repository.load(code);
      expect(cache.status(code).phase, ReadSyncPhase.online);
      expect(await cache.read(code), isNull);
    },
  );

  test(
    'fresh connectivity does not grant permissions the server withholds',
    () async {
      await repository.load(code);
      cache
        ..connectionChanged(connected: false)
        ..retryRead();
      await failSql('INSERT');
      permissions = productPermissions({
        for (final key in productPermissions().keys) key: key == 'product_read',
      });
      final fresh = await repository.load(code);
      expect(cache.offline, isFalse);
      expect(fresh.access.updatePrice, isFalse);
      expect(fresh.access.editName, isFalse);
      expect(cache.status(code).phase, ReadSyncPhase.failed);
    },
  );

  test(
    'successful persistence and network fallback have distinct provenance',
    () async {
      final first = await cache.loadResult(code, () async => productJson());
      expect(first.serverVerified, isTrue);
      expect(cache.status(code).phase, ReadSyncPhase.online);
      final fallback = await cache.loadResult(code, () async {
        throw const AppFailure(FailureKind.network, 'Offline');
      });
      expect(fallback.serverVerified, isFalse);
      expect(fallback.product?['id'], fixtureProduct.id);
      expect(cache.offline, isTrue);
      final stale = await repository.load(code);
      expect(stale.access.updatePrice, isFalse);
      expect(stale.access.editName, isFalse);
      expect(requests, isEmpty);
    },
  );
}

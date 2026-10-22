import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/product_details_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device Drift persistence and offline/recovery icons', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/offline-smoke-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final database = ReadCacheDatabase(NativeDatabase(file));
    final cache = EncryptedReadCache(
      database,
      sessionSecret: 'disposable-device-test',
    );
    const barcode = '0010101010';
    final product = <String, dynamic>{
      'id': 10,
      'barcode': barcode,
      'name': detailsFixture.name,
      'price': 100.0,
      'stock_quantity': 48.0,
      'uom': 'Units',
    };
    try {
      await tester.runAsync(() async {
        await cache.load(barcode, () async => product);
        await cache.load(
          barcode,
          () async =>
              throw const AppFailure(FailureKind.network, 'Offline test'),
        );
        expect((await cache.read(barcode))?['id'], 10);
        expect(
          latin1.decode(await file.readAsBytes()),
          isNot(contains(detailsFixture.name)),
        );
        var writes = 0;
        await expectLater(
          cache.write(() async {
            writes++;
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(writes, 0);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [readCacheProvider.overrideWithValue(cache)],
          child: const MaterialApp(
            home: Scaffold(body: ProductNameCard(product: detailsFixture)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      for (var cycle = 0; cycle < 2; cycle++) {
        await tester.runAsync(() async {
          cache.connectionChanged(connected: true);
          await cache.load(barcode, () async => {...product, 'price': 125.0});
        });
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
        cache.connectionChanged(connected: false);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    } finally {
      await tester.runAsync(() async {
        await cache.close();
        await database.close();
        if (file.existsSync()) await file.delete();
      });
    }
  });
}

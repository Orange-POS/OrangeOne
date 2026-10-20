import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/storage/encrypted_read_cache.dart';
import 'package:orange_one/core/storage/read_cache_database.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';

import '../support/product_details_fakes.dart';
import '../support/product_fakes.dart';

void main() {
  testWidgets(
    'all product cards show offline/online icons with accessible freshness',
    (tester) async {
      final db = ReadCacheDatabase(NativeDatabase.memory());
      final cache = EncryptedReadCache(db, sessionSecret: 'test-session');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(() async {
          await cache.close();
          await db.close();
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [readCacheProvider.overrideWithValue(cache)],
          child: const MaterialApp(
            home: Scaffold(body: ProductNameCard(product: detailsFixture)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      cache.connectionChanged(connected: false);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(
        find.byTooltip('Offline: cached data may be outdated'),
        findsOneWidget,
      );
      expect(find.text('In stock · 48 Units'), findsOneWidget);
    },
  );
  testWidgets('management buttons recover after two offline cycles', (
    tester,
  ) async {
    final db = ReadCacheDatabase(NativeDatabase.memory());
    final cache = EncryptedReadCache(db, sessionSecret: 'button-test');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await cache.close();
        await db.close();
      });
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readCacheProvider.overrideWithValue(cache),
          productDetailsRepositoryProvider.overrideWithValue(
            FakeDetailsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: ProductDetailsPage(barcode: '0010101010'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton, 'Update Price');
    expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
    for (var cycle = 0; cycle < 2; cycle++) {
      cache.connectionChanged(connected: false);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      await tester.runAsync(() async {
        cache.connectionChanged(connected: true);
        await cache.load('0010101010', () async => productJson());
      });
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
    }
  });
}

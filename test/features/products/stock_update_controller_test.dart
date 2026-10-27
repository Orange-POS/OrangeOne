import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/stock_update_providers.dart';

import '../../support/product_details_fakes.dart';

ProductDetails _with({double? stock = 48, bool adjustable = true}) =>
    ProductDetails(
      id: detailsFixture.id,
      name: detailsFixture.name,
      barcode: detailsFixture.barcode,
      price: detailsFixture.price,
      stock: stock,
      unit: detailsFixture.unit,
      version: detailsFixture.version,
      stockAdjustable: adjustable,
      stockLocationId: 8,
      quantityDecimals: 0,
    );

void main() {
  late FakeDetailsRepository repo;
  late ProviderContainer container;
  final provider = stockUpdateControllerProvider('0010101010');
  StockUpdateController controller() => container.read(provider.notifier);
  StockUpdateState value() => container.read(provider).requireValue;
  setUp(() async {
    repo = FakeDetailsRepository();
    container = ProviderContainer.test(
      overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
    )..listen(provider, (_, _) {});
    await container.read(provider.future);
  });

  test('invalid counts never submit', () {
    expect(controller().confirmation(), isNull);
    for (final input in ['-1', 'abc', '1.234', '']) {
      controller().changeQuantity(input);
      expect(controller().confirmation(), isNull, reason: input);
    }
    controller().changeQuantity('48');
    expect(controller().confirmation(), isNotNull, reason: 'recount allowed');
  });

  test('a confirmed count is written with the fresh version', () async {
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    await controller().save(confirmed);
    expect(repo.writtenCount?.text, '50');
    expect(repo.writtenVersions, ['3']);
    expect(value().phase, StockUpdatePhase.saved);
    expect(value().details.product?.stock, 50);
    expect(value().previousQuantity, 48);
  });

  test('repeated saves while busy write once', () async {
    repo.pendingWrite = Completer<ProductDetails>();
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    final first = controller().save(confirmed);
    await Future<void>.delayed(Duration.zero);
    await controller().save(confirmed);
    controller().changeQuantity('51');
    expect(value().draft, '50');
    repo.pendingWrite!.complete(_with(stock: 50));
    await first;
    expect(repo.writes, 1);
  });

  test('a changed server stock requires a new review', () async {
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    repo.product = _with(stock: 47);
    await controller().save(confirmed);
    expect(repo.writes, 0);
    expect(value().details.product?.stock, 47);
    expect(value().draft, '50');
    expect(value().message, contains('stock changed'));
  });

  for (final (label, access, product) in [
    ('permission', const ProductAccess(), _with()),
    ('adjustability', repoAccess, _with(adjustable: false)),
    ('tracking', repoAccess, _with(stock: null, adjustable: false)),
  ]) {
    test('losing $label after confirmation never writes', () async {
      controller().changeQuantity('50');
      final confirmed = controller().confirmation()!;
      repo
        ..access = access
        ..product = product;
      await controller().save(confirmed);
      expect(repo.writes, 0);
      expect(value().permitted, isFalse);
      expect(value().canSubmit, isFalse);
      expect(value().message, isNotNull);
    });
  }

  test('a stale version reloads stock and keeps the count', () async {
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    repo.writeError = const AppFailure(
      FailureKind.conflict,
      'This product was changed on another device.',
      code: 'VERSION_CONFLICT',
    );
    await controller().save(confirmed);
    expect(repo.writes, 1);
    expect(value().phase, StockUpdatePhase.editing);
    expect(value().draft, '50');
    expect(value().message, contains('another device'));
    expect(value().canSubmit, isTrue);
  });

  test('a lost acknowledgement blocks counting until a check', () async {
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    repo.writeError = const AppFailure(FailureKind.network, 'Offline.');
    await controller().save(confirmed);
    expect(value().phase, StockUpdatePhase.uncertain);
    expect(value().canSubmit, isFalse);
    controller().changeQuantity('60');
    expect(value().draft, '50');
    repo.writeError = null;
    await controller().refresh();
    expect(value().phase, StockUpdatePhase.editing);
    expect(repo.writes, 1);
  });

  test('backend validation keeps the count editable', () async {
    controller().changeQuantity('50');
    final confirmed = controller().confirmation()!;
    repo.writeError = const AppFailure(
      FailureKind.validation,
      'Stock in packages cannot be counted here.',
      code: 'BUSINESS_RULE_VIOLATION',
    );
    await controller().save(confirmed);
    expect(value().phase, StockUpdatePhase.editing);
    expect(value().message, 'Stock in packages cannot be counted here.');
  });
}

const repoAccess = ProductAccess(adjustStock: true);

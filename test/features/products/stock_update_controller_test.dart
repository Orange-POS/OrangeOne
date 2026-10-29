import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
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

  test('add and remove keep the quantity and change the preview', () {
    controller().changeQuantity('10');
    expect(value().operation, StockOperation.update);
    expect(value().previewStock, 10);
    controller().changeOperation(StockOperation.add);
    expect(value().draft, '10');
    expect(value().previewStock, 58);
    controller().changeOperation(StockOperation.remove);
    expect(value().previewStock, 38);
    controller().changeQuantity('49');
    expect(value().fieldError?.issue, StockInputIssue.exceedsStock);
    expect(value().previewStock, isNull);
    expect(controller().confirmation(), isNull);
    controller().changeQuantity('0');
    expect(value().fieldError?.issue, StockInputIssue.zero);
    controller().changeOperation(StockOperation.update);
    expect(value().fieldError, isNull, reason: 'a count of zero is valid');
    expect(controller().confirmation(), isNotNull);
  });

  for (final (operation, expected) in [
    (StockOperation.add, 58.0),
    (StockOperation.remove, 38.0),
  ]) {
    test('${operation.name} is written with the fresh version', () async {
      controller()
        ..changeOperation(operation)
        ..changeQuantity('10');
      final confirmed = controller().confirmation()!;
      expect(confirmed.operation, operation);
      expect(confirmed.expectedStock, expected);
      await controller().save(confirmed);
      expect(repo.writtenOperation, operation);
      expect(repo.writtenCount?.text, '10');
      expect(repo.writtenVersions, ['3']);
      expect(value().phase, StockUpdatePhase.saved);
      expect(value().details.product?.stock, expected);
      expect(value().previousQuantity, 48);
      expect(value().operation, operation);
    });
  }

  test('the operation cannot change while saving or after success', () async {
    repo.pendingWrite = Completer<ProductDetails>();
    controller()
      ..changeOperation(StockOperation.add)
      ..changeQuantity('2');
    final confirmed = controller().confirmation()!;
    final saving = controller().save(confirmed);
    await Future<void>.delayed(Duration.zero);
    controller().changeOperation(StockOperation.remove);
    expect(value().operation, StockOperation.add);
    repo.pendingWrite!.complete(_with(stock: 50));
    await saving;
    controller().changeOperation(StockOperation.remove);
    expect(value().operation, StockOperation.add);
    expect(repo.writes, 1);
  });

  test('a stale confirmation of another mode is not written', () async {
    controller()
      ..changeOperation(StockOperation.add)
      ..changeQuantity('2');
    final confirmed = controller().confirmation()!;
    controller().changeOperation(StockOperation.remove);
    await controller().save(confirmed);
    expect(repo.writes, 0);
  });

  test('a removal above the stock found on save is not sent', () async {
    controller()
      ..changeOperation(StockOperation.remove)
      ..changeQuantity('40');
    final confirmed = controller().confirmation()!;
    repo.product = _with(stock: 30);
    await controller().save(confirmed);
    expect(repo.writes, 0);
    expect(value().fieldError?.issue, StockInputIssue.exceedsStock);
    expect(value().canSubmit, isFalse);
  });

  test('a lost add acknowledgement blocks a repeat until a check', () async {
    controller()
      ..changeOperation(StockOperation.add)
      ..changeQuantity('5');
    final confirmed = controller().confirmation()!;
    repo.writeError = const AppFailure(FailureKind.network, 'Offline.');
    await controller().save(confirmed);
    expect(value().phase, StockUpdatePhase.uncertain);
    expect(value().operation, StockOperation.add);
    expect(value().canSubmit, isFalse);
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

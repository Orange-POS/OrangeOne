import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

import '../../support/product_details_fakes.dart';

void main() {
  for (final entry in {
    '0': '0.00',
    '125': '125.00',
    '00125.5': '125.50',
    ' 125,25 ': '125.25',
    '0.01': '0.01',
    '999999999.99': '999999999.99',
  }.entries) {
    test('CHF input ${entry.key} preserves hundredths', () {
      expect(ChfPrice.parse(entry.key).formatted, entry.value);
    });
  }
  for (final invalid in [
    '',
    'CHF 125',
    '-1',
    'AAA',
    'NaN',
    'Infinity',
    '1e2',
    '1,000.00',
    '1.234',
    '.5',
    '1.',
    '9999999999999999999999999',
  ]) {
    test('rejects invalid or imprecise CHF input $invalid', () {
      expect(() => ChfPrice.parse(invalid), throwsFormatException);
    });
  }

  late FakeDetailsRepository repo;
  late ProviderContainer container;
  final provider = priceUpdateControllerProvider('0010101010');
  setUp(() async {
    repo = FakeDetailsRepository();
    container = ProviderContainer.test(
      overrides: [productDetailsRepositoryProvider.overrideWithValue(repo)],
    )..listen(provider, (_, _) {});
    await container.read(provider.future);
  });

  test('blank, unchanged and invalid drafts never submit', () {
    final controller = container.read(provider.notifier);
    expect(controller.confirmation(), isNull);
    for (final input in ['100', 'AAA', '-2', '125.001']) {
      controller.changePrice(input);
      expect(container.read(provider).requireValue.canSubmit, isFalse);
      expect(controller.confirmation(), isNull);
    }
    expect(repo.writes, 0);
  });

  test(
    'confirmation alone does not write; save returns authoritative product',
    () async {
      final controller = container.read(provider.notifier)
        ..changePrice('125,25');
      final confirmed = controller.confirmation()!;
      expect(repo.writes, 0);
      await controller.save(confirmed);
      final state = container.read(provider).requireValue;
      expect(repo.writes, 1);
      expect(state.phase, PriceUpdatePhase.saved);
      expect(state.details.product!.price, 125.25);
      expect(state.draft, '125.25');
    },
  );

  test(
    'duplicate submission and editing are blocked during the write',
    () async {
      repo.pendingWrite = Completer<ProductDetails>();
      final controller = container.read(provider.notifier)..changePrice('125');
      final confirmed = controller.confirmation()!;
      final saving = controller.save(confirmed);
      await Future<void>.delayed(Duration.zero);
      await controller.save(confirmed);
      controller.changePrice('500');
      expect(repo.writes, 1);
      expect(container.read(provider).requireValue.draft, '125');
      repo.pendingWrite!.complete(
        ProductDetails(
          id: detailsFixture.id,
          name: detailsFixture.name,
          barcode: detailsFixture.barcode,
          price: 125,
          stock: detailsFixture.stock,
        ),
      );
      await saving;
      expect(
        container.read(provider).requireValue.phase,
        PriceUpdatePhase.saved,
      );
    },
  );

  test(
    'changed server price requires a fresh review and confirmation',
    () async {
      final controller = container.read(provider.notifier)..changePrice('125');
      final confirmed = controller.confirmation()!;
      await repo.updatePrice(repo.product!, ChfPrice.parse('105'));
      repo.writes = 0;
      await controller.save(confirmed);
      final state = container.read(provider).requireValue;
      expect(repo.writes, 0);
      expect(state.details.product!.price, 105);
      expect(state.draft, '125');
      expect(state.message, contains('price changed'));
    },
  );

  test('revoked permission or missing product prevents the write', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    final confirmed = controller.confirmation()!;
    repo.access = const ProductAccess();
    await controller.save(confirmed);
    expect(repo.writes, 0);
    expect(container.read(provider).requireValue.canSubmit, isFalse);
    repo.product = null;
    await controller.refresh();
    expect(container.read(provider).requireValue.details.product, isNull);
  });

  test('unconfirmed write requires a read before another submission', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    repo.writeError = const AppFailure(FailureKind.timeout, 'Fixture timeout');
    await controller.save(controller.confirmation()!);
    expect(repo.writes, 1);
    expect(
      container.read(provider).requireValue.phase,
      PriceUpdatePhase.uncertain,
    );
    expect(controller.confirmation(), isNull);
    expect(container.read(provider).requireValue.draft, '125');
    repo.writeError = null;
    await controller.refresh();
    expect(repo.writes, 1);
    expect(
      container.read(provider).requireValue.phase,
      PriceUpdatePhase.editing,
    );
    expect(container.read(provider).requireValue.draft, '125');
  });

  test('forbidden write is a safe failure without fake success', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    repo.writeError = const AppFailure(
      FailureKind.forbidden,
      'Permission denied.',
    );
    await controller.save(controller.confirmation()!);
    expect(
      container.read(provider).requireValue.phase,
      PriceUpdatePhase.editing,
    );
    expect(container.read(provider).requireValue.message, 'Permission denied.');
    expect(container.read(provider).requireValue.draft, '125');
  });

  test('obsolete confirmation after draft change cannot write', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    final confirmed = controller.confirmation()!;
    controller.changePrice('130');
    await controller.save(confirmed);
    expect(repo.writes, 0);
  });

  test('disposed price workflow ignores a late write completion', () async {
    repo.pendingWrite = Completer<ProductDetails>();
    final controller = container.read(provider.notifier)..changePrice('125');
    final saving = controller.save(controller.confirmation()!);
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    repo.pendingWrite!.complete(detailsFixture);
    await saving;
    expect(repo.writes, 1);
  });

  test('the write uses the freshly verified version', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    final confirmed = controller.confirmation()!;
    await controller.save(confirmed);
    expect(repo.writtenVersions, ['3']);
    expect(container.read(provider).requireValue.details.product?.version, '4');
  });

  test('a stale version reloads the price and keeps the draft', () async {
    final controller = container.read(provider.notifier)..changePrice('125');
    final confirmed = controller.confirmation()!;
    repo.writeError = const AppFailure(
      FailureKind.conflict,
      'This product was changed on another device.',
      code: 'VERSION_CONFLICT',
    );
    await controller.save(confirmed);
    final state = container.read(provider).requireValue;
    expect(repo.writes, 1);
    expect(state.phase, PriceUpdatePhase.editing);
    expect(state.draft, '125');
    expect(state.message, contains('another device'));
    expect(state.canSubmit, isTrue);
  });
}

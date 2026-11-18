import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/capabilities/feature_resolver.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/discount_fakes.dart';

/// Each list read waits until the test answers it, so answers can arrive
/// out of order.
class _ManualDiscounts extends FakeDiscountRepository {
  final requests = <Completer<ProductDiscounts>>[];

  @override
  Future<ProductDiscounts> list(int productId) {
    lists++;
    final request = Completer<ProductDiscounts>();
    requests.add(request);
    return request.future;
  }
}

ProductDiscounts _listOf(List<Discount> discounts) => ProductDiscounts(
  productId: 10,
  regularPrice: const DiscountMoney(10000, 'CHF'),
  counts: DiscountCounts(
    total: discounts.length,
    active: discounts.length,
    scheduled: 0,
    expired: 0,
    paused: 0,
  ),
  limit: 20,
  discounts: discounts,
);

void main() {
  // Two discounts in effect: the warning shows, so a re-read is scheduled
  // within overlapRecheck.
  final overlapping = _listOf([discountOf(), discountOf(id: 2)]);
  // A single discount: nothing to recheck.
  final single = _listOf([discountOf()]);

  late _ManualDiscounts repository;
  late ProviderContainer container;
  final provider = productDiscountsControllerProvider(10);

  // Created inside each test, so the first read runs on the test's fake
  // clock.
  void start() {
    repository = _ManualDiscounts();
    container = ProviderContainer.test(
      overrides: [
        discountRepositoryProvider.overrideWithValue(repository),
        utcNowProvider.overrideWithValue(() => testNow),
        featureAvailabilityProvider.overrideWith(
          (ref, feature) =>
              FeatureAvailability(feature, FeatureStatus.available),
        ),
      ],
    )..listen(provider, (_, _) {});
  }

  testWidgets('an obsolete response finishing last schedules no refresh', (
    tester,
  ) async {
    start();
    // The first read starts, then a refresh starts a second, newer read.
    await tester.pump();
    expect(repository.requests, hasLength(1));
    container
      ..invalidate(provider)
      ..read(provider);
    await tester.pump();
    expect(repository.requests, hasLength(2));

    // The newer read answers first (no overlap: no refresh needed)...
    repository.requests[1].complete(single);
    await tester.pump();
    expect(container.read(provider).value, same(single));
    // ...then the obsolete one, whose list would need a refresh.
    repository.requests[0].complete(overlapping);
    await tester.pump();
    expect(container.read(provider).value, same(single));

    // Long after any recheck would have fired: no further read.
    await tester.pump(
      ProductDiscountsController.overlapRecheck + const Duration(minutes: 1),
    );
    expect(repository.lists, 2);
  });

  testWidgets('the current build schedules its refresh', (tester) async {
    start();
    await tester.pump();
    repository.requests[0].complete(overlapping);
    await tester.pump();
    expect(container.read(provider).value, same(overlapping));
    await tester.pump(
      ProductDiscountsController.overlapRecheck + const Duration(seconds: 1),
    );
    expect(repository.lists, 2);
  });

  testWidgets("invalidating or disposing cancels the build's timer", (
    tester,
  ) async {
    start();
    await tester.pump();
    repository.requests[0].complete(overlapping);
    await tester.pump();
    // A refresh replaces the build that registered the timer.
    container
      ..invalidate(provider)
      ..read(provider);
    await tester.pump();
    expect(repository.lists, 2);
    repository.requests[1].complete(single);
    await tester.pump();
    await tester.pump(
      ProductDiscountsController.overlapRecheck + const Duration(minutes: 1),
    );
    expect(repository.lists, 2, reason: "the first build's timer is gone");

    // Disposing the list (leaving the screen) cancels it too.
    container
      ..invalidate(provider)
      ..read(provider);
    await tester.pump();
    repository.requests[2].complete(overlapping);
    await tester.pump();
    container.dispose();
    await tester.pump(
      ProductDiscountsController.overlapRecheck + const Duration(minutes: 1),
    );
    expect(repository.lists, 3);
  });
}

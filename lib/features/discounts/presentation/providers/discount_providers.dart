import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/capabilities/feature_resolver.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/pending_discount_create.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';

/// App composition binds the signed-in shop's contract adapter; it throws
/// while signed out.
final Provider<DiscountRepository> discountRepositoryProvider =
    Provider<DiscountRepository>(
      (ref) => throw invalidSession,
      name: 'discountRepositoryProvider',
    );

/// The product a discount screen belongs to. [manageAllowed] is the
/// product's own `discount_manage` (from Product Details), composed by the
/// app so this feature never reads product internals.
@immutable
class DiscountScope {
  const new({
    required this.productId,
    required this.barcode,
    required this.manageAllowed,
  });

  final int productId;
  final String barcode;
  final bool manageAllowed;

  @override
  bool operator ==(Object other) =>
      other is DiscountScope &&
      other.productId == productId &&
      other.barcode == barcode &&
      other.manageAllowed == manageAllowed;

  @override
  int get hashCode => Object.hash(productId, barcode, manageAllowed);
}

/// What the user may do with discounts right now: the central Feature
/// Resolver (shop capability and session permissions), the product's own
/// permission and the connection. Reads need a connection too: discounts
/// are never served from the offline cache.
class DiscountAccess {
  const new({
    required this.visible,
    required this.read,
    required this.manage,
    required this.offline,
  });

  /// The shop offers discounts (`product_discounts` in `GET /meta`).
  final bool visible;

  /// `discount_read` granted.
  final bool read;

  /// `discount_manage` granted for the session and the product.
  final bool manage;
  final bool offline;

  /// Writes are possible now (never offline, never queued).
  bool get canWrite => read && manage && !offline;
}

final ProviderFamily<DiscountAccess, bool> discountAccessProvider =
    Provider.family<DiscountAccess, bool>((ref, productManage) {
      ref.watch(readCacheChangesProvider);
      final read = ref.watch(featureAvailabilityProvider(AppFeature.discounts));
      final manage = ref.watch(
        featureAvailabilityProvider(AppFeature.discountManage),
      );
      return DiscountAccess(
        visible: read.visible,
        read: read.usable,
        manage: manage.usable && productManage,
        offline: ref.watch(readCacheProvider)?.offline ?? false,
      );
    }, name: 'discountAccessProvider');

/// Thrown by discount controllers when the Feature Resolver does not allow
/// the operation (never sent to the server).
const discountUnavailable = AppFailure(
  FailureKind.forbidden,
  'Discounts are not available.',
  code: 'DISCOUNTS_UNAVAILABLE',
);

/// Discounts of one product (`GET /products/{id}/discounts`), read online
/// only while the Feature Resolver allows reading.
final AsyncNotifierProviderFamily<
  ProductDiscountsController,
  ProductDiscounts,
  int
>
productDiscountsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ProductDiscountsController, ProductDiscounts, int>(
      ProductDiscountsController.new,
      name: 'productDiscountsControllerProvider',
      retry: (count, error) => null,
    );

/// The product's unresolved create of this session, if any. Read again with
/// every list read (writes invalidate the list), so entry points can offer
/// its recovery also when the product is at its discount limit.
final ProviderFamily<PendingDiscountCreate?, int>
pendingDiscountCreateProvider = Provider.autoDispose
    .family<PendingDiscountCreate?, int>((ref, productId) {
      ref.watch(productDiscountsControllerProvider(productId));
      return ref.watch(discountRepositoryProvider).pendingCreate(productId);
    }, name: 'pendingDiscountCreateProvider');

class ProductDiscountsController extends AsyncNotifier<ProductDiscounts> {
  new(this.productId);
  final int productId;

  @override
  Future<ProductDiscounts> build() async {
    final allowed = ref.watch(
      featureAvailabilityProvider(AppFeature.discounts)
          .select((availability) => availability.usable),
    );
    if (!allowed) throw discountUnavailable;
    // Back online: read again (a list shown before stays until then).
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) ref.invalidateSelf();
    });
    return await ref.watch(discountRepositoryProvider).list(productId);
  }

  Future<void> refresh() async {
    ref.read(readCacheProvider)?.retryRead();
    ref.invalidateSelf();
    await future.catchError((Object _) => _empty);
  }

  /// Shows a discount the server just confirmed, then reads the list again
  /// for the counts (the confirmed card stays visible meanwhile).
  void replace(Discount discount) {
    final current = state.value;
    if (current == null || state.hasError) return;
    state = AsyncData(
      ProductDiscounts(
        productId: current.productId,
        regularPrice: current.regularPrice,
        counts: current.counts,
        limit: current.limit,
        discounts: [
          for (final item in current.discounts)
            if (item.id == discount.id) discount else item,
        ],
      ),
    );
    ref.invalidateSelf();
  }

  static const _empty = ProductDiscounts(
    productId: 0,
    regularPrice: DiscountMoney(0, ''),
    counts: DiscountCounts(
      total: 0,
      active: 0,
      scheduled: 0,
      expired: 0,
      paused: 0,
    ),
    limit: 0,
    discounts: [],
  );
}

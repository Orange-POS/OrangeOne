import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

/// Product discounts of the signed-in shop. Reads are always fresh from the
/// server: discounts are never part of the offline read cache, and writes
/// are never queued or replayed.
///
/// Every write carries an `Idempotency-Key` (new per intent, reused only for
/// the identical request after an uncertain outcome) and, for existing
/// discounts, `If-Match` with the [Discount.version] of a fresh read. A
/// `VERSION_CONFLICT` is never retried or overwritten.
abstract interface class DiscountRepository {
  Future<ProductDiscounts> list(int productId);

  Future<Discount> get(int discountId);

  Future<Discount> create(int productId, DiscountDraft draft);

  /// Replaces every editable value of [current] (full replacement).
  Future<Discount> update(Discount current, DiscountDraft draft);

  /// Archives (never deletes) [current].
  Future<Discount> archive(Discount current);

  Future<Discount> pause(Discount current);

  Future<Discount> resume(Discount current);
}

import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/pending_discount_create.dart';

/// Client-side refusal codes of [DiscountRepository]; neither request is
/// sent to the server.
abstract final class DiscountRefusal {
  /// A create while an earlier one for the product is unresolved.
  static const pendingCreate = 'PENDING_CREATE';

  /// The unresolved create can no longer be replayed safely.
  static const pendingCreateExpired = 'PENDING_CREATE_EXPIRED';
}

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

  /// Creates a discount. Refused ([DiscountRefusal.pendingCreate]) while an
  /// earlier create for [productId] is unresolved ([pendingCreate]).
  Future<Discount> create(int productId, DiscountDraft draft);

  /// The unresolved create for [productId] in this session, if any. It
  /// survives forms closing and reopening; it never crosses sessions.
  PendingDiscountCreate? pendingCreate(int productId);

  /// Settles the unresolved create for [productId] by replaying it exactly
  /// as sent (same body, same `Idempotency-Key`). Returns the discount the
  /// server committed or creates now. A definitive refusal removes it and is
  /// rethrown; an open outcome (no answer, authentication, rate limit)
  /// keeps it. Refused ([DiscountRefusal.pendingCreateExpired]) when it
  /// can no longer be replayed safely.
  Future<Discount> resolvePendingCreate(int productId);

  /// Drops the unresolved create for [productId] on the user's explicit
  /// decision, after checking the product's discounts. Only for one that is
  /// no longer [PendingDiscountCreate.replayable].
  void discardPendingCreate(int productId);

  /// Replaces every editable value of [current] (full replacement).
  Future<Discount> update(Discount current, DiscountDraft draft);

  /// Archives (never deletes) [current].
  Future<Discount> archive(Discount current);

  Future<Discount> pause(Discount current);

  Future<Discount> resume(Discount current);
}

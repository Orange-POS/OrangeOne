import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';

/// A discount create for one product that was sent without a confirmed
/// answer. It may have committed, may still commit, or never reached the
/// server; only replaying it unchanged can tell. Until then no other create
/// for the product is sent.
class PendingDiscountCreate {
  const new({
    required this.draft,
    required this.replayable,
    this.committed = false,
  });

  /// The draft exactly as it was sent.
  final DiscountDraft draft;

  /// False once the server's idempotency record may have expired: a replay
  /// could then run as a new request, so the user decides after checking
  /// the product's discounts.
  final bool replayable;

  /// The server accepted it (a success reply) but its result could not be
  /// read: it was most likely created. Not [replayable] (a replay would
  /// return the same reply); no other create is sent until the user checked
  /// the product's discounts and resolves it explicitly.
  final bool committed;
}

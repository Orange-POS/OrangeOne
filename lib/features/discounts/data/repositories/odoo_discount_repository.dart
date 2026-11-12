import 'dart:convert';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/pending_writes.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/models/discount_model.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/entities/pending_discount_create.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';

/// [DiscountRepository] over the Mobile API v1 contract (1.1 additions).
/// Online only: nothing is cached or queued. A create without a confirmed
/// answer stays in the session's [PendingWrites] exactly as sent, and is
/// only ever replayed unchanged on the user's next save.
class OdooDiscountRepository implements DiscountRepository {
  new(
    this._remote, {
    IdempotencyKeys? idempotencyKeys,
    PendingWrites? pendingWrites,
    this.onSessionRejected,
  }) : _keys = idempotencyKeys ?? IdempotencyKeys(),
       _pending = pendingWrites ?? PendingWrites();

  final DiscountRemoteDataSource _remote;
  final IdempotencyKeys _keys;

  /// The session's unresolved creates; shared by every repository instance
  /// of the session, so a rebuild (or a form closing) never loses one.
  final PendingWrites _pending;

  /// Called when the server rejects the session (token revoked or invalid).
  final Future<void> Function()? onSessionRejected;

  Future<T> _call<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.unauthenticated) {
        await onSessionRejected?.call();
      }
      rethrow;
    }
  }

  /// A write that may only be repeated as the identical request.
  Future<Discount> _write(
    String operation,
    Future<MobileApiResponse> Function(String key) send, {
    int? expectedId,
  }) => _call(
    () => _keys.run(operation, (key) async {
      final discount = DiscountModel.parse((await send(key)).data);
      if (expectedId != null && discount.id != expectedId) {
        throw invalidResponse;
      }
      return discount;
    }),
  );

  @override
  Future<ProductDiscounts> list(int productId) => _call(() async {
    final result = DiscountModel.parseList(
      (await _remote.list(productId)).data,
    );
    if (result.productId != productId ||
        result.discounts.any((discount) => discount.productId != productId)) {
      throw invalidResponse;
    }
    return result;
  });

  @override
  Future<Discount> get(int discountId) => _call(() async {
    final discount = DiscountModel.parse((await _remote.get(discountId)).data);
    if (discount.id != discountId) throw invalidResponse;
    return discount;
  });

  static String _slot(int productId) => 'discount-create:product:$productId';

  static const _pendingCreate = AppFailure(
    FailureKind.conflict,
    'An earlier discount create for this product is not confirmed yet.',
    code: DiscountRefusal.pendingCreate,
  );

  static const _pendingCommitted = AppFailure(
    FailureKind.protocol,
    'The discount was received, but its result could not be read.',
    code: DiscountRefusal.pendingCreateCommitted,
  );

  static const _pendingExpired = AppFailure(
    FailureKind.conflict,
    'An earlier discount create can no longer be confirmed automatically.',
    code: DiscountRefusal.pendingCreateExpired,
  );

  @override
  Future<Discount> create(int productId, DiscountDraft draft) async {
    final slot = _slot(productId);
    // Refused before anything is sent: one unresolved create per product.
    if (_pending[slot] != null) throw _pendingCreate;
    final write = _pending.begin(
      slot: slot,
      method: 'POST',
      path: '/products/$productId/discounts',
      body: jsonEncode(DiscountInputModel.toJson(draft)),
      key: _keys.newKey(),
      intent: draft,
    );
    return await _sendCreate(productId, write);
  }

  @override
  PendingDiscountCreate? pendingCreate(int productId) {
    final write = _pending[_slot(productId)];
    final draft = write?.intent;
    if (write == null || draft is! DiscountDraft) return null;
    return PendingDiscountCreate(
      draft: draft,
      replayable: _pending.replayable(write),
      committed: _pending.committed(write),
    );
  }

  @override
  Future<Discount> resolvePendingCreate(int productId) async {
    final write = _pending[_slot(productId)];
    if (write == null) throw StateError('No pending create for $productId.');
    if (_pending.committed(write)) throw _pendingCommitted;
    if (!_pending.replayable(write)) throw _pendingExpired;
    return await _sendCreate(productId, write);
  }

  @override
  void discardPendingCreate(int productId) {
    final write = _pending[_slot(productId)];
    // Only the user's explicit decision, and only once it cannot be
    // replayed safely: a replayable one is settled by replaying it.
    if (write != null && !_pending.replayable(write)) _pending.settle(write);
  }

  /// Sends [write] exactly as recorded: the stored body and key, never
  /// rebuilt. The outcome decides whether it stays pending.
  Future<Discount> _sendCreate(int productId, PendingWrite write) =>
      _call(() async {
        final MobileApiResponse response;
        try {
          final body = jsonDecode(write.body) as Map<String, dynamic>;
          response = await _remote.create(
            productId,
            body,
            idempotencyKey: write.key,
          );
        } on AppFailure catch (failure) {
          // A server decision about this request settles it; no answer, a
          // cancellation, authentication or a rate limit leave it open.
          if (IdempotencyKeys.settles(failure)) _pending.settle(write);
          rethrow;
        }
        // A success envelope: the server committed it (or replayed that
        // commit). A result that is off contract (unreadable, or for another
        // product) is not a confirmed discount, and a replay would only
        // return the same stored reply: the create stays in its slot as
        // committed, blocking any other create for the product until the
        // user checked its discounts and resolves it.
        final Discount discount;
        try {
          discount = DiscountModel.parse(response.data);
          if (discount.productId != productId) throw invalidResponse;
        } on Object {
          _pending.markCommitted(write);
          throw _pendingCommitted;
        }
        _pending.settle(write);
        return discount;
      });

  @override
  Future<Discount> update(Discount current, DiscountDraft draft) {
    final body = DiscountInputModel.toJson(draft);
    return _write(
      'PUT /discounts/${current.id} ${current.version} ${jsonEncode(body)}',
      (key) => _remote.update(
        current.id,
        body,
        version: current.version,
        idempotencyKey: key,
      ),
      expectedId: current.id,
    );
  }

  @override
  Future<Discount> archive(Discount current) => _write(
    'DELETE /discounts/${current.id} ${current.version}',
    (key) => _remote.archive(
      current.id,
      version: current.version,
      idempotencyKey: key,
    ),
    expectedId: current.id,
  );

  @override
  Future<Discount> pause(Discount current) => _setPaused(current, true);

  @override
  Future<Discount> resume(Discount current) => _setPaused(current, false);

  Future<Discount> _setPaused(Discount current, bool paused) => _write(
    'POST /discounts/${current.id}/${paused ? 'pause' : 'resume'} '
    '${current.version}',
    (key) => _remote.setPaused(
      current.id,
      paused: paused,
      version: current.version,
      idempotencyKey: key,
    ),
    expectedId: current.id,
  );
}

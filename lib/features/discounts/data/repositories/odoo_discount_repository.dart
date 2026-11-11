import 'dart:convert';

import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/features/discounts/data/data_sources/discount_remote_data_source.dart';
import 'package:orange_one/features/discounts/data/models/discount_model.dart';
import 'package:orange_one/features/discounts/domain/entities/discount.dart';
import 'package:orange_one/features/discounts/domain/entities/discount_draft.dart';
import 'package:orange_one/features/discounts/domain/repositories/discount_repository.dart';

/// [DiscountRepository] over the Mobile API v1 contract (1.1 additions).
/// Online only: nothing is cached, queued or replayed.
class OdooDiscountRepository implements DiscountRepository {
  new(this._remote, {IdempotencyKeys? idempotencyKeys, this.onSessionRejected})
    : _keys = idempotencyKeys ?? IdempotencyKeys();

  final DiscountRemoteDataSource _remote;
  final IdempotencyKeys _keys;

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

  @override
  Future<Discount> create(int productId, DiscountDraft draft) {
    final body = DiscountInputModel.toJson(draft);
    return _call(
      () => _keys.run(
        'POST /products/$productId/discounts ${jsonEncode(body)}',
        (key) async {
          final discount = DiscountModel.parse(
            (await _remote.create(productId, body, idempotencyKey: key)).data,
          );
          if (discount.productId != productId) throw invalidResponse;
          return discount;
        },
      ),
    );
  }

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

import 'package:dio/dio.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';

/// The discount endpoints of the Mobile API 1.1 (`mupi_mobile_pos_api` with
/// `mupi_product_discount`). Called only when `GET /meta` lists
/// `product_discounts`; the same v1 envelope, headers and error codes as
/// every other endpoint.
class DiscountRemoteDataSource {
  const new(this._api, {this.cancelToken});

  final AuthenticatedMobileApi _api;
  final CancelToken? cancelToken;

  /// `GET /products/{id}/discounts` (archived discounts left out).
  Future<MobileApiResponse> list(int productId) => _api.send(
    MobileApiMethod.get,
    '/products/$productId/discounts',
    cancelToken: cancelToken,
  );

  /// `GET /discounts/{id}`: a fresh read with the current `version`.
  Future<MobileApiResponse> get(int discountId) => _api.send(
    MobileApiMethod.get,
    '/discounts/$discountId',
    cancelToken: cancelToken,
  );

  /// `POST /products/{id}/discounts`.
  Future<MobileApiResponse> create(
    int productId,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.post,
    '/products/$productId/discounts',
    body: body,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `PUT /discounts/{id}`: full replacement guarded by [version].
  Future<MobileApiResponse> update(
    int discountId,
    Map<String, dynamic> body, {
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.put,
    '/discounts/$discountId',
    body: body,
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `DELETE /discounts/{id}`: archives, never deletes.
  Future<MobileApiResponse> archive(
    int discountId, {
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.delete,
    '/discounts/$discountId',
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `POST /discounts/{id}/pause` or `/resume`, with the empty body `{}`.
  Future<MobileApiResponse> setPaused(
    int discountId, {
    required bool paused,
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.post,
    '/discounts/$discountId/${paused ? 'pause' : 'resume'}',
    body: const {},
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );
}

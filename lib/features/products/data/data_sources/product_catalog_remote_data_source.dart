import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/product_payload.dart';

/// Mobile API v2 product reads, writes and references, plus session
/// permissions.
class ProductCatalogRemoteDataSource {
  const new(this._api, {required this.cancelToken});
  final AuthenticatedMobileApi _api;
  final CancelToken cancelToken;

  Future<MobileApiResponse> byBarcode(String barcode) => _api.send(
    MobileApiMethod.get,
    ProductPayload.byBarcodePath(barcode),
    cancelToken: cancelToken,
  );

  /// Conditional when [etag] is given: a 304 response has no data.
  Future<MobileApiResponse> byId(int id, {String? etag}) => _api.send(
    MobileApiMethod.get,
    '/products/$id',
    ifNoneMatch: etag,
    cancelToken: cancelToken,
  );

  Future<MobileApiResponse> search({
    String? query,
    int? categoryId,
    String? cursor,
    int? limit,
  }) => _api.send(
    MobileApiMethod.get,
    '/products',
    query: {
      'q': ?query,
      'category_id': ?categoryId?.toString(),
      'cursor': ?cursor,
      'limit': ?limit?.toString(),
    },
    cancelToken: cancelToken,
  );

  /// Effective permissions of the session (`GET /auth/session`), used when no
  /// product payload carries them.
  Future<Object?> sessionPermissions() async {
    final response = await _api.send(
      MobileApiMethod.get,
      '/auth/session',
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) throw invalidResponse;
    return data['permissions'];
  }

  /// `GET /taxes`: active sale taxes of the session company.
  Future<Object?> taxes() async => (await _api.send(
    MobileApiMethod.get,
    '/taxes',
    cancelToken: cancelToken,
  )).data;

  /// `GET /categories` (one page of up to [limit] categories).
  Future<MobileApiResponse> categories({String? cursor, int limit = 100}) =>
      _api.send(
        MobileApiMethod.get,
        '/categories',
        query: {'cursor': ?cursor, 'limit': '$limit'},
        cancelToken: cancelToken,
      );

  /// `POST /products`: creates a product, never upserts.
  Future<MobileApiResponse> create(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.post,
    '/products',
    body: body,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `PATCH /products/{id}` guarded by the product JSON [version].
  Future<MobileApiResponse> update(
    int id,
    Map<String, dynamic> body, {
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.patch,
    '/products/$id',
    body: body,
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `PUT /products/{id}/price` guarded by the product JSON [version].
  Future<MobileApiResponse> updatePrice(
    int id,
    String listPrice, {
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.put,
    '/products/$id/price',
    body: {'list_price': listPrice},
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `POST /products/{id}/stock-adjustments` guarded by the product JSON
  /// [version]: sets the counted quantity at the POS stock location.
  Future<MobileApiResponse> adjustStock(
    int id,
    Map<String, dynamic> body, {
    required String version,
    required String idempotencyKey,
  }) => _api.send(
    MobileApiMethod.post,
    '/products/$id/stock-adjustments',
    body: body,
    ifMatchVersion: version,
    idempotencyKey: idempotencyKey,
    cancelToken: cancelToken,
  );

  /// `GET /products/changes`: changed and removed readable products since
  /// a position (`next_since` or an RFC 3339 time).
  Future<MobileApiResponse> changes(String since, {int limit = 100}) =>
      _api.send(
        MobileApiMethod.get,
        '/products/changes',
        query: {'since': since, 'limit': '$limit'},
        cancelToken: cancelToken,
      );
}

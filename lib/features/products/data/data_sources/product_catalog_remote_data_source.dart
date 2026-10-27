import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/product_payload.dart';

/// Mobile API v2 product reads (`/products…`) and session permissions.
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
}

import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/core/network/product_payload.dart';

class ProductRemoteDataSource {
  const new(this._api, {required this.cancelToken});
  final AuthenticatedMobileApi _api;
  final CancelToken cancelToken;

  /// `GET /products/by-barcode/{barcode}` as a product read record, or null
  /// when no POS product has this barcode (`PRODUCT_NOT_FOUND`).
  Future<Map<String, dynamic>?> findByBarcode(String barcode) async {
    final path = ProductPayload.byBarcodePath(barcode);
    try {
      final response = await _api.send(
        MobileApiMethod.get,
        path,
        cancelToken: cancelToken,
      );
      return ProductPayload.productRecord(response.data);
    } on AppFailure catch (failure) {
      if (failure.code == 'PRODUCT_NOT_FOUND') return null;
      rethrow;
    }
  }
}

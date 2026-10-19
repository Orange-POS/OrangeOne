import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';

class ProductDetailsRemoteDataSource {
  const new(
    this.client, {
    required this.origin,
    required this.token,
    required this.cancelToken,
  });
  final JsonRpcClient client;
  final Uri origin;
  final String token;
  final CancelToken cancelToken;

  Future<Map<String, dynamic>> call(
    String path, [
    Map<String, dynamic> params = const {},
  ]) async {
    final result = await client.call(
      path,
      backendOrigin: origin,
      accessToken: token,
      cancelToken: cancelToken,
      params: params,
    );
    if (result['ok'] == true) return result;
    final error = result['error'];
    if (result['ok'] != false || error is! String) throw invalidResponse;
    if (error == 'Barcode already exists.') {
      throw const AppFailure(
        FailureKind.conflict,
        'This barcode already exists. Open its product details.',
      );
    }
    if (error == 'Select valid product taxes.' ||
        error == 'Product name is required.' ||
        error == 'Valid product price is required.' ||
        error == 'Price cannot be negative.') {
      throw const AppFailure(
        FailureKind.validation,
        'Check the product name, price and tax selection.',
      );
    }
    if (error == 'Token does not have required permission.' ||
        error == 'Product is not allowed for this POS company.') {
      throw const AppFailure(
        FailureKind.forbidden,
        'You do not have permission for this product action.',
      );
    }
    if (const {
      'Missing access token.',
      'Invalid token format.',
      'Invalid token signature.',
      'Invalid token payload.',
      'Token has expired.',
      'Invalid token identifier.',
      'Token not found.',
      'Token does not match stored record.',
      'Token is not active.',
      'POS session is no longer opened.',
    }.contains(error)) {
      throw invalidSession;
    }
    throw const AppFailure(
      FailureKind.backend,
      'The server could not complete this product action. Refresh the product.',
    );
  }
}

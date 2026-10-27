import 'package:dio/dio.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/json_rpc_client.dart';

class ProductRemoteDataSource {
  const new(
    this._client, {
    required this.origin,
    required this.accessToken,
    required this.cancelToken,
  });
  final JsonRpcClient _client;
  final Uri origin;

  /// Current access token of the session, read for every request.
  final Future<String> Function() accessToken;
  final CancelToken cancelToken;

  Future<Map<String, dynamic>> find(String barcode) async => await _client.call(
    '/mupi/mobile/api/products/find',
    backendOrigin: origin,
    accessToken: await accessToken(),
    params: {'barcode': barcode},
    cancelToken: cancelToken,
  );

  static void checkResult(Map<String, dynamic> result) {
    if (result['ok'] == true) return;
    final error = result['error'];
    if (result['ok'] != false || error is! String) throw invalidResponse;
    if (error == 'Token does not have required permission.') {
      throw const AppFailure(
        FailureKind.forbidden,
        'You do not have permission to look up products. '
        'Contact your administrator.',
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
    if (error == 'Barcode is required.') {
      throw const AppFailure(
        FailureKind.validation,
        'Scan a valid product barcode.',
      );
    }
    throw const AppFailure(
      FailureKind.backend,
      'The server could not look up this product. Contact your administrator.',
    );
  }
}

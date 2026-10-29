import 'package:dio/dio.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';

import 'auth_fakes.dart';
import 'mobile_api_fakes.dart';

/// Mobile API v2 `Permissions`; every key granted unless overridden.
Map<String, bool> productPermissions([
  Map<String, bool> overrides = const {},
]) => {
  for (final key in const [
    'product_read',
    'product_create',
    'product_update_name',
    'product_update_taxes',
    'product_update_category',
    'product_update_price',
    'stock_adjust',
    'category_create',
    'product_history_read',
  ])
    key: true,
  ...overrides,
};

/// A v2 `Product` payload matching the Home and details fixtures.
Map<String, dynamic> v2Product({
  int id = 10,
  String? barcode = '0010101010',
  String name = 'Aachi Fish Fry Masala',
  String price = '100.00',
  String? quantity = '48.000',
  String version = '3',
  Map<String, bool>? permissions,
}) => {
  'id': id,
  'template_id': 20,
  'name': name,
  'description': 'The Key to Crispy, Flavorful Fish',
  'barcode': barcode,
  'default_code': 'MASALA',
  'list_price': {'amount': price, 'currency': 'CHF'},
  'taxes': [
    {
      'id': 7,
      'name': 'VAT',
      'amount': '8.1',
      'amount_type': 'percent',
      'price_include': false,
    },
  ],
  'category': {
    'id': 4,
    'name': 'Spices',
    'parent_id': null,
    'complete_name': 'All / Spices',
  },
  'stock': {
    'tracked': quantity != null,
    'quantity': quantity,
    'uom': {'id': 1, 'name': 'Units', 'rounding': '0.01'},
    'location_id': 8,
    'adjustable': quantity != null,
  },
  'available_in_pos': true,
  'active': true,
  'version': version,
  'updated_at': '2026-10-27T08:00:00Z',
  'permissions': permissions ?? productPermissions(),
};

/// `GET /auth/session` data carrying [permissions].
Map<String, dynamic> sessionData(Map<String, bool> permissions) => {
  'session_id': testSession.sessionId,
  'permissions': permissions,
};

/// Fixed access tokens for repository tests.
class StaticTokens implements AccessTokenSource {
  @override
  Future<String> accessToken() async => 'oa_fixture';

  @override
  Future<String> refreshAccessToken(String rejectedToken) async => 'oa_fixture';
}

/// An [AuthenticatedMobileApi] served by [server] through a real Dio stack.
AuthenticatedMobileApi fakeProductApi(
  FakeMobileApiServer server, {
  AccessTokenSource? tokens,
}) {
  final dio = Dio()..httpClientAdapter = server;
  return AuthenticatedMobileApi(
    MobileApiClient(
      dio,
      const ApiConfiguration(
        baseUrl: '',
        environment: AppEnvironment.development,
      ),
    ),
    apiBase: testApiBase,
    tokens: tokens ?? StaticTokens(),
  );
}

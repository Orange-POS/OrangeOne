import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/authenticated_mobile_api.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/network/mobile_api_client.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/demo/domain/entities/demo_sample.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';

import '../../support/auth_fakes.dart';

/// `GET /meta` answers per shop (api base); a missing entry fails.
class _Api implements AuthenticatedMobileApi {
  new(this.apiBase, this._shops, this.calls);

  @override
  final Uri apiBase;
  final Map<Uri, Object> _shops;
  final List<Uri> calls;

  @override
  Future<MobileApiResponse> send(
    MobileApiMethod method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? language,
    String? idempotencyKey,
    String? ifMatchVersion,
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) async {
    expect((method, path), (MobileApiMethod.get, '/meta'));
    calls.add(apiBase);
    final answer = _shops[apiBase];
    if (answer is AppFailure) throw answer;
    return MobileApiResponse(statusCode: 200, data: answer);
  }
}

class _Session extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  AuthSession? get session => state;
  set session(AuthSession? value) => state = value;
}

final NotifierProvider<_Session, AuthSession?> _sessionProvider =
    NotifierProvider<_Session, AuthSession?>(_Session.new);

final Uri _older = Uri.parse(
  'https://older-shop.example/api/orangeone/mobile/v1',
);
final Uri _newer = Uri.parse(
  'https://newer-shop.example/api/orangeone/mobile/v1',
);

AuthSession _at(Uri apiBase, String family) => AuthSession(
  accessToken: 'oa_fixture',
  apiBase: apiBase,
  expiresAt: testNow.add(const Duration(days: 1)),
  sessionId: family,
  userId: 2,
  posConfigId: 1,
  companyId: 1,
  posSessionId: 1,
);

Map<String, Object?> _meta(List<String> features) => {
  'api_version': '1.0.0',
  'features': features,
};

void main() {
  late Map<Uri, Object> shops;
  late List<Uri> calls;
  late ProviderContainer container;

  setUp(() {
    shops = {
      _older: _meta(['stock_adjustments', 'categories']),
      _newer: _meta(['stock_adjustments', 'categories', 'stock_movements']),
    };
    calls = [];
    container = ProviderContainer.test(
      overrides: [
        activeSessionProvider.overrideWith(
          (ref) => ref.watch(_sessionProvider),
        ),
        authenticatedMobileApiProvider.overrideWith((ref) {
          final session = ref.watch(activeSessionProvider);
          if (session == null) throw invalidSession;
          return _Api(session.apiBase, shops, calls);
        }),
        backendFeaturesOverride,
      ],
    );
  });

  /// The features while one screen listens; the listener closes afterwards,
  /// like a screen that is left (auto-dispose state).
  Future<BackendFeatures> features() async {
    final subscription = container.listen(backendFeaturesProvider, (_, _) {});
    try {
      return await container.read(backendFeaturesProvider.future);
    } finally {
      subscription.close();
      await container.pump();
    }
  }

  void signIn(AuthSession? session) =>
      container.read(_sessionProvider.notifier).session = session;

  test('signed out: the baseline, without any request', () async {
    expect(await features(), same(BackendFeatures.baseline));
    expect(calls, isEmpty);
  });

  test(
    'each shop shows its own features; switching never mixes them',
    () async {
      signIn(_at(_older, 'a'));
      expect((await features()).supports('stock_movements'), isFalse);
      signIn(_at(_newer, 'b'));
      expect((await features()).supports('stock_movements'), isTrue);
      signIn(_at(_older, 'c'));
      expect((await features()).supports('stock_movements'), isFalse);
      expect(calls, [_older, _newer, _older]);
    },
  );

  test('a session reads /meta once and keeps the answer', () async {
    signIn(_at(_newer, 'b'));
    await features();
    await features();
    expect(calls, [_newer]);
  });

  test(
    'a failure falls back to the baseline and is read again later',
    () async {
      shops[_newer] = const AppFailure(FailureKind.network, 'offline');
      signIn(_at(_newer, 'b'));
      expect(await features(), same(BackendFeatures.baseline));
      // Not kept: once the screen closed, the next one asks again.
      await container.pump();
      shops[_newer] = _meta(['stock_movements']);
      expect((await features()).supports('stock_movements'), isTrue);
      expect(calls, [_newer, _newer]);
    },
  );

  test('refusals are definitive answers for the compatibility check', () async {
    shops[_newer] = const AppFailure(
      FailureKind.upgradeRequired,
      'Update the app.',
      code: 'APP_UPGRADE_REQUIRED',
    );
    signIn(_at(_newer, 'b'));
    final upgrade = await features();
    expect(upgrade.refusal, BackendRefusal.appUpgradeRequired);
    expect(upgrade.confirmed, isTrue);
    expect(upgrade.supports('stock_movements'), isFalse);

    shops[_older] = const AppFailure(
      FailureKind.network,
      'Maintenance.',
      code: 'MAINTENANCE',
    );
    signIn(_at(_older, 'c'));
    expect((await features()).refusal, BackendRefusal.maintenance);
  });

  test('transport failures are never refusals', () async {
    shops[_newer] = const AppFailure(FailureKind.network, 'offline');
    signIn(_at(_newer, 'b'));
    expect((await features()).refusal, isNull);
  });

  test('an unreadable reply is the baseline, not a crash', () async {
    shops[_newer] = {'features': 'all'};
    signIn(_at(_newer, 'b'));
    expect(await features(), same(BackendFeatures.baseline));
  });

  test('Demo Mode supports its features without any request', () async {
    container.read(demoModeProvider.notifier).enable();
    container.read(demoLoginProvider.notifier).signIn(DemoSample.manager);
    expect((await features()).supports('stock_movements'), isTrue);
    expect(calls, isEmpty);
  });

  test('only answers from the shop or Demo Mode are confirmed', () async {
    expect(BackendFeatures.baseline.confirmed, isFalse);
    signIn(_at(_newer, 'b'));
    expect((await features()).confirmed, isTrue);
  });

  test(
    'with Product Details still listening, the Stock screen recovers',
    () async {
      shops[_newer] = const AppFailure(FailureKind.network, 'offline');
      signIn(_at(_newer, 'b'));
      // Product Details: attached first, stays mounted under the Stock screen.
      final details = container.listen(backendFeaturesProvider, (_, _) {});
      addTearDown(details.close);
      final fallback = await container.read(backendFeaturesProvider.future);
      expect(fallback.confirmed, isFalse);
      expect(fallback.supports('stock_movements'), isFalse);

      // Connectivity returns; the Stock screen opens above Product Details and
      // asks again because the features are unconfirmed.
      shops[_newer] = _meta(['stock_movements']);
      final stock = container.listen(backendFeaturesProvider, (_, _) {});
      addTearDown(stock.close);
      container.invalidate(backendFeaturesProvider);
      final recovered = await container.read(backendFeaturesProvider.future);
      expect(recovered.confirmed, isTrue);
      expect(recovered.supports('stock_movements'), isTrue);
      expect(details.read().value?.supports('stock_movements'), isTrue);
      expect(calls, [_newer, _newer]);
    },
  );
}

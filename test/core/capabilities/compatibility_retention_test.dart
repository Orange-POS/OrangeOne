import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/providers/product_dependencies.dart';
import 'package:orange_one/app/providers/session_lifecycle_bindings.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';

import '../../support/auth_fakes.dart';

class _Session extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  AuthSession? get session => state;
  set session(AuthSession? value) => state = value;
}

final NotifierProvider<_Session, AuthSession?> _sessionProvider =
    NotifierProvider<_Session, AuthSession?>(_Session.new);

final Uri _shopA = Uri.parse('https://shop-a.example/api/orangeone/mobile/v1');
final Uri _shopB = Uri.parse('https://shop-b.example/api/orangeone/mobile/v1');

AuthSession _session(Uri apiBase, String family) => AuthSession(
  accessToken: 'oa_fixture',
  apiBase: apiBase,
  expiresAt: testNow.add(const Duration(days: 1)),
  sessionId: family,
  userId: 2,
  posConfigId: 1,
  companyId: 1,
  posSessionId: 1,
);

final _refused = BackendFeatures.refused(BackendRefusal.appUpgradeRequired);
final _compatible = BackendFeatures(
  BackendFeatures.baseline.names,
  apiVersion: '1.1.0',
  confirmed: true,
);

void main() {
  /// The answer `GET /meta` gives next, per session family; a pending
  /// completer models a slow reply.
  late Map<String, FutureOr<BackendFeatures> Function()> answers;
  late ProviderContainer container;

  setUp(() {
    answers = {};
    container = ProviderContainer.test(
      overrides: [
        environmentProvider.overrideWithValue(AppEnvironment.development),
        activeSessionProvider.overrideWith(
          (ref) => ref.watch(_sessionProvider),
        ),
        capabilityScopeOverride,
        backendFeaturesProvider.overrideWith((ref) async {
          final session = ref.watch(activeSessionProvider);
          if (session == null) return BackendFeatures.baseline;
          return await answers[session.sessionId]!();
        }),
      ],
    )..listen(compatibilityProvider, (_, _) {});
  });

  Future<CompatibilityStatus> settle() async {
    for (var i = 0; i < 5; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }
    final status = container.read(compatibilityProvider);
    return status;
  }

  void signIn(AuthSession? session) =>
      container.read(_sessionProvider.notifier).session = session;

  Future<CompatibilityStatus> retry() {
    container.invalidate(backendFeaturesProvider);
    return settle();
  }

  test('refused, then a failed retry: still blocked', () async {
    answers['a'] = () => _refused;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.appUpgradeRequired);

    // Network failure, timeout or unreadable reply: the unconfirmed baseline.
    answers['a'] = () => BackendFeatures.baseline;
    expect(await retry(), CompatibilityStatus.appUpgradeRequired);
    // Also while the retry is still pending.
    final pending = Completer<BackendFeatures>();
    answers['a'] = () => pending.future;
    expect(await retry(), CompatibilityStatus.appUpgradeRequired);
    pending.complete(BackendFeatures.baseline);
    expect(await settle(), CompatibilityStatus.appUpgradeRequired);
  });

  test('refused, then a compatible answer: proceeds', () async {
    answers['a'] = () => BackendFeatures.refused(BackendRefusal.maintenance);
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.maintenance);
    answers['a'] = () => _compatible;
    expect(await retry(), CompatibilityStatus.compatible);
    // A later failure keeps the confirmed compatible state.
    answers['a'] = () => BackendFeatures.baseline;
    expect(await retry(), CompatibilityStatus.compatible);
  });

  test('a replacement session starts without the previous refusal', () async {
    answers['a'] = () => _refused;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.appUpgradeRequired);

    // Same shop, new session family whose /meta is unreadable.
    answers['b'] = () => BackendFeatures.baseline;
    signIn(_session(_shopA, 'b'));
    expect(await settle(), CompatibilityStatus.compatible);
  });

  test('another backend starts without the previous refusal', () async {
    answers['a'] = () => _refused;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.appUpgradeRequired);
    answers['a'] = () => _compatible;
    signIn(_session(_shopB, 'a'));
    expect(await settle(), CompatibilityStatus.compatible);
  });

  test('signing out clears the refusal', () async {
    answers['a'] = () => _refused;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.appUpgradeRequired);
    signIn(null);
    expect(await settle(), CompatibilityStatus.compatible);
    answers['a'] = () => BackendFeatures.baseline;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.compatible);
  });

  test(
    'a stale refusal of a replaced session never blocks the new one',
    () async {
      final slow = Completer<BackendFeatures>();
      answers['a'] = () => slow.future;
      signIn(_session(_shopA, 'a'));
      expect(await settle(), CompatibilityStatus.compatible);

      answers['b'] = () => _compatible;
      signIn(_session(_shopB, 'b'));
      expect(await settle(), CompatibilityStatus.compatible);
      slow.complete(_refused);
      expect(await settle(), CompatibilityStatus.compatible);
    },
  );

  test('the first unavailable check keeps the safe fallback', () async {
    answers['a'] = () => BackendFeatures.baseline;
    signIn(_session(_shopA, 'a'));
    expect(await settle(), CompatibilityStatus.compatible);
  });
}

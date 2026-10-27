import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';

import '../../../support/auth_fakes.dart';

void main() {
  testWidgets('session expiry clears local authentication automatically', (
    tester,
  ) async {
    var now = testNow;
    final repository = FakeAuthRepository()
      ..restored = AuthSession(
        accessToken: testSession.accessToken,
        apiBase: testSession.apiBase,
        expiresAt: testNow.add(const Duration(seconds: 1)),
        sessionId: testSession.sessionId,
        userId: 2,
        posSessionId: 106,
        posConfigId: 1,
        companyId: 1,
      );
    final scope = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        utcNowProvider.overrideWithValue(() => now),
      ],
    );
    await scope.read(sessionControllerProvider.future);
    expect(scope.read(sessionControllerProvider).value, isNotNull);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await scope.pump();
    expect(scope.read(sessionControllerProvider).value, isNull);
    expect(repository.signOuts, 1);
  });

  late FakeAuthRepository repository;
  late ProviderContainer container;
  setUp(() {
    repository = FakeAuthRepository();
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        utcNowProvider.overrideWithValue(() => testNow),
      ],
    );
  });

  test('restores once and prevents concurrent login operations', () async {
    await container.read(sessionControllerProvider.future);
    repository.pendingLogin = Completer<AuthSession>();
    final first = container
        .read(sessionControllerProvider.notifier)
        .signIn('fixture QR');
    final duplicate = await container
        .read(sessionControllerProvider.notifier)
        .signIn('fixture QR');
    expect(duplicate, isFalse);
    expect(repository.signIns, 1);
    expect(container.read(sessionControllerProvider).isLoading, isTrue);
    repository.pendingLogin!.complete(testSession);
    expect(await first, isTrue);
    expect(container.read(sessionControllerProvider).value?.userId, 2);
    expect(repository.restores, 1);
  });

  test('logout during login prevents stale authenticated state', () async {
    await container.read(sessionControllerProvider.future);
    repository.pendingLogin = Completer<AuthSession>();
    final login = container
        .read(sessionControllerProvider.notifier)
        .signIn('fixture QR');
    await container.read(sessionControllerProvider.notifier).signOut();
    repository.pendingLogin!.complete(testSession);
    expect(await login, isFalse);
    expect(container.read(sessionControllerProvider).value, isNull);
    expect(repository.signOuts, 1);
  });

  test(
    'invalid input never calls repository and exposes safe failure',
    () async {
      await container.read(sessionControllerProvider.future);
      expect(
        await container.read(sessionControllerProvider.notifier).signIn(''),
        isFalse,
      );
      expect(repository.signIns, 0);
      expect(container.read(sessionControllerProvider).error, same(invalidQr));
      container.read(sessionControllerProvider.notifier).clearLoginFailure();
      expect(container.read(sessionControllerProvider).hasError, isFalse);
    },
  );

  test('restoration failure is not automatically retried', () async {
    repository.failure = storageFailure;
    await expectLater(
      container.read(sessionControllerProvider.future),
      throwsA(same(storageFailure)),
    );
    await container.pump();
    expect(repository.restores, 1);
    expect(container.read(sessionControllerProvider).hasError, isTrue);
  });

  group('access tokens', () {
    test('refresh keeps the same session state', () async {
      repository.restored = testSession;
      await container.read(sessionControllerProvider.future);
      final states = <AsyncValue<AuthSession?>>[];
      container.listen(
        sessionControllerProvider,
        (previous, next) => states.add(next),
      );
      repository.currentToken = 'oa_access_2';
      final controller = container.read(sessionControllerProvider.notifier);

      expect(await controller.accessToken(), 'oa_access_2');
      expect(
        await controller.refreshAccessToken(testSession.accessToken),
        'oa_access_2',
      );
      expect(repository.rejectedTokens, [testSession.accessToken]);
      expect(states, isEmpty);
      expect(
        container.read(sessionControllerProvider).value,
        same(testSession),
      );
    });

    test('a rejected refresh signs out', () async {
      repository.restored = testSession;
      await container.read(sessionControllerProvider.future);
      repository.tokenFailure = invalidSession;

      await expectLater(
        container.read(sessionControllerProvider.notifier).accessToken(),
        throwsA(same(invalidSession)),
      );
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(repository.signOuts, 1);
    });

    test('a network failure keeps the session', () async {
      repository.restored = testSession;
      await container.read(sessionControllerProvider.future);
      repository.tokenFailure = const AppFailure(
        FailureKind.network,
        'offline',
      );

      await expectLater(
        container.read(sessionControllerProvider.notifier).accessToken(),
        throwsA(isA<AppFailure>()),
      );
      expect(
        container.read(sessionControllerProvider).value,
        same(testSession),
      );
      expect(repository.signOuts, 0);
    });

    test('signed out means no token and no repository call', () async {
      await container.read(sessionControllerProvider.future);

      await expectLater(
        container.read(sessionControllerProvider.notifier).accessToken(),
        throwsA(same(invalidSession)),
      );
      expect(repository.tokenRequests, 0);
    });
  });

  test(
    'resume revalidation cannot retain a server-invalidated session',
    () async {
      repository.restored = testSession;
      await container.read(sessionControllerProvider.future);
      repository.restored = null;
      await container.read(sessionControllerProvider.notifier).revalidate();
      expect(container.read(sessionControllerProvider).value, isNull);
      expect(repository.restores, 2);
    },
  );
}

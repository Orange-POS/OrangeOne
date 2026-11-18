import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/preferences/time_format_controller.dart';
import 'package:orange_one/core/storage/secret_store.dart';

import '../../support/auth_fakes.dart';

void main() {
  late MemorySecretStore store;

  ProviderContainer container() => ProviderContainer.test(
    overrides: [secretStoreProvider.overrideWithValue(store)],
  );

  setUp(() => store = MemorySecretStore());

  test('24-hour until the user chooses otherwise', () async {
    final c = container();
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours24);
    await pumpEventQueue();
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours24);
  });

  test('a stored choice is restored as the default', () async {
    store.values[timeFormatStorageKey] = '12h';
    final c = container()
      ..listen(timeFormatControllerProvider, (previous, next) {});
    await pumpEventQueue();
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours12);
  });

  test('a choice applies at once and is remembered', () async {
    final c = container();
    await c
        .read(timeFormatControllerProvider.notifier)
        .select(TimeFormatPreference.hours12);
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours12);
    expect(store.values[timeFormatStorageKey], '12h');
    // The next start reads it back.
    final next = container()
      ..listen(timeFormatControllerProvider, (previous, value) {});
    await pumpEventQueue();
    expect(
      next.read(timeFormatControllerProvider),
      TimeFormatPreference.hours12,
    );
  });

  test('unknown stored values keep the default', () async {
    store.values[timeFormatStorageKey] = 'sundial';
    final c = container()
      ..listen(timeFormatControllerProvider, (previous, next) {});
    await pumpEventQueue();
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours24);
  });

  test('a storage failure never blocks the choice', () async {
    store.failure = const AppFailure(FailureKind.storage, 'unavailable');
    final c = container();
    await c
        .read(timeFormatControllerProvider.notifier)
        .select(TimeFormatPreference.hours12);
    expect(c.read(timeFormatControllerProvider), TimeFormatPreference.hours12);
  });
}

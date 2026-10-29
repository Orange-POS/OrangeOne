import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/idempotency_keys.dart';

void main() {
  late IdempotencyKeys keys;
  late List<String> sent;
  setUp(() {
    keys = IdempotencyKeys();
    sent = [];
  });

  Future<void> write(String operation, [Object? error]) =>
      keys.run(operation, (key) async {
        sent.add(key);
        if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
      });

  test('every completed write gets a new UUID v4', () async {
    await write('PUT a');
    await write('PUT a');
    expect(sent.toSet(), hasLength(2));
    for (final key in sent) {
      expect(
        key,
        matches(
          RegExp(
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });

  for (final uncertain in <Object>[
    const AppFailure(FailureKind.network, 'offline'),
    const AppFailure(FailureKind.timeout, 'slow'),
    invalidResponse,
    StateError('unexpected'),
  ]) {
    test('an unknown outcome keeps the key for the same operation '
        '($uncertain)', () async {
      await expectLater(write('PUT a', uncertain), throwsA(same(uncertain)));
      await write('PUT b');
      await write('PUT a');
      expect(sent[2], sent[0]);
      expect(sent[1], isNot(sent[0]));
      // Settled: the next identical write is a new intent.
      await write('PUT a');
      expect(sent[3], isNot(sent[0]));
    });
  }

  test('a server answer settles the key', () async {
    const rejected = AppFailure(
      FailureKind.conflict,
      'stale',
      code: 'VERSION_CONFLICT',
    );
    await expectLater(write('PUT a', rejected), throwsA(same(rejected)));
    await write('PUT a');
    expect(sent[1], isNot(sent[0]));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/network/pending_writes.dart';

void main() {
  var now = DateTime.utc(2026, 11, 12, 8);
  late PendingWrites writes;

  PendingWrite begin([String slot = 'a', String key = 'k1']) => writes.begin(
    slot: slot,
    method: 'POST',
    path: '/x',
    body: '{"percent":"20"}',
    key: key,
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 12, 8);
    writes = PendingWrites(now: () => now);
  });

  test('keeps the write exactly as sent until it is settled', () {
    final write = begin();
    expect(writes['a'], same(write));
    expect(write.body, '{"percent":"20"}');
    expect(write.key, 'k1');
    writes.settle(write);
    expect(writes['a'], isNull);
  });

  test('an unresolved write is never replaced', () {
    final write = begin();
    expect(() => begin('a', 'k2'), throwsStateError);
    expect(writes['a'], same(write));
    expect(begin('b', 'k2').key, 'k2', reason: 'other slots are free');
  });

  test('settling an older write never removes a newer one', () {
    final old = begin();
    writes.settle(old);
    final newer = begin('a', 'k2');
    writes.settle(old);
    expect(writes['a'], same(newer));
  });

  test('replayable within the window only', () {
    final write = begin();
    now = now.add(PendingWrites.replayWindow - const Duration(minutes: 1));
    expect(writes.replayable(write), isTrue);
    now = now.add(const Duration(minutes: 1));
    expect(writes.replayable(write), isFalse);
    expect(writes['a'], same(write), reason: 'never dropped by itself');
  });
}

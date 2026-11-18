import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/formatting/money.dart';

void main() {
  test('failureText shows safe messages, otherwise the fallback', () {
    expect(
      failureText(
        const AppFailure(FailureKind.network, 'You are offline.'),
        'x',
      ),
      'You are offline.',
    );
    expect(
      failureText(const FormatException('Unreadable reply.'), 'x'),
      'Unreadable reply.',
    );
    expect(failureText(StateError('internal'), 'Try again.'), 'Try again.');
    expect(failureText(null, 'Try again.'), 'Try again.');
  });

  test('only answered refusals count as a refused write', () {
    for (final kind in FailureKind.values) {
      expect(
        AppFailure.refusedWrite(AppFailure(kind, 'm')),
        AppFailure.writeRefusals.contains(kind),
        reason: kind.name,
      );
    }
    // Lost connections and unreadable replies leave the outcome open.
    expect(
      AppFailure.refusedWrite(const AppFailure(FailureKind.network, 'm')),
      isFalse,
    );
    expect(AppFailure.refusedWrite(const FormatException('m')), isFalse);
  });

  test('money is shown with two decimals and its currency when known', () {
    expect(formatAmount(25), '25.00');
    expect(formatAmount(0.1), '0.10');
    expect(formatMoney(25, currency: 'USD'), 'USD 25.00');
    expect(formatMoney(25, currency: ' '), '25.00');
    expect(formatMoney(25), '25.00');
  });
}

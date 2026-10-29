import 'dart:math';

import 'package:orange_one/core/errors/app_failure.dart';

/// `Idempotency-Key` values for Mobile API writes.
///
/// Every new write gets a fresh UUID v4. A write whose outcome is unknown
/// (transport failure, timeout, cancellation or an unreadable response) keeps
/// its key, so repeating the *same* operation — identical request and
/// `If-Match` version — lets the server replay or apply it exactly once. A
/// definitive server answer settles the key; a later identical write is then
/// a new user intent with a new key.
class IdempotencyKeys {
  new({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final _uncertain = <String, String>{};
  static const _maxUncertain = 20;

  /// Runs [write] with the key for [operation] (a request fingerprint).
  Future<T> run<T>(
    String operation,
    Future<T> Function(String key) write,
  ) async {
    final key = _uncertain.remove(operation) ?? _newKey();
    try {
      return await write(key);
    } on AppFailure catch (failure) {
      // Error envelopes carry a code: the server decided, nothing is pending.
      if (failure.code == null) _remember(operation, key);
      rethrow;
    } on Object {
      _remember(operation, key);
      rethrow;
    }
  }

  void _remember(String operation, String key) {
    _uncertain[operation] = key;
    if (_uncertain.length > _maxUncertain) {
      _uncertain.remove(_uncertain.keys.first);
    }
  }

  String _newKey() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }
}

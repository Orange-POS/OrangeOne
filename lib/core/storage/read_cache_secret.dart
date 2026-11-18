import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:orange_one/core/storage/secret_store.dart';

/// The random secret of the read cache key, one per session identity, in
/// platform secure storage (never in the cache database).
///
/// The session identity alone (environment, server, company, user, token
/// family id) is not secret, so it never suffices to decrypt cached rows.
/// The stored secret is bound to the identity it was made for: another
/// session gets a new one, which also makes every older row unreadable.
///
/// Reading, replacing and deleting the stored record are one step each:
/// every [ReadCacheSecret] of the process runs them one at a time per
/// storage key, so an ended session's cleanup can never delete the secret a
/// newer session's cache has just written.
class ReadCacheSecret {
  new(this._store, {required String environment, Random? random})
    : _name = 'orangeone.$environment.read_cache_secret',
      _random = random ?? Random.secure();

  final SecretStore _store;
  final String _name;
  final Random _random;

  /// The last queued operation per storage key, shared by every instance
  /// (each session cache creates its own [ReadCacheSecret]).
  static final _queues = <String, Future<void>>{};

  /// Runs [operation] after every earlier one for this storage key, also
  /// when those failed.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final previous = _queues[_name] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final done = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _queues[_name] = done;
    unawaited(done.then<void>((_) => _release(done)));
    return result;
  }

  /// Forgets [done] once it is the last queued operation for this key.
  void _release(Future<void> done) {
    _queues.removeWhere((name, last) => name == _name && identical(last, done));
  }

  /// The secret for [identity]: the stored one when it was made for this
  /// identity, otherwise a new one that replaces it.
  Future<String> secretFor(String identity) async {
    final owner = await _owner(identity);
    return await _serialized(() async {
      final saved = await _store.read(_name);
      final parts = saved?.split(':');
      if (parts != null &&
          parts.length == 2 &&
          parts[0] == owner &&
          parts[1].length >= 43) {
        return parts[1];
      }
      final secret = base64UrlEncode(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      );
      await _store.write(_name, '$owner:$secret');
      return secret;
    });
  }

  /// Deletes the secret when it belongs to [identity] (the session ended);
  /// a newer session's secret is kept. The record is checked and deleted in
  /// one step, so no replacement can happen in between.
  Future<void> deleteFor(String identity) async {
    final owner = await _owner(identity);
    await _serialized(() async {
      final saved = await _store.read(_name);
      if (saved != null && saved.split(':').first == owner) {
        await _store.delete(_name);
      }
    });
  }

  static Future<String> _owner(String identity) async =>
      base64UrlEncode((await Sha256().hash(utf8.encode(identity))).bytes);
}

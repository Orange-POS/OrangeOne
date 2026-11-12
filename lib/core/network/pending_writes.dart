import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A non-idempotent write (a create) sent without a confirmed answer. It is
/// kept exactly as sent, so the only safe resolution is possible: replaying
/// the identical request with the same `Idempotency-Key`, which the server
/// answers with what it committed, or runs now if it never did.
class PendingWrite {
  const new({
    required this.slot,
    required this.method,
    required this.path,
    required this.body,
    required this.key,
    required this.sentAt,
    this.intent,
  });

  /// What the write is for, e.g. `discount-create:product:10`. One pending
  /// write per slot.
  final String slot;
  final String method;
  final String path;

  /// The request body exactly as serialised and sent (JSON text).
  final String body;

  /// The original `Idempotency-Key`. Never regenerated while pending.
  final String key;
  final DateTime sentAt;

  /// The domain value behind [body] (e.g. the discount draft), to show
  /// what was sent. Never used to rebuild [body].
  final Object? intent;
}

/// Unresolved creates of one authenticated session.
///
/// The server keeps idempotency records per token family (session) for 24
/// hours, so a replay is only meaningful in the same session and before
/// they expire. App composition creates one store per session identity
/// (environment, server, company, user, token family): logout, another
/// shop or another session start with an empty store, and nothing leaks.
/// A form closing, a controller disposing or a repository being rebuilt
/// keeps it. It is memory only: writes are never persisted or queued.
class PendingWrites {
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _writes = <String, PendingWrite>{};

  /// The server keeps an idempotency record 24 hours. A pending write older
  /// than this margin can no longer be confirmed by a replay (it could run
  /// as a new request), so it needs the user's explicit decision.
  static const replayWindow = Duration(hours: 23);

  PendingWrite? operator [](String slot) => _writes[slot];

  /// Whether [write] can still be confirmed by replaying it.
  bool replayable(PendingWrite write) =>
      _now().difference(write.sentAt) < replayWindow;

  /// Records a write before it is sent. Refused while [slot] already has an
  /// unresolved write: nothing may replace it.
  PendingWrite begin({
    required String slot,
    required String method,
    required String path,
    required String body,
    required String key,
    Object? intent,
  }) {
    if (_writes.containsKey(slot)) {
      throw StateError('An unresolved write is pending for $slot.');
    }
    return _writes[slot] = PendingWrite(
      slot: slot,
      method: method,
      path: path,
      body: body,
      key: key,
      sentAt: _now(),
      intent: intent,
    );
  }

  /// Removes [write] once its outcome is known (a confirmed answer or a
  /// definitive refusal), or on the user's explicit decision. A newer write
  /// in the same slot is never removed.
  void settle(PendingWrite write) {
    if (identical(_writes[write.slot], write)) _writes.remove(write.slot);
  }
}

/// The signed-in session's unresolved writes. App composition scopes it to
/// the session identity; without that (tests, signed out) it is one store
/// for the container.
final pendingWritesProvider = Provider<PendingWrites>(
  (ref) => PendingWrites(),
  name: 'pendingWritesProvider',
);

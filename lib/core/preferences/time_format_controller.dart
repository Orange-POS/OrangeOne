import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/storage/secret_store.dart';

/// How times are shown and picked: 24-hour (`14:30`) or 12-hour with
/// AM/PM (`2:30 PM`). Stored values stay 24-hour; this is display only.
enum TimeFormatPreference {
  hours24('24h'),
  hours12('12h');

  new(this.wire);
  final String wire;

  static TimeFormatPreference? fromWire(String? value) {
    for (final format in values) {
      if (format.wire == value) return format;
    }
    return null;
  }
}

/// Preference key. Not a secret; the existing injectable [SecretStore] is
/// reused (as for the language) so no extra storage dependency is needed.
const timeFormatStorageKey = 'orangeone.time_format';

/// The user's time format, 24-hour until they choose otherwise.
///
/// Chosen once on the time card, it stays the default on this device; a
/// storage failure never blocks the app (the choice then applies until
/// restart).
final timeFormatControllerProvider =
    NotifierProvider<TimeFormatController, TimeFormatPreference>(
      TimeFormatController.new,
      name: 'timeFormatControllerProvider',
    );

class TimeFormatController extends Notifier<TimeFormatPreference> {
  var _chosen = false;

  @override
  TimeFormatPreference build() {
    unawaited(_restore());
    return TimeFormatPreference.hours24;
  }

  Future<void> _restore() async {
    try {
      final saved = TimeFormatPreference.fromWire(
        await ref.read(secretStoreProvider).read(timeFormatStorageKey),
      );
      // A choice made while reading wins over the stored value.
      if (ref.mounted && !_chosen && saved != null) state = saved;
    } on Exception {
      // Keep the 24-hour default.
    }
  }

  /// Applies [format] immediately and remembers it for the next start.
  Future<void> select(TimeFormatPreference format) async {
    _chosen = true;
    state = format;
    try {
      await ref
          .read(secretStoreProvider)
          .write(timeFormatStorageKey, format.wire);
    } on Exception {
      // The format stays applied for this run only.
    }
  }
}

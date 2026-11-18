import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:orange_one/core/platform/haptics.dart';
import 'package:orange_one/core/storage/secret_store.dart';

import 'auth_fakes.dart';

/// Records the haptics the app asked for; optionally fails like a device
/// without haptics.
class RecordingHapticEngine implements HapticEngine {
  final played = <HapticEffect>[];
  Exception? failure;

  @override
  Future<void> play(HapticEffect effect) async {
    played.add(effect);
    if (failure != null) throw failure!;
  }
}

/// Overrides for tests: the haptics preference reads an in-memory store
/// (no Flutter binding needed), effects go to [engine] instead of the
/// platform, and the clock moves a second per effect, so every step a test
/// takes is recorded (the gaps are tested in `haptics_test.dart`).
List<Override> hapticsOverrides([RecordingHapticEngine? engine]) {
  var ticks = 0;
  return [
    secretStoreProvider.overrideWithValue(MemorySecretStore()),
    hapticEngineProvider.overrideWithValue(engine ?? RecordingHapticEngine()),
    hapticClockProvider.overrideWithValue(() => Duration(seconds: ++ticks)),
  ];
}

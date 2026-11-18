import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/secret_store.dart';

/// The few touch feedbacks of the app, named by meaning, not by strength.
enum HapticEffect {
  /// A code was read by the camera.
  scan,

  /// A change was confirmed in its confirmation dialog.
  confirm,

  /// The server confirmed a saved change.
  success,

  /// A wheel of a picker moved to another value (hour, minute, AM/PM).
  selection,

  /// Validation refused the entered values (an input error appeared, or the
  /// server rejected a save as invalid).
  error,
}

/// Plays a [HapticEffect] on the device. Replaced by a recording fake in
/// tests.
abstract interface class HapticEngine {
  Future<void> play(HapticEffect effect);
}

/// The platform's own haptics (`HapticFeedback`): Android and iOS skip them
/// when touch feedback is switched off in the phone's settings. The error is
/// the system's error pattern on iOS; Android's equivalent needs API 30, so
/// it plays a heavy tap there, which every supported version has.
class PlatformHapticEngine implements HapticEngine {
  const new();

  @override
  Future<void> play(HapticEffect effect) => switch (effect) {
    HapticEffect.scan => HapticFeedback.selectionClick(),
    HapticEffect.confirm => HapticFeedback.lightImpact(),
    HapticEffect.success => HapticFeedback.mediumImpact(),
    HapticEffect.selection => HapticFeedback.selectionClick(),
    HapticEffect.error =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? HapticFeedback.errorNotification()
          : HapticFeedback.heavyImpact(),
  };
}

final hapticEngineProvider = Provider<HapticEngine>(
  (ref) => const PlatformHapticEngine(),
  name: 'hapticEngineProvider',
);

/// A monotonic clock for the gaps between effects (device time changes never
/// hold haptics back). Replaced by a controlled clock in tests.
final hapticClockProvider = Provider<Duration Function()>((ref) {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}, name: 'hapticClockProvider');

/// Preference key. Not a secret; the existing injectable [SecretStore] is
/// reused (as for the language and time format).
const hapticsStorageKey = 'orangeone.haptics';

/// Whether the app plays haptic feedback: on until the user switches it off
/// in Settings, then remembered on this device.
final hapticsControllerProvider = NotifierProvider<HapticsController, bool>(
  HapticsController.new,
  name: 'hapticsControllerProvider',
);

class HapticsController extends Notifier<bool> {
  /// The shortest time between two of the same effect. A fast wheel spin
  /// still ticks per value without buzzing, and an error shown by both its
  /// input and the save that failed vibrates once.
  static const Map<HapticEffect, Duration> minimumGap = {
    HapticEffect.selection: Duration(milliseconds: 40),
    HapticEffect.error: Duration(seconds: 1),
  };

  var _chosen = false;
  late Future<void> _restored;
  final _last = <HapticEffect, Duration>{};

  @override
  bool build() {
    _restored = _restore();
    return true;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(secretStoreProvider).read(hapticsStorageKey);
      // A choice made while reading wins over the stored value.
      if (ref.mounted && !_chosen && saved != null) state = saved != 'off';
    } on Exception {
      // Keep haptics on.
    }
  }

  /// Applies [enabled] immediately and remembers it for the next start.
  Future<void> select({required bool enabled}) async {
    _chosen = true;
    state = enabled;
    try {
      await ref
          .read(secretStoreProvider)
          .write(hapticsStorageKey, enabled ? 'on' : 'off');
    } on Exception {
      // The choice stays applied for this run only.
    }
  }

  /// Plays [effect] when haptics are on. Never throws: a device without
  /// haptics simply stays silent.
  void play(HapticEffect effect) {
    final gap = minimumGap[effect];
    if (gap != null) {
      final now = ref.read(hapticClockProvider)();
      final last = _last[effect];
      if (last != null && now - last < gap) return;
      _last[effect] = now;
    }
    unawaited(_play(effect));
  }

  /// Plays the error haptic when [error] is a validation refusal (invalid
  /// values), never for network, permission or other failures.
  void rejected(Object error) {
    if (error is AppFailure && error.kind == FailureKind.validation) {
      play(HapticEffect.error);
    }
  }

  Future<void> _play(HapticEffect effect) async {
    // The first effect after a start waits for the stored choice, so a
    // switched-off app never ticks before the preference is read.
    await _restored;
    if (!ref.mounted || !state) return;
    try {
      await ref.read(hapticEngineProvider).play(effect);
    } on Exception {
      // Haptics are optional.
    }
  }
}

/// Plays [effect] from a widget. Silent when no provider scope exists (for
/// example a widget tested on its own).
void playHaptic(BuildContext context, HapticEffect effect) {
  // Rare events (a read code, a confirmation, a wheel step), so the ancestor
  // walk is cheap.
  final scope = context
      .findAncestorWidgetOfExactType<UncontrolledProviderScope>();
  scope?.container.read(hapticsControllerProvider.notifier).play(effect);
}

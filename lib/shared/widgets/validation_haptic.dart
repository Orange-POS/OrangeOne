import 'package:flutter/widgets.dart';
import 'package:orange_one/core/platform/haptics.dart';

/// Wraps an input and plays the error haptic when its validation [error]
/// appears. Nothing else changes: the child is shown as it is.
///
/// It plays only on the change from valid to invalid, never when the screen
/// opens with an error, on rebuilds, or while the user keeps typing into a
/// still-invalid value (the message may change; it is the same failure).
class ValidationHaptic extends StatefulWidget {
  const new({required this.error, required this.child, super.key});

  /// The input's current error text; null while valid.
  final String? error;
  final Widget child;

  @override
  State<ValidationHaptic> createState() => _ValidationHapticState();
}

class _ValidationHapticState extends State<ValidationHaptic> {
  @override
  void didUpdateWidget(ValidationHaptic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error == null && widget.error != null) {
      playHaptic(context, HapticEffect.error);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

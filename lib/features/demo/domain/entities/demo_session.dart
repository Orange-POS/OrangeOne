import 'package:orange_one/features/demo/domain/entities/demo_sample.dart';

/// Demo Mode is switched on: the QR login offers sample QR codes. It owns no
/// data; that belongs to the [DemoLogin] chosen from it.
class DemoSession {
  const new(this.id);

  /// Distinguishes runs so nothing of an earlier run is ever reused.
  final int id;
}

/// A sign-in with a [DemoSample]. It owns the isolated sample data and ends,
/// with all of it, on logout or when Demo Mode is turned off.
class DemoLogin {
  const new(this.id, this.sample);

  final int id;
  final DemoSample sample;

  /// Scope for session-bound UI state; never equals a real session identity.
  String get scope => 'demo|$id|${sample.id}';
}

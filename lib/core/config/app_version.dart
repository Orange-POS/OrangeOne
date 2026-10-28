import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The installed build version (the pubspec version, set by the Flutter tool).
///
/// One source for `X-App-Version` and `device.app_version`, so the backend's
/// minimum-version gate and the registered device always agree.
final appVersionProvider = Provider<String>(
  (ref) =>
      const String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '0.0.0'),
  name: 'appVersionProvider',
);

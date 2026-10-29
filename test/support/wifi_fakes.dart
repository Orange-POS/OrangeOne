import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/network/wifi_connection.dart';

/// Drives the Wi-Fi state of the QR scanner without a platform plugin.
Override wifiOverride(Stream<bool> states) =>
    wifiConnectionProvider.overrideWith((ref) => states);

/// The device is on Wi-Fi.
final Override wifiConnected = wifiConnectionProvider.overrideWith(
  (ref) => Stream.value(true),
);

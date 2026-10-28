import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device currently has a Wi-Fi connection.
///
/// This only reads the device's network interface. It cannot tell which
/// network the Wi-Fi is, so it never proves that the POS machine is
/// reachable or on the same network. Errors surface as [AsyncError]; callers
/// that gate an action on Wi-Fi must treat them as "not connected".
final StreamProvider<bool> wifiConnectionProvider =
    StreamProvider.autoDispose<bool>((ref) async* {
      final connectivity = Connectivity();
      yield _onWifi(await connectivity.checkConnectivity());
      yield* connectivity.onConnectivityChanged.map(_onWifi);
    }, name: 'wifiConnectionProvider');

bool _onWifi(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi);

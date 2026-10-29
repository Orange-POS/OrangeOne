import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/app/router/app_router.dart';
import 'package:orange_one/core/config/api_configuration.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/l10n/locale_controller.dart';

import '../../../support/auth_fakes.dart';
import '../../../support/wifi_fakes.dart';

const _wifiMessage =
    'Please connect to the same Wi-Fi network as the POS machine '
    'to scan the QR code.';

void main() {
  late StreamController<bool> wifi;
  late FakeAuthRepository repository;
  late MemorySecretStore store;
  var cameras = 0;
  late void Function(String) lastOnCode;
  late void Function(String) lastOnStatus;

  setUp(() {
    wifi = StreamController<bool>();
    repository = FakeAuthRepository();
    store = MemorySecretStore();
    cameras = 0;
    addTearDown(wifi.close);
  });

  Future<ProviderContainer> pumpScanner(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        utcNowProvider.overrideWithValue(() => testNow),
        secretStoreProvider.overrideWithValue(store),
        wifiOverride(wifi.stream),
        qrCameraBuilderProvider.overrideWithValue((context, onCode, onStatus) {
          cameras++;
          lastOnCode = onCode;
          lastOnStatus = onStatus;
          return const SizedBox(key: Key('camera-view'));
        }),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-login-button')));
    // The Wi-Fi check shows an endless spinner: pump instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return container;
  }

  Finder camera() => find.byKey(const Key('camera-view'));

  testWidgets('no Wi-Fi: the scanner is off and the message is shown', (
    tester,
  ) async {
    wifi.add(false);
    await pumpScanner(tester);
    expect(find.text(_wifiMessage), findsOneWidget);
    expect(camera(), findsNothing);
    expect(cameras, 0, reason: 'the camera is never started');
    expect(find.text('Scanner off · Wi-Fi required'), findsOneWidget);
    // Rebuilding the screen still never starts a camera.
    await tester.pump(const Duration(seconds: 1));
    expect(cameras, 0);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    // The rest of the screen is unchanged.
    expect(find.text('Scan to sign in'), findsOneWidget);
    expect(find.byTooltip('Back to login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wi-Fi on: the camera runs and the message is gone', (
    tester,
  ) async {
    wifi.add(true);
    await pumpScanner(tester);
    expect(camera(), findsOneWidget);
    expect(find.text(_wifiMessage), findsNothing);
    expect(
      find.text('Point your camera at the QR code on the POS machine.'),
      findsOneWidget,
    );
    expect(find.text('Opening camera…'), findsOneWidget);
    lastOnStatus('Camera on · Looking for QR code…');
    await tester.pump();
    expect(find.text('Camera on · Looking for QR code…'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
  });

  testWidgets('the scanner follows Wi-Fi through repeated cycles', (
    tester,
  ) async {
    wifi.add(false);
    await pumpScanner(tester);
    for (var cycle = 1; cycle <= 3; cycle++) {
      final before = cameras;
      wifi.add(true);
      await tester.pumpAndSettle();
      expect(camera(), findsOneWidget, reason: 'enabled in cycle $cycle');
      expect(find.text(_wifiMessage), findsNothing);
      expect(cameras, greaterThan(before));
      // The previous camera status does not leak into the new camera.
      lastOnStatus('Camera paused');
      await tester.pump();
      wifi.add(false);
      await tester.pumpAndSettle();
      expect(camera(), findsNothing, reason: 'disabled in cycle $cycle');
      expect(find.text(_wifiMessage), findsOneWidget);
      final off = cameras;
      await tester.pump(const Duration(seconds: 1));
      expect(cameras, off, reason: 'no camera while Wi-Fi is off');
    }
    wifi.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Opening camera…'), findsOneWidget);
  });

  testWidgets('while the Wi-Fi state is read nothing misleading shows', (
    tester,
  ) async {
    // No event yet: the provider is still loading.
    await pumpScanner(tester);
    expect(camera(), findsNothing);
    expect(find.text(_wifiMessage), findsNothing);
    expect(find.text('Checking Wi-Fi…'), findsOneWidget);
    wifi.add(true);
    await tester.pumpAndSettle();
    expect(camera(), findsOneWidget);
  });

  testWidgets('an unreadable Wi-Fi state counts as not connected', (
    tester,
  ) async {
    wifi.addError(StateError('plugin failure'));
    await pumpScanner(tester);
    expect(camera(), findsNothing);
    expect(find.text(_wifiMessage), findsOneWidget);
    wifi.add(true);
    await tester.pumpAndSettle();
    expect(camera(), findsOneWidget);
  });

  testWidgets('a read error after Wi-Fi was on stops the camera', (
    tester,
  ) async {
    wifi.add(true);
    await pumpScanner(tester);
    expect(camera(), findsOneWidget);
    wifi.addError(StateError('plugin failure'));
    await tester.pumpAndSettle();
    expect(camera(), findsNothing);
    expect(find.text(_wifiMessage), findsOneWidget);
  });

  testWidgets('QR sign-in is unchanged when Wi-Fi is on', (tester) async {
    wifi.add(true);
    await pumpScanner(tester);
    lastOnCode('fixture QR');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.signIns, 1);
    // Ends the session so its expiry timer does not outlive the test.
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(repository.signOuts, 1);
  });

  testWidgets('the message and status follow the selected language', (
    tester,
  ) async {
    store.values[localeStorageKey] = 'nl';
    wifi.add(false);
    await pumpScanner(tester);
    expect(
      find.text(
        'Maak verbinding met hetzelfde wifi-netwerk als het POS-systeem '
        'om de QR-code te scannen.',
      ),
      findsOneWidget,
    );
    expect(find.text('Scanner uit · Wifi vereist'), findsOneWidget);
    expect(find.text(_wifiMessage), findsNothing);
  });

  testWidgets('the message is announced to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    wifi.add(false);
    await pumpScanner(tester);
    expect(
      tester.getSemantics(find.text(_wifiMessage)),
      matchesSemantics(
        label: _wifiMessage,
        isLiveRegion: true,
        textDirection: TextDirection.ltr,
      ),
    );
    handle.dispose();
  });

  testWidgets('going back to login works with the scanner off', (tester) async {
    wifi.add(false);
    final container = await pumpScanner(tester);
    await tester.tap(find.byTooltip('Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to scan QR'), findsOneWidget);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/login',
    );
  });
}

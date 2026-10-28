import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const scanner = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(permissions, null)
      ..setMockMethodCallHandler(scanner, null);
  });
  for (final status in [0, 2, 4]) {
    testWidgets('camera handles denied/restricted/permanent status $status', (
      tester,
    ) async {
      var settingsOpened = false;
      var scans = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(permissions, (call) async {
          if (call.method == 'requestPermissions') return <int, int>{1: status};
          if (call.method == 'checkPermissionStatus') return status;
          if (call.method == 'openAppSettings') {
            settingsOpened = true;
            return true;
          }
          return null;
        })
        ..setMockMethodCallHandler(scanner, (call) async => null);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QrCamera(onCode: (value) => scans++, onStatus: (value) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (status == 2) {
        expect(
          find.text('Camera access is restricted on this device.'),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsNothing);
      } else if (status == 4) {
        expect(find.text('Open Settings'), findsOneWidget);
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();
        expect(settingsOpened, isTrue);
      } else {
        expect(find.text('Allow camera / Retry'), findsOneWidget);
      }
      expect(scans, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

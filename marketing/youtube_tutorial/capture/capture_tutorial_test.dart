// Captures the real OrangeONE screens for the "Getting Started" YouTube
// tutorial, as the Production flavor shows them.
//
// Run from the repository root (see marketing/youtube_tutorial/README.md):
//   flutter test --update-goldens marketing/youtube_tutorial/capture
//
// The app runs with the Production environment, no development tools and no
// Demo Mode. Products come from a fictional in-memory catalog; nothing here
// touches a server, secure storage or a camera. The supplied logo artwork
// contains incorrect text, so the harness serves a text-free crop of its
// mark (brand/logo_mark.png) for the screenshots only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/app/app.dart';
import 'package:orange_one/core/config/app_environment.dart';
import 'package:orange_one/core/storage/secret_store.dart';
import 'package:orange_one/features/authentication/domain/entities/auth_session.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/authentication/presentation/widgets/qr_camera.dart';
import 'package:orange_one/features/demo/data/repositories/demo_catalog.dart';
import 'package:orange_one/features/demo/data/repositories/demo_product_details_repository.dart';
import 'package:orange_one/features/demo/data/repositories/demo_product_repository.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/presentation/providers/product_providers.dart';
import 'package:orange_one/features/home/presentation/providers/recent_scans_providers.dart';
import 'package:orange_one/features/home/presentation/widgets/product_camera.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';

import '../../../test/support/auth_fakes.dart';
import '../../../test/support/wifi_fakes.dart';
import '../../onboarding_video/capture/camera_scenes.dart';

const _water = '2000000000011';
const _root = 'marketing/youtube_tutorial';

/// iPhone 14 class viewport: 390 x 844 logical pixels at 3x.
const _logical = Size(390, 844);
const _ratio = 3.0;

final _manifest = <String, Object>{
  'viewport': {'width': _logical.width, 'height': _logical.height},
  'shots': <String>[],
  'targets': <String, Object>{},
};

/// Serves the text-free logo mark in place of the supplied logo artwork.
class _LogoBundle extends CachingAssetBundle {
  new(this._logo);
  final ByteData _logo;

  @override
  Future<ByteData> load(String key) =>
      key == AppLogo.asset ? Future.value(_logo) : rootBundle.load(key);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  final material = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await material.load();
}

void _configureView(WidgetTester tester) {
  tester.view
    ..physicalSize = _logical * _ratio
    ..devicePixelRatio = _ratio
    ..padding = const FakeViewPadding(top: 47 * _ratio, bottom: 34 * _ratio)
    ..viewPadding = const FakeViewPadding(
      top: 47 * _ratio,
      bottom: 34 * _ratio,
    );
  addTearDown(tester.view.reset);
}

/// Lets real asset/SVG decoding finish, then settles frames.
Future<void> _settle(WidgetTester tester, {bool animations = true}) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    if (animations) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(find.byType(App), matchesGoldenFile('../shots/$name.png'));
  (_manifest['shots']! as List<String>).add(name);
}

void _target(WidgetTester tester, String name, Finder finder) {
  final rect = tester.getRect(finder.first);
  (_manifest['targets']! as Map<String, Object>)[name] = {
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
  };
}

Future<void> _tap(WidgetTester tester, String name, Finder finder) async {
  _target(tester, name, finder);
  await tester.tap(finder.first);
}

/// Types each of [steps], capturing each step as `<name>_<n>`.
Future<void> _type(
  WidgetTester tester,
  Finder field,
  List<String> steps,
  String name,
) async {
  for (final (index, step) in steps.indexed) {
    await tester.enterText(field, step);
    await _settle(tester, animations: false);
    await _shot(tester, '${name}_$index');
  }
}

void main() {
  setUpAll(_loadFonts);
  tearDownAll(() {
    final json = const JsonEncoder.withIndent('  ').convert(_manifest);
    File('$_root/shots/manifest.json').writeAsStringSync('$json\n');
    // The animation page loads this script so it also works from file://.
    File('$_root/shots/manifest.js')
        .writeAsStringSync('window.MANIFEST = $json;\n');
  });

  testWidgets('getting started journey (Production flavor)', (tester) async {
    _configureView(tester);
    debugDisableShadows = false;
    final logo = File('$_root/brand/logo_mark.png').readAsBytesSync();
    final auth = FakeAuthRepository()..pendingLogin = Completer<AuthSession>();
    final catalog = DemoCatalog.seeded();
    ValueChanged<String>? qrCode;
    ValueChanged<String>? qrStatus;
    ValueChanged<String>? barcode;
    ValueChanged<String>? barcodeStatus;
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _LogoBundle(ByteData.sublistView(logo)),
        child: ProviderScope(
          overrides: [
            environmentProvider.overrideWithValue(AppEnvironment.production),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
            wifiOverride(Stream.value(true)),
            authRepositoryProvider.overrideWithValue(auth),
            qrCameraBuilderProvider.overrideWithValue((
              context,
              onCode,
              onStatus,
            ) {
              qrCode = onCode;
              qrStatus = onStatus;
              return const QrCameraScene();
            }),
            productCameraBuilderProvider.overrideWithValue((
              context,
              onCode,
              onStatus,
            ) {
              barcode = onCode;
              barcodeStatus = onStatus;
              return const BarcodeCameraScene(digits: _water);
            }),
            productRepositoryProvider.overrideWithValue(
              DemoProductRepository(catalog),
            ),
            productDetailsRepositoryProvider.overrideWithValue(
              DemoProductDetailsRepository(catalog, canEdit: true),
            ),
            recentScansRepositoryProvider.overrideWithValue(
              MemoryRecentScansRepository(),
            ),
            unsetStockScopeProvider.overrideWith((ref) => 'tutorial'),
          ],
          child: const App(),
        ),
      ),
    );
    await _settle(tester);
    await _shot(tester, 'login');

    // QR code login.
    await _tap(
      tester,
      'login_scan',
      find.byKey(const Key('scan-login-button')),
    );
    await _settle(tester);
    qrStatus!('Camera on · Looking for QR code…');
    await _settle(tester);
    await _shot(tester, 'qr_scan');
    qrCode!('tutorial-sample-login');
    await _settle(tester, animations: false);
    await _shot(tester, 'qr_signing');
    auth.pendingLogin!.complete(testSession);
    await _settle(tester);
    _target(tester, 'home_logout', find.byKey(const Key('logout-button')));
    await _shot(tester, 'home');

    // Barcode scanning.
    await _tap(
      tester,
      'home_scan',
      find.byKey(const Key('scan-product-button')),
    );
    await _settle(tester);
    barcodeStatus!('Camera is on · just point at a barcode');
    await _settle(tester);
    await _shot(tester, 'scanner');
    barcode!(_water);
    await _settle(tester);
    await _shot(tester, 'details');

    // Edit name and tax.
    await _tap(tester, 'details_edit', find.byTooltip('Edit product name'));
    await _settle(tester);
    await _shot(tester, 'edit');
    final name = find.byKey(const Key('product-name-input'));
    await _tap(tester, 'edit_name', name);
    await _type(tester, name, [
      'Sparkling Water',
      'Sparkling Mineral',
      'Sparkling Mineral Water 1L',
    ], 'edit_type');
    await _tap(tester, 'edit_tax', find.byKey(const Key('product-tax-input')));
    await _settle(tester);
    await _shot(tester, 'edit_tax_sheet');
    await _tap(tester, 'edit_tax_option', find.text('2.6%'));
    await _settle(tester);
    await _shot(tester, 'edit_filled');
    await _tap(tester, 'edit_save', find.text('Save Changes'));
    await _settle(tester);
    await _shot(tester, 'edit_confirm');
    await _tap(tester, 'edit_confirm', find.text('Confirm'));
    await _settle(tester);
    await _shot(tester, 'details_after_edit');

    // Update price.
    await _tap(tester, 'details_price', find.byTooltip('Update price'));
    await _settle(tester);
    await _shot(tester, 'price');
    final price = find.byKey(const Key('new-price-input'));
    await _tap(tester, 'price_input', price);
    await _type(tester, price, ['1', '1.5', '1.50'], 'price_type');
    await _tap(tester, 'price_save', find.text('Save Changes'));
    await _settle(tester);
    await _shot(tester, 'price_confirm');
    await _tap(tester, 'price_confirm', find.text('Confirm'));
    await _settle(tester);
    await _shot(tester, 'details_after_price');

    // Update stock: add a delivery.
    await _tap(tester, 'details_stock', find.byTooltip('Update stock'));
    await _settle(tester);
    await _shot(tester, 'stock');
    await _tap(
      tester,
      'stock_add',
      find.byKey(const Key('stock-operation-add')),
    );
    await _settle(tester);
    await _shot(tester, 'stock_add');
    final count = find.byKey(const Key('stock-count-input'));
    await _tap(tester, 'stock_input', count);
    await _type(tester, count, ['2', '24'], 'stock_type');
    // Scroll the form to reveal the live preview under the field.
    final preview = find.byKey(const Key('stock-preview'));
    _target(tester, 'stock_preview_before', preview);
    await tester.ensureVisible(preview);
    await _settle(tester, animations: false);
    _target(tester, 'stock_preview_after', preview);
    await _shot(tester, 'stock_preview');
    await _tap(tester, 'stock_save', find.text('Add Stock'));
    await _settle(tester);
    await _shot(tester, 'stock_confirm');
    await _tap(tester, 'stock_confirm', find.text('Confirm'));
    await _settle(tester);
    await _shot(tester, 'details_after_stock');

    _target(
      tester,
      'details_open_scanner',
      find.byKey(const Key('open-scanner-button')),
    );

    debugDisableShadows = true;
  });
}

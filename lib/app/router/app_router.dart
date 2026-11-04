import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/app/router/auth_redirect.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/features/authentication/presentation/pages/login_page.dart';
import 'package:orange_one/features/authentication/presentation/pages/qr_login_page.dart';
import 'package:orange_one/features/authentication/presentation/pages/splash_page.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_mode_section.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_sample_barcodes.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_sample_qr_list.dart';
import 'package:orange_one/features/home/presentation/pages/home_page.dart';
import 'package:orange_one/features/home/presentation/pages/product_scanner_page.dart';
import 'package:orange_one/features/initialization/presentation/pages/initialization_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/settings/presentation/pages/settings_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (previous, next) => refresh.value++)
    ..listen(demoLoginProvider, (previous, next) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/startup',
    refreshListenable: refresh,
    redirect: (context, route) => authenticationRedirect(
      ref.read(sessionControllerProvider),
      route.uri.path,
      demo: ref.read(demoLoginProvider) != null,
    ),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.goNamed('login'),
          child: const Text('Return to OrangeONE'),
        ),
      ),
    ),
    routes: [
      GoRoute(
        name: 'login',
        path: '/login',
        builder: (context, state) => LoginPage(
          sessionExpired: state.uri.queryParameters['reason'] == 'expired',
        ),
        routes: [
          GoRoute(
            name: 'qrLogin',
            path: 'scan',
            builder: (context, state) => Consumer(
              builder: (context, ref, child) => QrLoginPage(
                demoSamples: ref.watch(demoModeProvider) == null
                    ? null
                    : const DemoSampleQrList(),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        name: 'home',
        path: '/home',
        builder: (context, state) => Consumer(
          builder: (context, ref, child) {
            final auth = ref.watch(sessionControllerProvider);
            final demo = ref.watch(demoLoginProvider) != null;
            final session = auth.isLoading || auth.hasError ? null : auth.value;
            if (session == null && !demo) {
              return const SplashPage();
            }
            return HomePage(
              onScan: () => context.pushNamed<bool>('productScanner'),
              // Leaving the sample session keeps Demo Mode on.
              onSignOut: () {
                if (demo) {
                  ref.read(demoLoginProvider.notifier).signOut();
                } else {
                  unawaited(
                    ref.read(sessionControllerProvider.notifier).signOut(),
                  );
                }
              },
            );
          },
        ),
        routes: [
          GoRoute(
            name: 'productEdit',
            path: 'products/edit',
            builder: (context, state) => ProductEditPage(
              barcode: state.uri.queryParameters['barcode'] ?? '',
            ),
          ),
          GoRoute(
            name: 'productScanner',
            path: 'scan',
            builder: (context, state) => ProductScannerPage(
              samples: ref.read(demoLoginProvider) == null
                  ? null
                  : (scan) => DemoSampleBarcodes(onSelected: scan),
              onLookup: (barcode, {required found}) => context.pushNamed<void>(
                found ? 'productDetails' : 'addProduct',
                queryParameters: {'barcode': barcode},
              ),
            ),
          ),
          GoRoute(
            name: 'productDetails',
            path: 'products/details',
            builder: (context, state) => ProductDetailsPage(
              barcode: state.uri.queryParameters['barcode'] ?? '',
            ),
          ),
          GoRoute(
            name: 'addProduct',
            path: 'products/new',
            builder: (context, state) => ProductCreationPage(
              barcode: state.uri.queryParameters['barcode'] ?? '',
            ),
          ),
          GoRoute(
            name: 'productPrice',
            path: 'products/price',
            builder: (context, state) => ProductPriceUpdatePage(
              barcode: state.uri.queryParameters['barcode'] ?? '',
            ),
          ),
          GoRoute(
            name: 'productStock',
            path: 'products/stock',
            builder: (context, state) => ProductStockUpdatePage(
              barcode: state.uri.queryParameters['barcode'] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        name: 'startup',
        path: '/startup',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(path: '/', redirect: (context, state) => '/login'),
      // Settings hold Demo Mode in every flavor; the Crashlytics verification
      // inside them exists in development only.
      GoRoute(
        name: 'settings',
        path: '/settings',
        builder: (context, state) => Consumer(
          builder: (context, ref, child) {
            final auth = ref.watch(sessionControllerProvider);
            return SettingsPage(
              demoSection: DemoModeSection(
                // Never next to a real session, or while one is restored.
                available: !auth.isLoading && auth.value == null,
                onEnabled: () => context.goNamed('login'),
                onDisabled: () => context.goNamed('login'),
              ),
            );
          },
        ),
      ),
      if (ref.watch(developmentDiagnosticsProvider))
        GoRoute(
          name: 'initialization',
          path: '/diagnostics/initialization',
          builder: (context, state) => const InitializationPage(),
        ),
    ],
  );
  ref
    ..onDispose(router.dispose)
    ..onDispose(refresh.dispose);
  return router;
}, name: 'routerProvider');

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/app/bootstrap/bootstrap_resolver.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/core/config/application_settings.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/features/authentication/presentation/pages/login_page.dart';
import 'package:orange_one/features/authentication/presentation/pages/qr_login_page.dart';
import 'package:orange_one/features/authentication/presentation/pages/splash_page.dart';
import 'package:orange_one/features/authentication/presentation/providers/auth_providers.dart';
import 'package:orange_one/features/compatibility/presentation/pages/compatibility_page.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_mode_section.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_sample_barcodes.dart';
import 'package:orange_one/features/demo/presentation/widgets/demo_sample_qr_list.dart';
import 'package:orange_one/features/discounts/presentation/pages/discount_details_page.dart';
import 'package:orange_one/features/discounts/presentation/pages/discount_form_page.dart';
import 'package:orange_one/features/discounts/presentation/pages/discount_list_page.dart';
import 'package:orange_one/features/discounts/presentation/providers/discount_providers.dart';
import 'package:orange_one/features/discounts/presentation/widgets/discount_summary_card.dart';
import 'package:orange_one/features/help_support/presentation/pages/tutorial_page.dart';
import 'package:orange_one/features/home/presentation/pages/home_page.dart';
import 'package:orange_one/features/home/presentation/pages/product_scanner_page.dart';
import 'package:orange_one/features/initialization/presentation/pages/initialization_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_creation_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_details_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_edit_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_price_update_page.dart';
import 'package:orange_one/features/products/presentation/pages/product_stock_update_page.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/features/settings/presentation/pages/settings_page.dart';
import 'package:orange_one/features/startup/presentation/providers/startup_configuration_providers.dart';
import 'package:orange_one/features/startup/presentation/widgets/startup_workflow_section.dart';

/// The discount screens of one product: the product's id and its own
/// `discount_manage` come from Product Details, so the discounts feature
/// never reads product internals. `editPrice` opens the product's price
/// screen and tells whether a new price was saved; it is null while the
/// product's `update_price` is not granted.
Widget _discountRoute(
  GoRouterState state,
  Widget Function(
    DiscountScope scope,
    Widget productCard,
    Widget navTrailing,
    int? discountId,
    Future<bool> Function(BuildContext context)? editPrice,
  )
  page,
) {
  final barcode = state.uri.queryParameters['barcode'] ?? '';
  final productId = int.tryParse(state.uri.queryParameters['product_id'] ?? '');
  final discountId = int.tryParse(
    state.uri.queryParameters['discount_id'] ?? '',
  );
  return Consumer(
    builder: (context, ref, child) {
      if (productId == null || productId <= 0) {
        return ProductDetailsPage(barcode: barcode);
      }
      final details = ref.watch(productDetailsControllerProvider(barcode));
      final product = details.hasError ? null : details.value?.product;
      final scope = DiscountScope(
        productId: productId,
        barcode: barcode,
        manageAllowed:
            product?.id == productId &&
            (details.value?.access.manageDiscounts ?? false),
      );
      final card = product == null || product.id != productId
          ? const SizedBox.shrink()
          : ProductNameCard(product: product, showActions: false);
      final priceAllowed =
          product?.id == productId &&
          (details.value?.access.updatePrice ?? false);
      return page(
        scope,
        card,
        ProductSyncNavButton(barcode: barcode),
        discountId,
        priceAllowed
            ? (context) async =>
                  await context.pushNamed<bool>(
                    'productPrice',
                    queryParameters: {'barcode': barcode},
                  ) ??
                  false
            : null,
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref
    ..listen(sessionControllerProvider, (previous, next) => refresh.value++)
    ..listen(demoLoginProvider, (previous, next) => refresh.value++)
    ..listen(
      startupConfigurationControllerProvider,
      (previous, next) => refresh.value++,
    )
    // Listening keeps the Capability Manager's GET /meta read alive for the
    // whole session: it runs right after sign-in or restore.
    ..listen(compatibilityProvider, (previous, next) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/startup',
    refreshListenable: refresh,
    redirect: (context, route) => bootstrapRedirect(
      session: ref.read(sessionControllerProvider),
      path: route.uri.path,
      startup: ref.read(startupConfigurationControllerProvider),

      compatibility: ref.read(compatibilityProvider),
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
            builder: (context, state) {
              final barcode = state.uri.queryParameters['barcode'] ?? '';
              return ProductDetailsPage(
                barcode: barcode,
                discountsBuilder: (details) {
                  final product = details.product!;
                  final query = {
                    'barcode': barcode,
                    'product_id': '${product.id}',
                  };
                  return DiscountSummaryCard(
                    productId: product.id,
                    manageAllowed: details.access.manageDiscounts,
                    onOpen: () => context.pushNamed(
                      'productDiscounts',
                      queryParameters: query,
                    ),
                    onCreate: () async {
                      final message = await context.pushNamed<String>(
                        'productDiscountForm',
                        queryParameters: query,
                      );
                      if (context.mounted) showDiscountResult(context, message);
                    },
                  );
                },
              );
            },
          ),
          GoRoute(
            name: 'productDiscounts',
            path: 'products/discounts',
            builder: (context, state) => _discountRoute(
              state,
              (scope, card, nav, _, _) => DiscountListPage(
                scope: scope,
                productCard: card,
                navTrailing: nav,
              ),
            ),
          ),
          GoRoute(
            name: 'productDiscountForm',
            path: 'products/discounts/form',
            builder: (context, state) => _discountRoute(
              state,
              (scope, card, nav, discountId, editPrice) => DiscountFormPage(
                scope: scope,
                discountId: discountId,
                productCard: card,
                navTrailing: nav,
                onEditPrice: editPrice,
              ),
            ),
          ),
          GoRoute(
            name: 'productDiscountDetail',
            path: 'products/discounts/detail',
            builder: (context, state) => _discountRoute(
              state,
              (scope, card, nav, discountId, _) => discountId == null
                  ? DiscountListPage(
                      scope: scope,
                      productCard: card,
                      navTrailing: nav,
                    )
                  : DiscountDetailsPage(
                      scope: scope,
                      discountId: discountId,
                      productCard: card,
                      navTrailing: nav,
                    ),
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
      GoRoute(
        name: 'compatibility',
        path: compatibilityPath,
        builder: (context, state) => Consumer(
          builder: (context, ref, child) => CompatibilityPage(
            status: ref.watch(compatibilityProvider),
            onRetry: () => ref.invalidate(backendFeaturesProvider),
            onSignOut: () => unawaited(
              ref.read(sessionControllerProvider.notifier).signOut(),
            ),
          ),
        ),
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
              startupSection: const StartupWorkflowSection(),
              demoSection: DemoModeSection(
                // Never next to a real session, or while one is restored.
                available: !auth.isLoading && auth.value == null,
                onEnabled: () => context.goNamed('login'),
                onDisabled: () => context.goNamed('login'),
              ),
            );
          },
        ),
        routes: [
          // Help & Support: the remotely managed tutorial videos.
          GoRoute(
            name: 'tutorial',
            path: 'tutorial',
            builder: (context, state) => const TutorialPage(),
          ),
        ],
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

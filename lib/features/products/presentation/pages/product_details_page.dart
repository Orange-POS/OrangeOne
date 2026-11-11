import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/network/backend_features.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_success_toast.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/edit_pencil_button.dart';
import 'package:orange_one/shared/widgets/info_row_card.dart';
import 'package:orange_one/shared/widgets/product_navbar.dart';
import 'package:orange_one/shared/widgets/product_scaffold.dart';
import 'package:orange_one/shared/widgets/scan_dock_bar.dart';

class ProductDetailsPage extends ConsumerStatefulWidget {
  const new({required this.barcode, this.discountsBuilder, super.key});
  final String barcode;

  /// The discount card under the price, composed by the app (the discounts
  /// feature); null shows none.
  final Widget Function(ProductDetailsState details)? discountsBuilder;
  @override
  ConsumerState<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends ConsumerState<ProductDetailsPage> {
  /// The same way back to the scanner the screen always had.
  void _openScanner() =>
      context.canPop() ? context.pop() : context.goNamed('productScanner');

  String _taxLabel(AppLocalizations l10n, ProductDetails product) =>
      product.taxes.isNotEmpty
      ? product.taxes.join(', ')
      : product.taxIds?.isEmpty == true
      ? l10n.detailsTaxNone
      : l10n.detailsTaxUnavailable;

  @override
  Widget build(BuildContext context) {
    // Read the shop's features early, so the stock screen opened from here
    // shows its operations at once.
    ref.watch(backendFeaturesProvider);
    final l10n = context.l10n;
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productDetailsControllerProvider(widget.barcode);
    final state = ref.watch(provider);
    final product = state.hasError ? null : state.value?.product;
    return ProductScaffold(
      // The success of a finished form, above the scan dock.
      floatingActionButton: SizedBox(
        width: MediaQuery.sizeOf(context).width - 32,
        child: ProductSuccessToast(barcode: widget.barcode),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // The dock floats: content stays visible through its notch.
      floatingBottomBar: true,
      bottomNavigationBar: ScanDockBar(
        buttonKey: const Key('open-scanner-button'),
        label: l10n.detailsOpenScanner,
        onPressed: _openScanner,
      ),
      appBar: ProductNavbar(
        title: l10n.detailsTitle,
        // Open Scanner replaces the back arrow; system back still works.
        showBack: false,
        onBack: null,
        trailing: ProductSyncNavButton(barcode: widget.barcode),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(provider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (product != null)
              SliverToBoxAdapter(
                child: ProductNameCard(
                  product: product,
                  detailsLayout: true,
                  taxText: _taxLabel(l10n, product),
                  onEdit: !offline && state.value!.access.editName
                      ? () => context.pushNamed<bool>(
                          'productEdit',
                          queryParameters: {'barcode': widget.barcode},
                        )
                      : null,
                  // Only permitted, backend-adjustable stock can be counted.
                  onAdjustStock:
                      !offline &&
                          state.value!.access.adjustStock &&
                          product.stockAdjustable &&
                          product.stock != null
                      ? () => context.pushNamed<bool>(
                          'productStock',
                          queryParameters: {'barcode': widget.barcode},
                        )
                      : null,
                ),
              ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                // Includes the floating dock's height, so the last card can
                // scroll clear of it.
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    state.when(
                      skipLoadingOnRefresh: false,
                      skipLoadingOnReload: false,
                      loading: () => Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: l10n.detailsLoading,
                        ),
                      ),
                      error: (error, stack) => Column(
                        children: [
                          Text(
                            error is AppFailure
                                ? error.message
                                : error is FormatException
                                ? error.message
                                : l10n.detailsLoadFailed,
                          ),
                          Text(l10n.detailsPullToRefresh),
                        ],
                      ),
                      data: (details) => details.product == null
                          ? Column(
                              children: [
                                Text(l10n.productNotFound),
                                FilledButton(
                                  onPressed: () => context.pushReplacementNamed(
                                    'addProduct',
                                    queryParameters: {
                                      'barcode': widget.barcode,
                                    },
                                  ),
                                  child: Text(l10n.addProduct),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InfoRowCard.price(
                                  label: l10n.detailsPrice,
                                  value: _priceLabel(details.product!.price),
                                  action: EditPencilButton(
                                    tooltip: l10n.detailsUpdatePrice,
                                    onPressed:
                                        !offline && details.access.updatePrice
                                        ? () => context.pushNamed<bool>(
                                            'productPrice',
                                            queryParameters: {
                                              'barcode': widget.barcode,
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                                ?widget.discountsBuilder?.call(details),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _priceLabel(double price) => 'CHF ${price.toStringAsFixed(2)}';
}

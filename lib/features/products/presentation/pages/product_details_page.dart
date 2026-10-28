import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/mock_discount_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/open_scanner_button.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/product_sync_indicator.dart';

class ProductDetailsPage extends ConsumerStatefulWidget {
  const new({required this.barcode, super.key});
  final String barcode;
  @override
  ConsumerState<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends ConsumerState<ProductDetailsPage> {
  String _discountName = 'Cotton essentials offer';
  String _discountPercent = '20';

  Future<void> _editDiscount() async {
    final result = await showDialog<MockDiscount>(
      context: context,
      builder: (context) => MockDiscountDialog(
        initial: (name: _discountName, percent: _discountPercent),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _discountName = result.name;
        _discountPercent = result.percent;
      });
    }
  }

  /// The same way back to the scanner the screen always had.
  void _openScanner() =>
      context.canPop() ? context.pop() : context.goNamed('productScanner');

  String _taxLabel(AppLocalizations l10n, ProductDetails product) =>
      product.taxes.isNotEmpty
      ? product.taxes.join(', ')
      : product.taxIds?.isEmpty == true
      ? l10n.detailsTaxNone
      : l10n.detailsTaxUnavailable;

  /// Status text with the localized time of the last server verification.
  String _syncTime(BuildContext context, String status, DateTime time) {
    final material = MaterialLocalizations.of(context);
    final local = time.toLocal();
    return context.l10n.syncLastVerified(
      status,
      '${material.formatCompactDate(local)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productDetailsControllerProvider(widget.barcode);
    final state = ref.watch(provider);
    final product = state.hasError ? null : state.value?.product;
    return ProductScaffold(
      floatingActionButton: OpenScannerButton(onPressed: _openScanner),
      appBar: ProductNavbar(
        title: l10n.detailsTitle,
        // Open Scanner replaces the back arrow; system back still works.
        showBack: false,
        onBack: null,
        onEdit: null,
        editTooltip: l10n.detailsEditName,
        trailing: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .2),
          ),
          alignment: Alignment.center,
          child: ProductSyncIndicator(
            barcode: widget.barcode,
            labels: ProductSyncLabels(
              pending: l10n.syncPending,
              online: l10n.syncOnline,
              offline: l10n.syncOffline,
              failed: l10n.syncFailed,
              lastVerified: (status, time) => _syncTime(context, status, time),
            ),
            onlineIcon: SvgPicture.asset(
              'assets/icons/product_detail_online.svg',
              width: 24,
              height: 24,
            ),
          ),
        ),
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
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.paddingOf(context).bottom + 8,
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
                                _row(
                                  'assets/icons/product_detail_price.svg',
                                  l10n.detailsPrice,
                                  _priceLabel(details.product!.price),
                                  isPrice: true,
                                  action: IconButton(
                                    tooltip: l10n.detailsUpdatePrice,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 48,
                                      height: 48,
                                    ),
                                    onPressed:
                                        !offline && details.access.updatePrice
                                        ? () => context.pushNamed<bool>(
                                            'productPrice',
                                            queryParameters: {
                                              'barcode': widget.barcode,
                                            },
                                          )
                                        : null,
                                    icon: Opacity(
                                      opacity:
                                          !offline && details.access.updatePrice
                                          ? 1
                                          : .38,
                                      child: SvgPicture.asset(
                                        'assets/icons/'
                                        'product_detail_pencil.svg',
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _row(
                                  'assets/icons/product_detail_tax.svg',
                                  l10n.detailsTax,
                                  _taxLabel(l10n, details.product!),
                                ),
                                // Keep discounts hidden for future use.
                                Visibility(
                                  visible: false,
                                  maintainState: true,
                                  child: _discountCard(),
                                ),
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

  Widget _row(
    String asset,
    String label,
    String value, {
    Widget? action,
    bool isPrice = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: OrangeTheme.actionDisabled),
    ),
    child: Row(
      children: [
        SvgPicture.asset(
          asset,
          width: isPrice ? 24 : 20,
          height: isPrice ? 24 : 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: OrangeTheme.secondary,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action],
      ],
    ),
  );

  Widget _discountCard() => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: const [
        BoxShadow(
          color: Color(0xFFDADCE0),
          offset: Offset(0, 4),
          blurRadius: 4,
        ),
      ],
      border: Border.all(color: const Color(0xFFDADCE0)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.sell_outlined, color: OrangeTheme.scannerAccent),
            const SizedBox(width: 8),
            const Expanded(child: Text('Discount · Mock data')),
            IconButton(
              tooltip: 'Edit mock discount',
              onPressed: _editDiscount,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _discountName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OrangeTheme.pale,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$_discountPercent% off · Preview only',
            style: const TextStyle(color: OrangeTheme.dark, fontSize: 20),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Schedule\n12–18 Oct 2026 · All day'),
        const SizedBox(height: 8),
        const Text(
          'Mock discount changes are not saved '
          'to Odoo.',
        ),
      ],
    ),
  );
}

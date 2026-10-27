import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/mock_discount_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
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

  @override
  Widget build(BuildContext context) {
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productDetailsControllerProvider(widget.barcode);
    final state = ref.watch(provider);
    final product = state.hasError ? null : state.value?.product;
    return ProductScaffold(
      appBar: ProductNavbar(
        title: 'Product',
        backTooltip: 'Back to scanner',
        onBack: () => context.canPop()
            ? context.pop()
            : context.goNamed('productScanner'),
        onEdit: null,
        editTooltip: 'Edit product name',
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
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Loading product details',
                        ),
                      ),
                      error: (error, stack) => Column(
                        children: [
                          Text(
                            error is AppFailure
                                ? error.message
                                : error is FormatException
                                ? error.message
                                : 'Unable to load product details.',
                          ),
                          const Text('Pull down to refresh product details.'),
                        ],
                      ),
                      data: (details) => details.product == null
                          ? Column(
                              children: [
                                const Text('Product not found'),
                                FilledButton(
                                  onPressed: () => context.pushReplacementNamed(
                                    'addProduct',
                                    queryParameters: {
                                      'barcode': widget.barcode,
                                    },
                                  ),
                                  child: const Text('Add product'),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _row(
                                  'assets/icons/product_detail_price.svg',
                                  'Price',
                                  _priceLabel(details.product!.price),
                                  action: IconButton(
                                    tooltip: 'Update price',
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
                                  'TAX',
                                  details.product!.currentTaxLabel,
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
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text.rich(
                        TextSpan(
                          text: 'Powered By ',
                          children: [
                            TextSpan(
                              text: 'OrangeONE',
                              style: TextStyle(
                                color: OrangeTheme.actionPressed,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: OrangeTheme.secondary,
                          fontSize: 12,
                          height: 16 / 12,
                        ),
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

  Widget _row(String asset, String label, String value, {Widget? action}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OrangeTheme.actionDisabled),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              asset,
              width: label == 'Price' ? 24 : 20,
              height: label == 'Price' ? 24 : 20,
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

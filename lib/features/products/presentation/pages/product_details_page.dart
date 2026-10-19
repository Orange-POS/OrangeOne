import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/mock_discount_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_bar.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';
import 'package:orange_one/shared/widgets/stock_badge.dart';

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
    final provider = productDetailsControllerProvider(widget.barcode);
    final state = ref.watch(provider);
    final product = state.isLoading || state.hasError
        ? null
        : state.value?.product;
    return Scaffold(
      // Neutral backing prevents the glass footer picking up an orange cast.
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: OrangeTheme.homeGradient),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to scanner',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('productScanner'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .2),
                      fixedSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Product',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit product name',
                    onPressed: product != null && state.value!.access.editName
                        ? () => context.pushNamed<bool>(
                            'productEdit',
                            queryParameters: {'barcode': widget.barcode},
                          )
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .2),
                      fixedSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.edit_square),
                    color: Colors.white,
                    disabledColor: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: product == null
          ? null
          : ProductActionBar(
              onUpdatePrice: state.value!.access.updatePrice
                  ? () => context.pushNamed<bool>(
                      'productPrice',
                      queryParameters: {'barcode': widget.barcode},
                    )
                  : null,
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(provider.notifier).refresh(),
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: OrangeTheme.homeGradient,
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                children: [
                  if (product != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: OrangeTheme.gradient,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: .5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            offset: Offset(0, 4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppLogo(),
                          const SizedBox(height: 16),
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (product.reference.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                product.reference,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          StockBadge(
                            quantity: product.stock,
                            unit: product.unit,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              child: state.when(
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
                            style: FilledButton.styleFrom(
                              backgroundColor: OrangeTheme.scannerAccent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => context.pushReplacementNamed(
                              'addProduct',
                              queryParameters: {'barcode': widget.barcode},
                            ),
                            child: const Text('Add product'),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row(
                            Icons.barcode_reader,
                            'Barcode',
                            product!.barcode,
                          ),
                          _row(
                            Icons.payments_outlined,
                            'Price',
                            'CHF ${product.price.toStringAsFixed(2)}',
                          ),
                          _row(
                            Icons.percent,
                            'TAX',
                            product.taxes.isEmpty
                                ? 'No taxes assigned'
                                : product.taxes.join('\n'),
                          ),
                          Container(
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
                              border: Border.all(
                                color: const Color(0xFFDADCE0),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.sell_outlined,
                                      color: OrangeTheme.scannerAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text('Discount · Mock data'),
                                    ),
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
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                    style: const TextStyle(
                                      color: OrangeTheme.dark,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Schedule\n12–18 Oct 2026 · All day',
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Mock discount changes are not saved '
                                  'to Odoo.',
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

  Widget _row(IconData icon, String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDADCE0)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon == Icons.barcode_reader)
          SvgPicture.asset(
            'assets/icons/product_barcode.svg',
            colorFilter: const ColorFilter.mode(
              OrangeTheme.scannerAccent,
              BlendMode.srcIn,
            ),
            width: 20,
            height: 20,
          )
        else
          Icon(icon, color: OrangeTheme.scannerAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: OrangeTheme.secondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

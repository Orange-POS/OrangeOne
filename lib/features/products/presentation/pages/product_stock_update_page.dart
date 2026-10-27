import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/providers/stock_update_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_context.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/features/products/presentation/widgets/stock_count_form.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Sets the counted on-hand quantity, following the Update Price layout.
class ProductStockUpdatePage extends ConsumerStatefulWidget {
  const new({required this.barcode, super.key});
  final String barcode;
  @override
  ConsumerState<ProductStockUpdatePage> createState() =>
      _ProductStockUpdatePageState();
}

class _ProductStockUpdatePageState
    extends ConsumerState<ProductStockUpdatePage> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _confirming = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _leave(bool changed) {
    if (context.canPop()) {
      context.pop(changed);
    } else {
      context.goNamed(
        'productDetails',
        queryParameters: {'barcode': widget.barcode},
      );
    }
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    final provider = stockUpdateControllerProvider(widget.barcode);
    final confirmation = ref.read(provider.notifier).confirmation();
    if (confirmation == null) return;
    _confirming = true;
    _focus.unfocus();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => StockCountDialog(confirmation: confirmation),
      );
      if (accepted == true && mounted) {
        await ref.read(provider.notifier).save(confirmation);
      }
    } finally {
      _confirming = false;
    }
  }

  Future<void> _refresh() async {
    final provider = stockUpdateControllerProvider(widget.barcode);
    await ref.read(provider.notifier).refresh();
  }

  String _blockedMessage(StockUpdateState value) =>
      !value.details.access.adjustStock
      ? 'You do not have permission to update this stock.'
      : value.details.product!.stock == null
      ? 'Stock is not tracked for this product.'
      : 'Stock for this product cannot be counted here. Packaged, '
            'owner-specific or lot-tracked stock must be adjusted in Odoo.';

  String _savedMessage(StockUpdateState value) {
    final product = value.details.product!;
    final previous = value.previousQuantity;
    final next = stockQuantityLabel(product.stock ?? 0, product.unit);
    return previous == null
        ? 'New stock: $next'
        : 'Previous stock: ${stockQuantityLabel(previous, product.unit)}'
              ' · New stock: $next';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = stockUpdateControllerProvider(widget.barcode);
    final async = ref.watch(provider);
    final view = async.isLoading || async.hasError ? null : async.value;
    final product = view?.details.product;
    final busy = view?.busy ?? false;
    final saved = view?.phase == StockUpdatePhase.saved;
    final uncertain = view?.phase == StockUpdatePhase.uncertain;
    ref.listen(provider, (previous, next) {
      final value = next.value;
      if (!next.isLoading &&
          !next.hasError &&
          value != null &&
          value.phase == StockUpdatePhase.saved &&
          _text.text != value.draft) {
        _text.value = TextEditingValue(
          text: value.draft,
          selection: TextSelection.collapsed(offset: value.draft.length),
        );
      }
    });
    return PopScope(
      canPop: !busy,
      child: ProductScaffold(
        appBar: ProductNavbar(
          title: 'Update Stock',
          onBack: busy ? null : () => _leave(saved),
          onEdit:
              view != null && view.permitted && !busy && !saved && !uncertain
              ? _focus.requestFocus
              : null,
          editTooltip: 'Edit counted quantity',
        ),
        bottomNavigationBar: ProductActionSurface(
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                disabledBackgroundColor: busy ? OrangeTheme.action : null,
                disabledForegroundColor: busy ? Colors.white : null,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: busy
                  ? null
                  : saved
                  ? () => _leave(true)
                  : uncertain
                  ? _refresh
                  : view?.canSubmit == true && !offline
                  ? _confirm
                  : null,
              child: Text(
                busy
                    ? view?.phase == StockUpdatePhase.checking
                          ? 'Checking…'
                          : 'Updating…'
                    : saved
                    ? 'Done'
                    : uncertain
                    ? 'Check current stock'
                    : 'Update Stock',
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (product != null)
                SliverToBoxAdapter(child: ProductNameCard(product: product)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading current stock',
                      ),
                    ),
                    error: (error, stack) => Column(
                      children: [
                        Text(
                          error is AppFailure
                              ? error.message
                              : error is FormatException
                              ? error.message
                              : 'Unable to load the current product stock.',
                        ),
                        if (error is! FormatException)
                          TextButton(
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                    data: (value) {
                      final current = value.details.product;
                      if (current == null) {
                        return const Text('Product not found');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PriceContextRow(
                            label: 'Barcode',
                            value: current.barcode,
                            barcode: true,
                          ),
                          PriceContextRow(
                            label: 'Current Stock',
                            value: current.stock == null
                                ? 'Stock unavailable'
                                : stockQuantityLabel(
                                    current.stock!,
                                    current.unit,
                                  ),
                          ),
                          const Divider(color: Color(0xFFDADCE0), height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: StockCountForm(
                              controller: _text,
                              focusNode: _focus,
                              onChanged: ref
                                  .read(provider.notifier)
                                  .changeQuantity,
                              enabled:
                                  value.permitted &&
                                  !value.busy &&
                                  value.phase == StockUpdatePhase.editing,
                              unit: current.unit,
                              error: value.fieldError,
                            ),
                          ),
                          if (!value.permitted)
                            PriceUpdateNotice(message: _blockedMessage(value)),
                          if (value.phase == StockUpdatePhase.saved)
                            PriceUpdateNotice(
                              success: true,
                              title: 'Stock Updated Successfully',
                              message: _savedMessage(value),
                            ),
                          if (value.message != null)
                            PriceUpdateNotice(message: value.message!),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

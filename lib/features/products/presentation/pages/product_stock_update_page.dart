import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/providers/stock_update_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_context.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/features/products/presentation/widgets/stock_count_form.dart';
import 'package:orange_one/features/products/presentation/widgets/stock_operation_selector.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Updates, adds to or removes from the on-hand stock, following the Update
/// Price layout.
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

  String _blockedMessage(AppLocalizations l10n, StockUpdateState value) =>
      !value.details.access.adjustStock
      ? l10n.stockNoPermission
      : value.details.product!.stock == null
      ? l10n.stockNotTracked
      : l10n.stockCannotCount;

  String _savedMessage(AppLocalizations l10n, StockUpdateState value) {
    final product = value.details.product!;
    final previous = value.previousQuantity;
    final next = stockQuantityLabel(product.stock ?? 0, product.unit);
    return previous == null
        ? l10n.stockSuccessNew(next)
        : l10n.stockSuccessMessage(
            stockQuantityLabel(previous, product.unit),
            next,
          );
  }

  /// A saved count returns to Product Details with the success toast.
  void _finish(StockUpdateState value) {
    final l10n = context.l10n;
    if (value.details.product == null) return;
    // A counted quantity, even zero, is a set stock.
    ref.read(unsetStockProvider.notifier).clear(widget.barcode);
    ref
        .read(productSuccessProvider.notifier)
        .show(
          barcode: widget.barcode,
          title: l10n.stockSuccessTitle,
          message: _savedMessage(l10n, value),
        );
    _leave(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
      if (value?.phase == StockUpdatePhase.saved &&
          previous?.value?.phase != StockUpdatePhase.saved) {
        _finish(value!);
      }
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
          title: l10n.stockTitle,
          onBack: busy ? null : () => _leave(saved),
          trailing: ProductSyncNavButton(barcode: widget.barcode),
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
                          ? l10n.commonChecking
                          : l10n.commonUpdating
                    : uncertain
                    ? l10n.stockCheckCurrent
                    : switch (view?.operation ?? StockOperation.update) {
                        StockOperation.update => l10n.stockActionUpdate,
                        StockOperation.add => l10n.stockActionAdd,
                        StockOperation.remove => l10n.stockActionRemove,
                      },
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
                SliverToBoxAdapter(
                  child: ProductNameCard(
                    product: product,
                    detailsLayout: true,
                    showActions: false,
                    taxText: localizedTaxText(l10n, product),
                  ),
                ),
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
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: l10n.stockLoading,
                      ),
                    ),
                    error: (error, stack) => Column(
                      children: [
                        Text(
                          error is AppFailure
                              ? error.message
                              : error is FormatException
                              ? error.message
                              : l10n.stockLoadFailed,
                        ),
                        if (error is! FormatException)
                          TextButton(
                            onPressed: _refresh,
                            child: Text(l10n.commonTryAgain),
                          ),
                      ],
                    ),
                    data: (value) {
                      final current = value.details.product;
                      if (current == null) {
                        return Text(l10n.productNotFound);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PriceContextRow(
                            label: l10n.stockCurrentLabel,
                            value:
                                ref
                                        .watch(unsetStockProvider)
                                        .contains(current.barcode) &&
                                    (current.stock ?? 0) == 0
                                ? l10n.stockNotSet
                                : current.stock == null
                                ? l10n.stockUnavailable
                                : stockQuantityLabel(
                                    current.stock!,
                                    current.unit,
                                  ),
                          ),
                          const Divider(color: Color(0xFFDADCE0), height: 24),
                          StockOperationSelector(
                            selected: value.operation,
                            onChanged: ref
                                .read(provider.notifier)
                                .changeOperation,
                            enabled:
                                value.permitted &&
                                !value.busy &&
                                value.phase == StockUpdatePhase.editing,
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
                              operation: value.operation,
                              unit: current.unit,
                              error: value.fieldError,
                              current: current.stock,
                              preview: value.previewStock,
                            ),
                          ),
                          if (!value.permitted)
                            PriceUpdateNotice(
                              message: _blockedMessage(l10n, value),
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

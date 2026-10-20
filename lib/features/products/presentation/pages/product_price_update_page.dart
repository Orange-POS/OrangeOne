import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/providers/price_update_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_change_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_context.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductPriceUpdatePage extends ConsumerStatefulWidget {
  const new({required this.barcode, super.key});
  final String barcode;
  @override
  ConsumerState<ProductPriceUpdatePage> createState() =>
      _ProductPriceUpdatePageState();
}

class _ProductPriceUpdatePageState
    extends ConsumerState<ProductPriceUpdatePage> {
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
    final provider = priceUpdateControllerProvider(widget.barcode);
    final confirmation = ref.read(provider.notifier).confirmation();
    if (confirmation == null) return;
    _confirming = true;
    _focus.unfocus();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => PriceChangeDialog(confirmation: confirmation),
      );
      if (accepted == true && mounted) {
        await ref.read(provider.notifier).save(confirmation);
      }
    } finally {
      _confirming = false;
    }
  }

  String _priceLabel(double price) => 'CHF ${price.toStringAsFixed(2)}';

  String _successMessage(double price) => 'New price: ${_priceLabel(price)}';

  Future<void> _refresh() async {
    final provider = priceUpdateControllerProvider(widget.barcode);
    if (ref.read(provider).hasError) {
      ref.invalidate(provider);
      // The provider exposes retry failures in the page's error state.
      await AsyncValue.guard(() => ref.read(provider.future));
    } else {
      await ref.read(provider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = priceUpdateControllerProvider(widget.barcode);
    final async = ref.watch(provider);
    final view = async.isLoading || async.hasError ? null : async.value;
    final product = view?.details.product;
    final busy = view?.busy ?? false;
    final saved = view?.phase == PriceUpdatePhase.saved;
    final uncertain = view?.phase == PriceUpdatePhase.uncertain;
    ref.listen(provider, (previous, next) {
      final value = next.value;
      if (!next.isLoading &&
          !next.hasError &&
          value != null &&
          value.phase == PriceUpdatePhase.saved &&
          _text.text != value.draft) {
        _text.value = TextEditingValue(
          text: value.draft,
          selection: TextSelection.collapsed(offset: value.draft.length),
        );
      }
    });
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: ProductNavbar(
          title: 'Update Price',
          onBack: busy ? null : () => _leave(saved),
          onEdit:
              product != null &&
                  view!.details.access.updatePrice &&
                  !busy &&
                  !saved &&
                  !uncertain
              ? _focus.requestFocus
              : null,
          editTooltip: 'Edit new price',
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
                    ? view?.phase == PriceUpdatePhase.checking
                          ? 'Checking…'
                          : 'Updating…'
                    : saved
                    ? 'Done'
                    : uncertain
                    ? 'Check current price'
                    : 'Update Price',
              ),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (product != null) ProductNameCard(product: product),
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: OrangeTheme.homeGradient,
                ),
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
                        semanticsLabel: 'Loading current price',
                      ),
                    ),
                    error: (error, stack) => Column(
                      children: [
                        Text(
                          error is AppFailure
                              ? error.message
                              : error is FormatException
                              ? error.message
                              : 'Unable to load the current product price.',
                        ),
                        if (error is! FormatException)
                          TextButton(
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                    data: (value) => value.details.product == null
                        ? const Text('Product not found')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PriceContextRow(
                                label: 'Barcode',
                                value: value.details.product!.barcode,
                                barcode: true,
                              ),
                              PriceContextRow(
                                label: 'Current Price',
                                value: _priceLabel(
                                  value.details.product!.price,
                                ),
                              ),
                              const Divider(
                                color: Color(0xFFDADCE0),
                                height: 24,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                child: PriceUpdateForm(
                                  controller: _text,
                                  focusNode: _focus,
                                  onChanged: ref
                                      .read(provider.notifier)
                                      .changePrice,
                                  enabled:
                                      value.details.access.updatePrice &&
                                      !value.busy &&
                                      value.phase == PriceUpdatePhase.editing,
                                  error: value.fieldError,
                                ),
                              ),
                              if (!value.details.access.updatePrice)
                                const PriceUpdateNotice(
                                  message:
                                      'You do not have permission '
                                      'to update this price.',
                                ),
                              if (value.phase == PriceUpdatePhase.saved)
                                PriceUpdateNotice(
                                  success: true,
                                  title: 'Price Updated Successfully',
                                  message: _successMessage(
                                    value.details.product!.price,
                                  ),
                                ),
                              if (value.message != null)
                                PriceUpdateNotice(message: value.message!),
                            ],
                          ),
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

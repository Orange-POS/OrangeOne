import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_context.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_category_sheet.dart';
import 'package:orange_one/features/products/presentation/widgets/product_confirm_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/product_creation_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/features/products/presentation/widgets/product_tax_sheet.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Creates a product for an unknown barcode. There is no product name card:
/// the product does not exist yet.
class ProductCreationPage extends ConsumerStatefulWidget {
  const new({required this.barcode, super.key});
  final String barcode;
  @override
  ConsumerState<ProductCreationPage> createState() =>
      _ProductCreationPageState();
}

class _ProductCreationPageState extends ConsumerState<ProductCreationPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _stockFocus = FocusNode();
  bool _selecting = false;
  bool _confirming = false;
  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _stockFocus.dispose();
    super.dispose();
  }

  void _back() =>
      context.canPop() ? context.pop() : context.goNamed('productScanner');
  void _details() => context.pushReplacementNamed(
    'productDetails',
    queryParameters: {'barcode': widget.barcode},
  );

  Future<void> _tax(ProductCreationState value) async {
    if (_selecting || !value.editable) return;
    _selecting = true;
    FocusScope.of(context).unfocus();
    try {
      final choice = await showModalBottomSheet<ProductTaxChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (context) => ProductTaxSheet(
          taxes: value.context.taxes,
          selectedIds: value.taxIds,
        ),
      );
      if (mounted && choice != null) {
        ref
            .read(productCreationControllerProvider(widget.barcode).notifier)
            .edit(taxIds: choice.id == null ? [] : [choice.id!]);
      }
    } finally {
      _selecting = false;
    }
  }

  Future<void> _category(ProductCreationState value) async {
    if (_selecting || !value.editable) return;
    _selecting = true;
    FocusScope.of(context).unfocus();
    final controller = ref.read(
      productCreationControllerProvider(widget.barcode).notifier,
    );
    try {
      final choice = await showModalBottomSheet<ProductCategoryChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (context) => ProductCategorySheet(
          categories: value.context.categories,
          selectedId: value.categoryId,
          allowNone: false,
          onCreate: value.context.details.access.createCategory
              ? controller.createCategory
              : null,
        ),
      );
      if (mounted && choice?.id != null) {
        controller.edit(categoryId: choice!.id);
      }
    } finally {
      _selecting = false;
    }
  }

  /// Nothing is created before Confirm is selected.
  Future<void> _confirm(ProductCreationState value) async {
    if (_confirming) return;
    _confirming = true;
    FocusScope.of(context).unfocus();
    final l10n = context.l10n;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => ProductConfirmDialog(
          title: l10n.createConfirmTitle,
          message: l10n.createConfirmMessage(
            value.name.trim(),
            widget.barcode,
            value.categoryName ?? '',
            value.taxText(l10n.taxNoTax) ?? '',
            value.effectivePrice,
            value.stock.trim().isEmpty ? l10n.stockNotSet : value.stock.trim(),
          ),
        ),
      );
      if (accepted == true && mounted) {
        await ref
            .read(productCreationControllerProvider(widget.barcode).notifier)
            .save();
      }
    } finally {
      _confirming = false;
    }
  }

  /// The created product opens in Product Details with the success toast.
  void _finish(ProductCreationState value) {
    final l10n = context.l10n;
    final created = value.created;
    if (created == null) return;
    ref
        .read(productSuccessProvider.notifier)
        .show(
          barcode: widget.barcode,
          title: l10n.createSuccessTitle,
          message: l10n.createSuccessMessage(
            created.name,
            created.price.toStringAsFixed(2),
            value.taxText(l10n.taxNoTax) ?? '',
          ),
        );
    _details();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productCreationControllerProvider(widget.barcode);
    final async = ref.watch(provider);
    final value = async.hasError || async.isLoading ? null : async.value;
    final busy = value?.busy ?? false;
    final saved = value?.phase == ProductCreationPhase.saved;
    final existing = value?.context.details.product;
    final controller = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      final current = next.value;
      if (current?.phase == ProductCreationPhase.saved &&
          previous?.value?.phase != ProductCreationPhase.saved) {
        _finish(current!);
      }
    });
    return PopScope(
      canPop: !busy,
      child: ProductScaffold(
        appBar: ProductNavbar(
          title: l10n.createTitle,
          onBack: busy ? null : _back,
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
                  : saved || existing != null
                  ? _details
                  : value?.phase == ProductCreationPhase.uncertain
                  ? controller.check
                  : value?.canSubmit == true && !offline
                  ? () => _confirm(value!)
                  : null,
              child: Text(
                busy
                    ? l10n.commonCreating
                    : saved || existing != null
                    ? l10n.createOpenDetails
                    : value?.phase == ProductCreationPhase.uncertain
                    ? l10n.createCheckBarcode
                    : l10n.createButton,
              ),
            ),
          ),
        ),
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: async.when(
                  skipLoadingOnReload: false,
                  skipLoadingOnRefresh: false,
                  loading: () => Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: l10n.createLoading,
                    ),
                  ),
                  error: (error, stack) => Column(
                    children: [
                      Text(
                        error is AppFailure
                            ? error.message
                            : error is FormatException
                            ? error.message
                            : l10n.createLoadFailed,
                      ),
                      if (error is! FormatException)
                        TextButton(
                          onPressed: () =>
                              ref.read(provider.notifier).retryInitialLoad(),
                          child: Text(l10n.commonTryAgain),
                        ),
                    ],
                  ),
                  data: (view) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PriceContextRow(
                        label: l10n.detailsBarcode,
                        value: widget.barcode,
                        barcode: true,
                      ),
                      const SizedBox(height: 6),
                      if (!view.context.canCreate && !saved)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            existing != null
                                ? l10n.createExists
                                : l10n.createNoPermission,
                          ),
                        ),
                      ProductCreationForm(
                        value: view,
                        name: _name,
                        price: _price,
                        stock: _stock,
                        nameFocus: _nameFocus,
                        priceFocus: _priceFocus,
                        stockFocus: _stockFocus,
                        onName: (name) => controller.edit(name: name),
                        onPrice: (price) => controller.edit(price: price),
                        onStock: (stock) => controller.edit(stock: stock),
                        onTax: view.editable ? () => _tax(view) : null,
                        onCategory: view.editable
                            ? () => _category(view)
                            : null,
                      ),
                      if (view.message != null)
                        PriceUpdateNotice(message: view.message!),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

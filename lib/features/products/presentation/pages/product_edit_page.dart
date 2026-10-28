import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_category_sheet.dart';
import 'package:orange_one/features/products/presentation/widgets/product_confirm_dialog.dart';
import 'package:orange_one/features/products/presentation/widgets/product_edit_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/features/products/presentation/widgets/product_sync_nav_button.dart';
import 'package:orange_one/features/products/presentation/widgets/product_tax_sheet.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

class ProductEditPage extends ConsumerStatefulWidget {
  const new({required this.barcode, super.key});
  final String barcode;
  @override
  ConsumerState<ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends ConsumerState<ProductEditPage> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  bool _selecting = false;
  bool _confirming = false;
  @override
  void dispose() {
    _name.dispose();
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

  Future<void> _refresh() async {
    final provider = productEditControllerProvider(widget.barcode);
    await ref.read(provider.notifier).refresh();
  }

  Future<void> _taxes(ProductEditState value) async {
    if (_selecting || !value.canSelectTax) return;
    _selecting = true;
    _focus.unfocus();
    try {
      final choice = await showModalBottomSheet<ProductTaxChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (context) => ProductTaxSheet(
          taxes: value.taxes,
          selectedIds: value.selectedTaxIds ?? value.details.product?.taxIds,
        ),
      );
      if (mounted && choice != null) {
        ref
            .read(productEditControllerProvider(widget.barcode).notifier)
            .selectTax(choice.id);
      }
    } finally {
      _selecting = false;
    }
  }

  Future<void> _categories(ProductEditState value) async {
    if (_selecting || !value.canSelectCategory) return;
    _selecting = true;
    _focus.unfocus();
    try {
      final selected = value.selectedCategory;
      final choice = await showModalBottomSheet<ProductCategoryChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (context) => ProductCategorySheet(
          categories: value.categories,
          selectedId: selected == null
              ? value.details.product?.category?.id
              : selected.id,
          onCreate: value.details.access.createCategory
              ? ref
                    .read(
                      productEditControllerProvider(widget.barcode).notifier,
                    )
                    .createCategory
              : null,
        ),
      );
      if (mounted && choice != null) {
        ref
            .read(productEditControllerProvider(widget.barcode).notifier)
            .selectCategory(choice.id);
      }
    } finally {
      _selecting = false;
    }
  }

  String _taxText(AppLocalizations l10n, ProductEditState view) {
    final ids = view.selectedTaxIds;
    if (ids == null) return localizedTaxText(l10n, view.details.product!);
    if (ids.isEmpty) return l10n.taxNoTax;
    if (ids.any((id) => !view.taxes.any((tax) => tax.id == id))) {
      return l10n.detailsTaxUnavailable;
    }
    return view.taxes
        .where((tax) => ids.contains(tax.id))
        .map((tax) => tax.label)
        .join(', ');
  }

  String _categoryText(AppLocalizations l10n, ProductEditState view) {
    final change = view.selectedCategory;
    if (change == null) {
      return view.details.product?.category?.name ?? l10n.categoryNone;
    }
    for (final category in view.categories) {
      if (category.id == change.id) return category.name;
    }
    return change.id == null ? l10n.categoryNone : l10n.detailsTaxUnavailable;
  }

  /// Nothing is saved before Confirm is selected.
  Future<void> _confirm(ProductEditState view) async {
    if (_confirming) return;
    _confirming = true;
    _focus.unfocus();
    final l10n = context.l10n;
    final provider = productEditControllerProvider(widget.barcode);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => ProductConfirmDialog(
          title: l10n.editConfirmTitle,
          message: l10n.editConfirmMessage(
            view.name.trim(),
            _taxText(l10n, view),
            _categoryText(l10n, view),
          ),
        ),
      );
      if (accepted == true && mounted) {
        await ref.read(provider.notifier).save();
      }
    } finally {
      _confirming = false;
    }
  }

  /// A saved change returns to Product Details with the success toast.
  void _finish(ProductEditState view) {
    final l10n = context.l10n;
    final product = view.details.product;
    if (product == null) return;
    ref
        .read(productSuccessProvider.notifier)
        .show(
          barcode: widget.barcode,
          title: l10n.editSuccessTitle,
          message: l10n.editSuccessMessage(
            product.name,
            localizedTaxText(l10n, product),
          ),
        );
    _leave(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(readCacheChangesProvider);
    final offline = ref.watch(readCacheProvider)?.offline ?? false;
    final provider = productEditControllerProvider(widget.barcode);
    final async = ref.watch(provider);
    final value = async.isLoading || async.hasError ? null : async.value;
    final product = value?.details.product;
    final busy = value?.busy ?? false;
    final saved = value?.phase == ProductEditPhase.saved;
    final uncertain = value?.phase == ProductEditPhase.uncertain;
    ref.listen(provider, (previous, next) {
      final current = next.value;
      if (current?.phase == ProductEditPhase.saved &&
          previous?.value?.phase != ProductEditPhase.saved) {
        _finish(current!);
      }
      if (!next.isLoading &&
          !next.hasError &&
          current != null &&
          _name.text != current.name) {
        _name.value = TextEditingValue(
          text: current.name,
          selection: TextSelection.collapsed(offset: current.name.length),
        );
      }
    });
    return PopScope(
      canPop: !busy,
      child: ProductScaffold(
        appBar: ProductNavbar(
          title: l10n.editTitle,
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
                  : value?.canSubmit == true && !offline
                  ? () => _confirm(value!)
                  : null,
              child: Text(
                busy
                    ? value?.phase == ProductEditPhase.checking
                          ? l10n.commonChecking
                          : l10n.commonUpdating
                    : uncertain
                    ? l10n.editCheckCurrent
                    : l10n.commonSaveChanges,
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: async.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: l10n.editLoading,
                      ),
                    ),
                    error: (error, stack) => Column(
                      children: [
                        Text(
                          error is AppFailure
                              ? error.message
                              : error is FormatException
                              ? error.message
                              : l10n.editLoadFailed,
                        ),
                        if (error is! FormatException)
                          TextButton(
                            onPressed: _refresh,
                            child: Text(l10n.commonTryAgain),
                          ),
                      ],
                    ),
                    data: (view) => view.details.product == null
                        ? Text(l10n.productNotFound)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (view.taxSelectionError != null)
                                Text(
                                  view.taxSelectionError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ProductEditForm(
                                controller: _name,
                                focusNode: _focus,
                                onChanged: ref
                                    .read(provider.notifier)
                                    .changeName,
                                enabled: view.canEdit,
                                error: view.nameError,
                                taxLabel: _taxText(l10n, view),
                                onSelectTax: view.canSelectTax
                                    ? () => _taxes(view)
                                    : null,
                                categoryLabel: _categoryText(l10n, view),
                                onSelectCategory: view.canSelectCategory
                                    ? () => _categories(view)
                                    : null,
                              ),
                              if (!view.details.access.editName)
                                PriceUpdateNotice(
                                  message: l10n.editNoPermission,
                                ),
                              if (view.taxMessage != null && !saved)
                                PriceUpdateNotice(message: view.taxMessage!),
                              if (view.categoryMessage != null && !saved)
                                PriceUpdateNotice(
                                  message: view.categoryMessage!,
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_edit_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_category_sheet.dart';
import 'package:orange_one/features/products/presentation/widgets/product_edit_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_scaffold.dart';
import 'package:orange_one/features/products/presentation/widgets/product_tax_sheet.dart';
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

  @override
  Widget build(BuildContext context) {
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
          title: 'Edit Name & Tax',
          onBack: busy ? null : () => _leave(saved),
          onEdit: value?.canEdit == true ? _focus.requestFocus : null,
          editTooltip: 'Edit product name',
        ),
        bottomNavigationBar: ProductActionSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
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
                      ? () async {
                          _focus.unfocus();
                          await ref.read(provider.notifier).save();
                        }
                      : null,
                  child: Text(
                    busy
                        ? value?.phase == ProductEditPhase.checking
                              ? 'Checking…'
                              : 'Updating…'
                        : saved
                        ? 'Done'
                        : uncertain
                        ? 'Check current information'
                        : 'Save Changes',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Powered By ',
                      style: TextStyle(color: Color(0xFF5F6368)),
                    ),
                    TextSpan(
                      text: 'OrangeONE',
                      style: TextStyle(color: OrangeTheme.dark),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 12),
              ),
            ],
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
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading product information',
                      ),
                    ),
                    error: (error, stack) => Column(
                      children: [
                        Text(
                          error is AppFailure
                              ? error.message
                              : error is FormatException
                              ? error.message
                              : 'Unable to load product information.',
                        ),
                        if (error is! FormatException)
                          TextButton(
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                    data: (view) => view.details.product == null
                        ? const Text('Product not found')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFDADCE0),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.percent,
                                      color: OrangeTheme.scannerAccent,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(child: Text('TAX')),
                                    Expanded(
                                      child: Text(
                                        view.currentTaxLabel,
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
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
                                taxLabel: view.taxLabel,
                                onSelectTax: view.canSelectTax
                                    ? () => _taxes(view)
                                    : null,
                                categoryLabel: view.categoryLabel,
                                onSelectCategory: view.canSelectCategory
                                    ? () => _categories(view)
                                    : null,
                              ),
                              if (!view.details.access.editName)
                                const PriceUpdateNotice(
                                  message:
                                      'You do not have permission '
                                      'to edit this product.',
                                ),
                              if (view.taxMessage != null && !saved)
                                PriceUpdateNotice(message: view.taxMessage!),
                              if (view.categoryMessage != null && !saved)
                                PriceUpdateNotice(
                                  message: view.categoryMessage!,
                                ),
                              if (saved)
                                PriceUpdateNotice(
                                  success: true,
                                  title: 'Name & Tax Updated Successfully',
                                  message:
                                      'New name: ${view.details.product!.name}'
                                      ' · Tax: ${view.taxLabel}',
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

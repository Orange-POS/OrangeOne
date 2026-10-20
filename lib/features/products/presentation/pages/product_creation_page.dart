import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_creation_providers.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_context.dart';
import 'package:orange_one/features/products/presentation/widgets/price_update_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_action_surface.dart';
import 'package:orange_one/features/products/presentation/widgets/product_creation_form.dart';
import 'package:orange_one/features/products/presentation/widgets/product_name_card.dart';
import 'package:orange_one/features/products/presentation/widgets/product_navbar.dart';
import 'package:orange_one/features/products/presentation/widgets/product_tax_sheet.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

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
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final GlobalKey _success = GlobalKey();
  bool _selecting = false;
  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
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

  @override
  Widget build(BuildContext context) {
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
      final created = next.value?.created;
      if (created != null) {
        _name.text = created.name;
        _price.text = created.price.toStringAsFixed(2);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final notice = _success.currentContext;
          if (mounted && notice != null) {
            Scrollable.ensureVisible(
              notice,
              duration: const Duration(milliseconds: 200),
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          }
        });
      }
    });
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: ProductNavbar(
          title: 'Create New Product',
          onBack: busy ? null : _back,
          onEdit: value?.editable == true ? _nameFocus.requestFocus : null,
          editTooltip: 'Enter product name',
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
                      : saved || existing != null
                      ? _details
                      : value?.phase == ProductCreationPhase.uncertain
                      ? controller.check
                      : value?.canSubmit == true && !offline
                      ? () async {
                          FocusScope.of(context).unfocus();
                          await controller.save();
                        }
                      : null,
                  child: Text(
                    busy
                        ? 'Creating…'
                        : saved
                        ? 'Done'
                        : existing != null
                        ? 'Open Product Details'
                        : value?.phase == ProductCreationPhase.uncertain
                        ? 'Check barcode'
                        : 'Create Product',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Powered By ',
                      style: TextStyle(color: OrangeTheme.secondary),
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
        body: ListView(
          padding: EdgeInsets.zero,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ProductNameCard(product: value?.created ?? existing),
            Container(
              decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: async.when(
                  skipLoadingOnReload: false,
                  skipLoadingOnRefresh: false,
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading product creation options',
                    ),
                  ),
                  error: (error, stack) => Column(
                    children: [
                      Text(
                        error is AppFailure
                            ? error.message
                            : error is FormatException
                            ? error.message
                            : 'Unable to load product creation options.',
                      ),
                      if (error is! FormatException)
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                  data: (view) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PriceContextRow(
                        label: 'Barcode',
                        value: widget.barcode,
                        barcode: true,
                      ),
                      const SizedBox(height: 6),
                      if (!view.context.canCreate && !saved)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            existing != null
                                ? 'This barcode already exists. '
                                      'Open the product instead.'
                                : 'You do not have permission '
                                      'to create products.',
                          ),
                        ),
                      ProductCreationForm(
                        value: view,
                        name: _name,
                        price: _price,
                        nameFocus: _nameFocus,
                        priceFocus: _priceFocus,
                        onName: (name) => controller.edit(name: name),
                        onPrice: (price) => controller.edit(price: price),
                        onTax: view.editable ? () => _tax(view) : null,
                      ),
                      if (view.message != null)
                        PriceUpdateNotice(message: view.message!),
                      if (saved)
                        PriceUpdateNotice(
                          key: _success,
                          success: true,
                          title: 'New Product Created',
                          message:
                              '${view.created!.name} · '
                              'CHF ${view.created!.price.toStringAsFixed(2)} · '
                              '${view.taxLabel}',
                        ),
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

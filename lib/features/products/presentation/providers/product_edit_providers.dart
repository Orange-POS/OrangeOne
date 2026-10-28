import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/use_cases/edit_product_information.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/presentation/product_tax_label.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum ProductEditPhase { editing, saving, checking, saved, uncertain }

class ProductEditState {
  const new({
    required this.details,
    required this.name,
    this.taxes = const [],
    this.selectedTaxIds,
    this.taxMessage,
    this.taxSelectionError,
    this.categories = const [],
    this.selectedCategory,
    this.categoryMessage,
    this.nameError,
    this.message,
    this.phase = ProductEditPhase.editing,
  });
  final ProductDetailsState details;
  final String name;
  final List<ProductTax> taxes;
  final List<ProductCategory> categories;

  /// Null keeps the current category.
  final CategoryChange? selectedCategory;
  final String? categoryMessage;

  /// Null preserves all existing taxes; [] explicitly removes them.
  final List<int>? selectedTaxIds;
  final String? taxMessage;
  final String? taxSelectionError;
  final String? nameError;
  final String? message;
  final ProductEditPhase phase;
  bool get busy =>
      phase == ProductEditPhase.saving || phase == ProductEditPhase.checking;
  bool get canEdit =>
      details.product != null &&
      details.access.editName &&
      phase == ProductEditPhase.editing;
  bool get canSelectTax =>
      canEdit && details.access.updateTaxes && taxMessage == null;
  bool get canSelectCategory =>
      canEdit && details.access.updateCategory && categoryMessage == null;
  bool get changed =>
      name.trim() != details.product?.name ||
      selectedTaxIds != null ||
      selectedCategory != null;
  bool get canSubmit =>
      canEdit &&
      (selectedTaxIds == null || canSelectTax) &&
      (selectedCategory == null || canSelectCategory) &&
      taxSelectionError == null &&
      changed &&
      name.trim().isNotEmpty &&
      nameError == null;
  String get currentTaxLabel =>
      details.product?.currentTaxLabel ?? 'Tax information unavailable';

  String get taxLabel => selectedTaxIds == null
      ? currentTaxLabel
      : selectedTaxIds!.isEmpty
      ? 'No Tax'
      : selectedTaxIds!.any((id) => !taxes.any((tax) => tax.id == id))
      ? 'Selected tax unavailable'
      : taxes
            .where((tax) => selectedTaxIds!.contains(tax.id))
            .map((tax) => tax.label)
            .join(', ');

  String get categoryLabel {
    final change = selectedCategory;
    if (change == null) {
      return details.product?.category?.name ?? 'No category';
    }
    if (change.id == null) return 'No category';
    for (final category in categories) {
      if (category.id == change.id) return category.name;
    }
    return 'Selected category unavailable';
  }
}

final AsyncNotifierProviderFamily<
  ProductEditController,
  ProductEditState,
  String
>
productEditControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ProductEditController, ProductEditState, String>(
      ProductEditController.new,
      name: 'productEditControllerProvider',
      retry: (count, error) => null,
    );

class ProductEditController extends AsyncNotifier<ProductEditState> {
  new(this.barcode);
  final String barcode;
  int _generation = 0;

  @override
  Future<ProductEditState> build() async {
    _generation++;
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) unawaited(refresh());
    });
    final repository = ref.watch(productDetailsRepositoryProvider);
    final details = await ManageProductDetails(repository).load(barcode);
    return await _loadReferences(details, details.product?.name ?? '');
  }

  Future<ProductEditState> _loadReferences(
    ProductDetailsState details,
    String name, {
    List<int>? selectedTaxIds,
    CategoryChange? selectedCategory,
    String? message,
  }) async {
    if (!ref.mounted) throw cancelledOperation;
    final repository = ref.read(productDetailsRepositoryProvider);
    final editable = details.product != null && details.access.editName;
    // Load both option lists together; Future.wait observes every error.
    final options = await Future.wait([
      _options(
        editable && details.access.updateTaxes ? repository.loadTaxes : null,
      ),
      _options(
        editable && details.access.updateCategory
            ? repository.loadCategories
            : null,
      ),
    ]);
    final taxes = (options[0] ?? const []).cast<ProductTax>();
    var taxMessage = !editable || !details.access.updateTaxes
        ? 'Tax selection requires reference access. '
              'Existing taxes are preserved.'
        : options[0] == null
        ? 'Tax options are unavailable. Existing taxes are preserved.'
        : null;
    if (selectedTaxIds != null && taxMessage != null) {
      taxMessage =
          'Tax changes are unavailable. Your selection is retained. '
          'Restore access and refresh before saving.';
    }
    final categories = (options[1] ?? const []).cast<ProductCategory>();
    final categoryMessage =
        editable && details.access.updateCategory && options[1] == null
        ? 'Category options are unavailable. '
              'The current category is preserved.'
        : null;
    return ProductEditState(
      details: details,
      name: name,
      taxes: taxes,
      taxMessage: taxMessage,
      taxSelectionError: _taxError(selectedTaxIds, taxes),
      selectedTaxIds: selectedTaxIds,
      categories: categories,
      categoryMessage: categoryMessage,
      selectedCategory: selectedCategory,
      message: message,
      nameError: _nameError(name),
    );
  }

  /// Picker options, or null when they could not be loaded. Session
  /// rejection still propagates; [load] is null when not permitted.
  static Future<List<Object>?> _options(
    Future<List<Object>> Function()? load,
  ) async {
    if (load == null) return const [];
    try {
      return await load();
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.unauthenticated) rethrow;
      return null;
    } on Exception {
      return null;
    }
  }

  String? _taxError(List<int>? ids, List<ProductTax> taxes) =>
      ids != null && ids.any((id) => !taxes.any((tax) => tax.id == id))
      ? 'Your selected tax is unavailable. '
            'Select an available tax before saving.'
      : null;

  String? _nameError(String name) {
    try {
      EditProductInformation.validateName(name);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  ProductEditState _copy(
    ProductEditState value, {
    String? name,
    List<int>? selectedTaxIds,
    ProductEditPhase phase = ProductEditPhase.editing,
    String? message,
  }) => ProductEditState(
    details: value.details,
    name: name ?? value.name,
    taxes: value.taxes,
    selectedTaxIds: selectedTaxIds ?? value.selectedTaxIds,
    taxMessage: value.taxMessage,
    taxSelectionError: value.taxSelectionError,
    categories: value.categories,
    selectedCategory: value.selectedCategory,
    categoryMessage: value.categoryMessage,
    nameError: _nameError(name ?? value.name),
    phase: phase,
    message: message,
  );

  void changeName(String name) {
    final current = state.value;
    if (state.isLoading || current == null || !current.canEdit) return;
    state = AsyncData(_copy(current, name: name));
  }

  void selectTax(int? id) {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.canSelectTax ||
        (id != null && !current.taxes.any((tax) => tax.id == id))) {
      return;
    }
    final ids = id == null ? <int>[] : [id];
    final original = current.details.product?.taxIds;
    final unchanged =
        original != null &&
        original.length == ids.length &&
        original.toSet().containsAll(ids);
    state = AsyncData(
      ProductEditState(
        details: current.details,
        name: current.name,
        taxes: current.taxes,
        selectedTaxIds: unchanged ? null : List.unmodifiable(ids),
        taxMessage: current.taxMessage,
        categories: current.categories,
        selectedCategory: current.selectedCategory,
        categoryMessage: current.categoryMessage,
        nameError: current.nameError,
      ),
    );
  }

  /// A null [id] removes the category.
  void selectCategory(int? id) {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.canSelectCategory ||
        (id != null && !current.categories.any((c) => c.id == id))) {
      return;
    }
    final unchanged = current.details.product?.category?.id == id;
    state = AsyncData(
      ProductEditState(
        details: current.details,
        name: current.name,
        taxes: current.taxes,
        selectedTaxIds: current.selectedTaxIds,
        taxMessage: current.taxMessage,
        taxSelectionError: current.taxSelectionError,
        categories: current.categories,
        selectedCategory: unchanged ? null : CategoryChange(id),
        categoryMessage: current.categoryMessage,
        nameError: current.nameError,
      ),
    );
  }

  /// Creates a category (`POST /categories`) and selects it for this
  /// product. Failures are rethrown for the picker to show.
  Future<ProductCategory> createCategory(String name) async {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        !current.canSelectCategory ||
        !current.details.access.createCategory) {
      throw const FormatException('Category creation is not available.');
    }
    final created = await ref
        .read(productDetailsRepositoryProvider)
        .createCategory(name);
    if (!ref.mounted) return created;
    final latest = state.value ?? current;
    state = AsyncData(
      ProductEditState(
        details: latest.details,
        name: latest.name,
        taxes: latest.taxes,
        selectedTaxIds: latest.selectedTaxIds,
        taxMessage: latest.taxMessage,
        taxSelectionError: latest.taxSelectionError,
        categories: List.unmodifiable([
          ...latest.categories.where((c) => c.id != created.id),
          created,
        ]),
        selectedCategory: latest.selectedCategory,
        categoryMessage: latest.categoryMessage,
        nameError: latest.nameError,
        message: latest.message,
        phase: latest.phase,
      ),
    );
    selectCategory(created.id);
    return created;
  }

  Future<void> save() async {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return;
    final generation = _generation;
    state = AsyncData(_copy(current, phase: ProductEditPhase.saving));
    final repository = ref.read(productDetailsRepositoryProvider);
    var writeStarted = false;
    try {
      final fresh = await ManageProductDetails(repository).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      final product = fresh.product;
      if (product == null ||
          !fresh.access.editName ||
          (current.selectedTaxIds != null && !fresh.access.updateTaxes) ||
          (current.selectedCategory != null && !fresh.access.updateCategory)) {
        final next = await _loadReferences(
          fresh,
          current.name,
          selectedTaxIds: current.selectedTaxIds,
          selectedCategory: current.selectedCategory,
          message: 'This product or edit permission is no longer available.',
        );
        if (ref.mounted && generation == _generation) state = AsyncData(next);
        return;
      }
      final previous = current.details.product!;
      if (product.id != previous.id ||
          product.name != previous.name ||
          (current.selectedTaxIds != null && !_sameTaxes(product, previous)) ||
          (current.selectedCategory != null &&
              product.category?.id != previous.category?.id)) {
        final next = await _loadReferences(
          fresh,
          current.name,
          selectedTaxIds: current.selectedTaxIds,
          selectedCategory: current.selectedCategory,
          message: 'Product information changed. Review it before saving.',
        );
        if (ref.mounted && generation == _generation) state = AsyncData(next);
        return;
      }
      final taxes = current.selectedTaxIds == null
          ? current.taxes
          : await repository.loadTaxes();
      final categories = current.selectedCategory?.id == null
          ? current.categories
          : await repository.loadCategories();
      if (!ref.mounted || generation != _generation) return;
      final taxError = _taxError(current.selectedTaxIds, taxes);
      final categoryId = current.selectedCategory?.id;
      if (taxError != null ||
          (categoryId != null && !categories.any((c) => c.id == categoryId))) {
        state = AsyncData(
          ProductEditState(
            details: fresh,
            name: current.name,
            taxes: taxes,
            selectedTaxIds: current.selectedTaxIds,
            taxSelectionError: taxError,
            categories: categories,
            selectedCategory: current.selectedCategory,
            categoryMessage: current.categoryMessage,
            message: taxError == null
                ? 'Your selected category is unavailable. '
                      'Select an available category before saving.'
                : null,
          ),
        );
        return;
      }
      writeStarted = true;
      final updated = await EditProductInformation(repository)(
        product,
        current.name,
        taxIds: current.selectedTaxIds,
        allowedTaxes: taxes,
        category: current.selectedCategory,
        allowedCategories: categories,
      );
      if (!ref.mounted || generation != _generation) return;
      final selected = current.selectedTaxIds?.toSet();
      final returned = updated.taxIds?.toSet();
      if (updated.id != product.id ||
          updated.barcode != barcode ||
          updated.name != EditProductInformation.validateName(current.name) ||
          (selected != null &&
              (returned == null ||
                  selected.length != returned.length ||
                  !selected.containsAll(returned))) ||
          (current.selectedCategory != null &&
              updated.category?.id != current.selectedCategory!.id)) {
        throw invalidResponse;
      }
      state = AsyncData(
        ProductEditState(
          details: ProductDetailsState(updated, fresh.access),
          name: updated.name,
          taxes: taxes,
          categories: categories,
          phase: ProductEditPhase.saved,
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is AppFailure && error.kind == FailureKind.conflict) {
        // Nothing was written: show the latest server data, keep the draft.
        try {
          final latest = await ManageProductDetails(repository).load(barcode);
          final next = await _loadReferences(
            latest,
            current.name,
            selectedTaxIds: current.selectedTaxIds,
            selectedCategory: current.selectedCategory,
            message: error.message,
          );
          if (ref.mounted && generation == _generation) {
            state = AsyncData(next);
            ref.invalidate(productDetailsControllerProvider(barcode));
          }
          return;
        } on Exception {
          if (!ref.mounted || generation != _generation) return;
        }
      }
      final rejected =
          error is FormatException ||
          (error is AppFailure &&
              {
                FailureKind.forbidden,
                FailureKind.validation,
                FailureKind.unauthenticated,
                FailureKind.conflict,
                FailureKind.notFound,
                FailureKind.rateLimited,
              }.contains(error.kind));
      state = AsyncData(
        _copy(
          current,
          phase: writeStarted && !rejected
              ? ProductEditPhase.uncertain
              : ProductEditPhase.editing,
          message: writeStarted && !rejected
              ? 'The save could not be confirmed. Check current product '
                    'information before saving again.'
              : error is AppFailure
              ? error.message
              : error is FormatException
              ? error.message
              : 'Unable to update this product. Your changes are preserved.',
        ),
      );
    }
  }

  bool _sameTaxes(ProductDetails current, ProductDetails previous) {
    final currentIds = current.taxIds;
    final previousIds = previous.taxIds;
    if (currentIds != null && previousIds != null) {
      return currentIds.length == previousIds.length &&
          currentIds.toSet().containsAll(previousIds);
    }
    return current.taxes.join('\n') == previous.taxes.join('\n');
  }

  Future<void> refresh() async {
    if (state.isLoading) return;
    if (state.hasError) {
      ref.read(readCacheProvider)?.retryRead();
      final generation = _generation;
      state = const AsyncLoading();
      final result = await AsyncValue.guard(() async {
        final details = await ManageProductDetails(
          ref.read(productDetailsRepositoryProvider),
        ).load(barcode);
        return await _loadReferences(details, details.product?.name ?? '');
      });
      if (ref.mounted && generation == _generation) state = result;
      return;
    }
    final current = state.value;
    if (current == null || current.busy) return;
    ref.read(readCacheProvider)?.retryRead();
    final generation = _generation;
    state = AsyncData(_copy(current, phase: ProductEditPhase.checking));
    try {
      final details = await ManageProductDetails(
        ref.read(productDetailsRepositoryProvider),
      ).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      final next = await _loadReferences(
        details,
        current.name,
        selectedTaxIds: current.selectedTaxIds,
        selectedCategory: current.selectedCategory,
        message: 'Current information refreshed. Review before saving.',
      );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(next);
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        _copy(
          current,
          phase: current.phase,
          message: error is AppFailure
              ? error.message
              : 'Unable to refresh product information.',
        ),
      );
    }
  }
}

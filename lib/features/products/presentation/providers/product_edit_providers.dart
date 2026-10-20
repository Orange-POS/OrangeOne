import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';
import 'package:orange_one/features/products/domain/use_cases/edit_product_information.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum ProductEditPhase { editing, saving, checking, saved, uncertain }

class ProductEditState {
  const new({
    required this.details,
    required this.name,
    this.taxes = const [],
    this.selectedTaxIds,
    this.taxMessage,
    this.nameError,
    this.message,
    this.phase = ProductEditPhase.editing,
  });
  final ProductDetailsState details;
  final String name;
  final List<ProductTax> taxes;

  /// Null preserves all existing taxes; [] explicitly removes them.
  final List<int>? selectedTaxIds;
  final String? taxMessage;
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
      canEdit && details.access.readReferences && taxMessage == null;
  bool get changed =>
      name.trim() != details.product?.name || selectedTaxIds != null;
  bool get canSubmit =>
      canEdit &&
      (selectedTaxIds == null || canSelectTax) &&
      changed &&
      name.trim().isNotEmpty &&
      nameError == null;
  String get currentTaxLabel {
    final product = details.product;
    if (product == null) return 'Tax information unavailable';
    if (product.taxes.isNotEmpty) return product.taxes.join(', ');
    return product.taxIds?.isEmpty == true
        ? 'No Tax'
        : 'Tax information unavailable';
  }

  String get taxLabel => selectedTaxIds == null
      ? currentTaxLabel
      : selectedTaxIds!.isEmpty
      ? 'No Tax'
      : taxes
            .where((tax) => selectedTaxIds!.contains(tax.id))
            .map((tax) => tax.label)
            .join(', ');
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
    String? message,
  }) async {
    if (!ref.mounted) throw cancelledOperation;
    var taxes = <ProductTax>[];
    String? taxMessage;
    if (details.product != null &&
        details.access.editName &&
        details.access.readReferences) {
      try {
        taxes = await ref.read(productDetailsRepositoryProvider).loadTaxes();
      } on AppFailure catch (error) {
        if (error.kind == FailureKind.unauthenticated) rethrow;
        taxMessage =
            'Tax options are unavailable. Existing taxes are preserved.';
      } on Exception {
        taxMessage =
            'Tax options are unavailable. Existing taxes are preserved.';
      }
    } else {
      taxMessage =
          'Tax selection requires reference access. '
          'Existing taxes are preserved.';
    }
    return ProductEditState(
      details: details,
      name: name,
      taxes: taxes,
      taxMessage: taxMessage,
      selectedTaxIds: selectedTaxIds,
      message: message,
      nameError: _nameError(name),
    );
  }

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
        nameError: current.nameError,
      ),
    );
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
          (current.selectedTaxIds != null && !fresh.access.readReferences)) {
        final next = await _loadReferences(
          fresh,
          current.name,
          message: 'This product or edit permission is no longer available.',
        );
        if (ref.mounted && generation == _generation) state = AsyncData(next);
        return;
      }
      final previous = current.details.product!;
      if (product.id != previous.id ||
          product.name != previous.name ||
          (current.selectedTaxIds != null && !_sameTaxes(product, previous))) {
        final next = await _loadReferences(
          fresh,
          current.name,
          message: 'Product information changed. Review it before saving.',
        );
        if (ref.mounted && generation == _generation) state = AsyncData(next);
        return;
      }
      final taxes = current.selectedTaxIds == null
          ? current.taxes
          : await repository.loadTaxes();
      if (!ref.mounted || generation != _generation) return;
      writeStarted = true;
      final updated = await EditProductInformation(repository)(
        product,
        current.name,
        taxIds: current.selectedTaxIds,
        allowedTaxes: taxes,
      );
      if (!ref.mounted || generation != _generation) return;
      if (updated.id != product.id || updated.barcode != barcode) {
        throw invalidResponse;
      }
      state = AsyncData(
        ProductEditState(
          details: ProductDetailsState(updated, fresh.access),
          name: updated.name,
          taxes: taxes,
          phase: ProductEditPhase.saved,
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      final rejected =
          error is FormatException ||
          (error is AppFailure &&
              {
                FailureKind.forbidden,
                FailureKind.validation,
                FailureKind.unauthenticated,
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
    ref.read(readCacheProvider)?.retryRead();
    final current = state.value;
    if (state.isLoading || current == null || current.busy) return;
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

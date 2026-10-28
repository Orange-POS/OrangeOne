import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum StockUpdatePhase { editing, saving, checking, saved, uncertain }

class StockUpdateState {
  const new({
    required this.details,
    this.draft = '',
    this.operation = StockOperation.update,
    this.phase = StockUpdatePhase.editing,
    this.fieldError,
    this.message,
    this.previousQuantity,
  });
  final ProductDetailsState details;
  final String draft;

  /// Update (count), Add or Remove.
  final StockOperation operation;
  final StockUpdatePhase phase;

  /// Why the entered quantity cannot be submitted (null while valid/empty).
  final StockInputException? fieldError;
  final String? message;

  /// The on-hand quantity before the confirmed adjustment.
  final double? previousQuantity;
  bool get busy =>
      phase == StockUpdatePhase.saving || phase == StockUpdatePhase.checking;

  /// Counting needs permission and stock the backend can adjust.
  bool get permitted =>
      details.product != null &&
      details.access.adjustStock &&
      details.product!.stockAdjustable &&
      details.product!.stock != null;
  bool get canSubmit =>
      phase == StockUpdatePhase.editing &&
      permitted &&
      draft.trim().isNotEmpty &&
      fieldError == null;

  /// The stock after the entered quantity, for the live preview. Null until
  /// the quantity is valid. It is only a preview: the backend result decides.
  double? get previewStock {
    final product = details.product;
    if (!permitted || draft.trim().isEmpty || fieldError != null) return null;
    try {
      final count = StockCount.parse(
        draft,
        maxDecimals: product!.quantityDecimals,
      );
      return operation.resultFor(product.stock!, count.quantity);
    } on FormatException {
      return null;
    }
  }
}

final AsyncNotifierProviderFamily<
  StockUpdateController,
  StockUpdateState,
  String
>
stockUpdateControllerProvider = AsyncNotifierProvider.autoDispose
    .family<StockUpdateController, StockUpdateState, String>(
      StockUpdateController.new,
      name: 'stockUpdateControllerProvider',
      retry: (count, error) => null,
    );

class StockUpdateController extends AsyncNotifier<StockUpdateState> {
  new(this.barcode);
  final String barcode;
  int _generation = 0;

  @override
  Future<StockUpdateState> build() async {
    _generation++;
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) unawaited(refresh());
    });
    final repository = ref.watch(productDetailsRepositoryProvider);
    final details = await ManageProductDetails(repository).load(barcode);
    return StockUpdateState(details: details);
  }

  /// The state while the quantity can be edited (not saving, saved or unsure).
  StockUpdateState? get _editable {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        current.busy ||
        current.phase == StockUpdatePhase.saved ||
        current.phase == StockUpdatePhase.uncertain) {
      return null;
    }
    return current;
  }

  void changeQuantity(String raw) {
    final current = _editable;
    if (current == null) return;
    state = AsyncData(_editing(current.details, raw, current.operation));
  }

  /// Switches between Update, Add and Remove. The entered quantity is kept
  /// and checked again for the new operation.
  void changeOperation(StockOperation operation) {
    final current = _editable;
    if (current == null || current.operation == operation) return;
    state = AsyncData(_editing(current.details, current.draft, operation));
  }

  StockUpdateState _editing(
    ProductDetailsState details,
    String draft,
    StockOperation operation, {
    String? message,
  }) {
    StockInputException? error;
    if (draft.trim().isNotEmpty && details.product != null) {
      try {
        AdjustStock(ref.read(productDetailsRepositoryProvider))
            .validate(draft, details.product!, operation: operation);
      } on StockInputException catch (failure) {
        error = failure;
      }
    }
    return StockUpdateState(
      details: details,
      draft: draft,
      operation: operation,
      fieldError: error,
      message: message,
    );
  }

  StockCountConfirmation? confirmation() {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return null;
    final product = current.details.product!;
    return StockCountConfirmation(
      product: product,
      count: AdjustStock(ref.read(productDetailsRepositoryProvider))
          .validate(current.draft, product, operation: current.operation),
      operation: current.operation,
    );
  }

  Future<void> save(StockCountConfirmation confirmation) async {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return;
    final proposed = this.confirmation();
    if (proposed == null ||
        proposed.product.id != confirmation.product.id ||
        proposed.product.stock != confirmation.product.stock ||
        proposed.operation != confirmation.operation ||
        proposed.count.text != confirmation.count.text) {
      return;
    }
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    var details = current.details;
    var writeStarted = false;
    state = AsyncData(
      StockUpdateState(
        details: details,
        draft: current.draft,
        operation: current.operation,
        phase: StockUpdatePhase.saving,
      ),
    );
    try {
      // Recheck permission, adjustability and the confirmed stock.
      details = await ManageProductDetails(repository).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      final product = details.product;
      final checked = StockUpdateState(details: details);
      if (!checked.permitted) {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            current.operation,
            message: product == null
                ? 'Product is no longer available.'
                : !details.access.adjustStock
                ? 'You do not have permission to update this stock.'
                : 'Stock for this product cannot be counted here.',
          ),
        );
        return;
      }
      if (product!.id != confirmation.product.id ||
          product.stock != confirmation.product.stock) {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            current.operation,
            message:
                'The stock changed. Review the current quantity '
                'and confirm again.',
          ),
        );
        return;
      }
      writeStarted = true;
      // The freshly verified version guards the write (If-Match).
      final adjustment = await AdjustStock(repository)(
        StockCountConfirmation(
          product: product,
          count: confirmation.count,
          operation: confirmation.operation,
        ),
      );
      if (!ref.mounted || generation != _generation) return;
      final updated = adjustment.product;
      if (updated.id != product.id ||
          updated.barcode != barcode ||
          updated.stock != adjustment.newQuantity) {
        throw invalidResponse;
      }
      state = AsyncData(
        StockUpdateState(
          details: ProductDetailsState(updated, details.access),
          draft: confirmation.count.text,
          operation: confirmation.operation,
          phase: StockUpdatePhase.saved,
          previousQuantity: adjustment.previousQuantity,
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      if (error is AppFailure && error.kind == FailureKind.conflict) {
        // Nothing was written: show the latest stock, keep the count.
        try {
          final latest = await ManageProductDetails(repository).load(barcode);
          if (!ref.mounted || generation != _generation) return;
          state = AsyncData(
            _editing(
              latest,
              current.draft,
              current.operation,
              message: error.message,
            ),
          );
          ref.invalidate(productDetailsControllerProvider(barcode));
          return;
        } on Exception {
          if (!ref.mounted || generation != _generation) return;
        }
      }
      final denied =
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
      if (writeStarted && !denied) {
        state = AsyncData(
          StockUpdateState(
            details: details,
            draft: current.draft,
            operation: current.operation,
            phase: StockUpdatePhase.uncertain,
            message:
                'The stock update could not be confirmed. Check the current '
                'stock before counting again.',
          ),
        );
      } else {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            current.operation,
            message: error is AppFailure
                ? error.message
                : error is FormatException
                ? error.message
                : 'Unable to check or update this stock. '
                      'Try again after refreshing.',
          ),
        );
      }
    }
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
        return StockUpdateState(details: details);
      });
      if (ref.mounted && generation == _generation) state = result;
      return;
    }
    final current = state.value;
    if (current == null || current.busy) return;
    ref.read(readCacheProvider)?.retryRead();
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    state = AsyncData(
      StockUpdateState(
        details: current.details,
        draft: current.draft,
        operation: current.operation,
        phase: StockUpdatePhase.checking,
      ),
    );
    try {
      final details = await ManageProductDetails(repository).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        _editing(
          details,
          current.draft,
          current.operation,
          message: 'Current stock refreshed. Review before updating.',
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        StockUpdateState(
          details: current.details,
          draft: current.draft,
          operation: current.operation,
          phase: current.phase == StockUpdatePhase.uncertain
              ? StockUpdatePhase.uncertain
              : StockUpdatePhase.editing,
          fieldError: current.fieldError,
          message: error is AppFailure
              ? error.message
              : 'Unable to refresh the current stock.',
        ),
      );
    }
  }
}

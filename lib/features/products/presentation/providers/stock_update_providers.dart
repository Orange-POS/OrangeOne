import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/adjust_stock.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum StockUpdatePhase { editing, saving, checking, saved, uncertain }

class StockUpdateState {
  const new({
    required this.details,
    this.draft = '',
    this.phase = StockUpdatePhase.editing,
    this.fieldError,
    this.message,
    this.previousQuantity,
  });
  final ProductDetailsState details;
  final String draft;
  final StockUpdatePhase phase;
  final String? fieldError;
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

  void changeQuantity(String raw) {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        current.busy ||
        current.phase == StockUpdatePhase.saved ||
        current.phase == StockUpdatePhase.uncertain) {
      return;
    }
    state = AsyncData(_editing(current.details, raw));
  }

  StockUpdateState _editing(
    ProductDetailsState details,
    String draft, {
    String? message,
  }) {
    String? error;
    if (draft.trim().isNotEmpty && details.product != null) {
      try {
        AdjustStock(ref.read(productDetailsRepositoryProvider))
            .validate(draft, details.product!);
      } on FormatException catch (failure) {
        error = failure.message;
      }
    }
    return StockUpdateState(
      details: details,
      draft: draft,
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
          .validate(current.draft, product),
    );
  }

  Future<void> save(StockCountConfirmation confirmation) async {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return;
    final proposed = this.confirmation();
    if (proposed == null ||
        proposed.product.id != confirmation.product.id ||
        proposed.product.stock != confirmation.product.stock ||
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
        StockCountConfirmation(product: product, count: confirmation.count),
      );
      if (!ref.mounted || generation != _generation) return;
      final updated = adjustment.product;
      if (updated.id != product.id ||
          updated.barcode != barcode ||
          updated.stock != confirmation.count.quantity) {
        throw invalidResponse;
      }
      state = AsyncData(
        StockUpdateState(
          details: ProductDetailsState(updated, details.access),
          draft: confirmation.count.text,
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
            _editing(latest, current.draft, message: error.message),
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

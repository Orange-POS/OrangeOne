import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/update_product_price.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum PriceUpdatePhase { editing, saving, checking, saved, uncertain }

class PriceUpdateState {
  const new({
    required this.details,
    this.draft = '',
    this.phase = PriceUpdatePhase.editing,
    this.fieldError,
    this.message,
  });
  final ProductDetailsState details;
  final String draft;
  final PriceUpdatePhase phase;
  final String? fieldError;
  final String? message;
  bool get busy =>
      phase == PriceUpdatePhase.saving || phase == PriceUpdatePhase.checking;
  bool get canSubmit =>
      phase == PriceUpdatePhase.editing &&
      details.product != null &&
      details.access.updatePrice &&
      draft.trim().isNotEmpty &&
      fieldError == null;
}

final AsyncNotifierProviderFamily<
  PriceUpdateController,
  PriceUpdateState,
  String
>
priceUpdateControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PriceUpdateController, PriceUpdateState, String>(
      PriceUpdateController.new,
      name: 'priceUpdateControllerProvider',
      retry: (count, error) => null,
    );

class PriceUpdateController extends AsyncNotifier<PriceUpdateState> {
  new(this.barcode);
  final String barcode;
  int _generation = 0;

  @override
  Future<PriceUpdateState> build() async {
    _generation++;
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) unawaited(refresh());
    });
    final repository = ref.watch(productDetailsRepositoryProvider);
    final details = await ManageProductDetails(repository).load(barcode);
    return PriceUpdateState(details: details);
  }

  void changePrice(String raw) {
    final current = state.value;
    if (state.isLoading ||
        current == null ||
        current.busy ||
        current.phase == PriceUpdatePhase.saved ||
        current.phase == PriceUpdatePhase.uncertain) {
      return;
    }
    state = AsyncData(_editing(current.details, raw));
  }

  PriceUpdateState _editing(
    ProductDetailsState details,
    String draft, {
    String? message,
  }) {
    String? error;
    if (draft.trim().isNotEmpty && details.product != null) {
      try {
        UpdateProductPrice(ref.read(productDetailsRepositoryProvider))
            .validate(draft, details.product!);
      } on FormatException catch (failure) {
        error = failure.message;
      }
    }
    return PriceUpdateState(
      details: details,
      draft: draft,
      fieldError: error,
      message: message,
    );
  }

  PriceChangeConfirmation? confirmation() {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return null;
    return PriceChangeConfirmation(
      product: current.details.product!,
      price: UpdateProductPrice(ref.read(productDetailsRepositoryProvider))
          .validate(current.draft, current.details.product!),
    );
  }

  Future<void> save(PriceChangeConfirmation confirmation) async {
    final current = state.value;
    if (state.isLoading || current == null || !current.canSubmit) return;
    final proposed = this.confirmation();
    if (proposed == null ||
        proposed.product.id != confirmation.product.id ||
        proposed.product.price != confirmation.product.price ||
        proposed.price.minorUnits != confirmation.price.minorUnits) {
      return;
    }
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    var details = current.details;
    var writeStarted = false;
    state = AsyncData(
      PriceUpdateState(
        details: details,
        draft: current.draft,
        phase: PriceUpdatePhase.saving,
      ),
    );
    try {
      // Recheck permission, identity and price after confirmation.
      details = await ManageProductDetails(repository).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      final product = details.product;
      if (product == null || !details.access.updatePrice) {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            message: product == null
                ? 'Product is no longer available.'
                : 'You do not have permission to update this price.',
          ),
        );
        return;
      }
      if (product.id != confirmation.product.id ||
          product.price != confirmation.product.price) {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            message:
                'The product price changed. Review the current price '
                'and confirm again.',
          ),
        );
        return;
      }
      writeStarted = true;
      final updated = await UpdateProductPrice(repository)(confirmation);
      if (!ref.mounted || generation != _generation) return;
      if (updated.id != product.id ||
          updated.barcode != barcode ||
          updated.price.toStringAsFixed(2) != confirmation.price.formatted) {
        throw invalidResponse;
      }
      state = AsyncData(
        PriceUpdateState(
          details: ProductDetailsState(updated, details.access),
          draft: updated.price.toStringAsFixed(2),
          phase: PriceUpdatePhase.saved,
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      final denied =
          error is AppFailure &&
          {
            FailureKind.forbidden,
            FailureKind.validation,
            FailureKind.unauthenticated,
          }.contains(error.kind);
      if (writeStarted && !denied) {
        state = AsyncData(
          PriceUpdateState(
            details: details,
            draft: current.draft,
            phase: PriceUpdatePhase.uncertain,
            message:
                'The save could not be confirmed. Check the current server '
                'price before attempting another update.',
          ),
        );
      } else {
        state = AsyncData(
          _editing(
            details,
            current.draft,
            message: error is AppFailure
                ? error.message
                : 'Unable to check or update this price. '
                      'Try again after refreshing.',
          ),
        );
      }
    }
  }

  Future<void> refresh() async {
    ref.read(readCacheProvider)?.retryRead();
    final current = state.value;
    if (state.isLoading || current == null || current.busy) return;
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    state = AsyncData(
      PriceUpdateState(
        details: current.details,
        draft: current.draft,
        phase: PriceUpdatePhase.checking,
      ),
    );
    try {
      final details = await ManageProductDetails(repository).load(barcode);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        _editing(
          details,
          current.draft,
          message: 'Current price refreshed. Review before updating.',
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        PriceUpdateState(
          details: current.details,
          draft: current.draft,
          phase: current.phase == PriceUpdatePhase.uncertain
              ? PriceUpdatePhase.uncertain
              : PriceUpdatePhase.editing,
          fieldError: current.fieldError,
          message: error is AppFailure
              ? error.message
              : 'Unable to refresh the current price.',
        ),
      );
    }
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';
import 'package:orange_one/features/products/domain/use_cases/manage_product_details.dart';

final Provider<ProductDetailsRepository> productDetailsRepositoryProvider =
    Provider.autoDispose(
      (ref) => throw invalidSession,
      name: 'productDetailsRepositoryProvider',
    );

final AsyncNotifierProviderFamily<
  ProductDetailsController,
  ProductDetailsState,
  String
>
productDetailsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ProductDetailsController, ProductDetailsState, String>(
      ProductDetailsController.new,
      name: 'productDetailsControllerProvider',
      retry: (count, error) => null,
    );

class ProductDetailsController extends AsyncNotifier<ProductDetailsState> {
  new(this.barcode);
  final String barcode;
  bool _saving = false;
  int _generation = 0;
  @override
  Future<ProductDetailsState> build() {
    _generation++;
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) unawaited(refresh());
    });
    return ManageProductDetails(ref.watch(productDetailsRepositoryProvider))
        .load(barcode);
  }

  Future<void> refresh() async {
    if (_saving || state.isLoading) return;
    ref.read(readCacheProvider)?.retryRead();
    final generation = _generation;
    final useCase = ManageProductDetails(
      ref.read(productDetailsRepositoryProvider),
    );
    final result = await AsyncValue.guard(() => useCase.load(barcode));
    if (ref.mounted && generation == _generation) state = result;
  }

  Future<void> save({String? name, String? price}) async {
    if (_saving || state.isLoading) return;
    ref.read(readCacheProvider)?.retryRead();
    final generation = _generation;
    final current = state.requireValue;
    final product = current.product;
    if (product == null) throw invalidResponse;
    if ((name != null && !current.access.editName) ||
        (price != null && !current.access.updatePrice)) {
      throw const AppFailure(
        FailureKind.forbidden,
        'You do not have permission for this product action.',
      );
    }
    _saving = true;
    try {
      final useCase = ManageProductDetails(
        ref.read(productDetailsRepositoryProvider),
      );
      if (name != null) await useCase.rename(product.id, name);
      if (price != null) await useCase.reprice(product.id, price);
      if (!ref.mounted || generation != _generation) return;
      // A confirmed write is never retried. Re-read authoritative details.
      state = const AsyncLoading();
      final updated = await AsyncValue.guard(() => useCase.load(barcode));
      if (ref.mounted && generation == _generation) state = updated;
    } finally {
      _saving = false;
    }
  }
}

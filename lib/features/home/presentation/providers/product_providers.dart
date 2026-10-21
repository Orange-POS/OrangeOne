import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';
import 'package:orange_one/features/home/domain/use_cases/lookup_product.dart';

/// App composition binds this contract to the current authenticated session.
final Provider<ProductRepository> productRepositoryProvider =
    Provider.autoDispose<ProductRepository>(
      (ref) => throw invalidSession,
      name: 'productRepositoryProvider',
    );

final Provider<LookupProduct> lookupProductProvider =
    Provider.autoDispose<LookupProduct>(
      (ref) => LookupProduct(ref.watch(productRepositoryProvider)),
      name: 'lookupProductProvider',
    );

class ProductLookup {
  const new({required this.barcode, this.product});
  final String barcode;
  final Product? product;
}

final AsyncNotifierProvider<ProductLookupController, ProductLookup?>
productLookupControllerProvider =
    AsyncNotifierProvider.autoDispose<ProductLookupController, ProductLookup?>(
      ProductLookupController.new,
      name: 'productLookupControllerProvider',
      retry: (count, error) => null,
    );

class ProductLookupController extends AsyncNotifier<ProductLookup?> {
  var _generation = 0;
  String? _lastBarcode;
  String? _retryBarcode;

  @override
  ProductLookup? build() {
    ref.watch(lookupProductProvider);
    _generation++;
    _lastBarcode = null;
    _retryBarcode = null;
    return null;
  }

  Future<void> scan(String raw, {bool retry = false}) async {
    if (state.isLoading) return;
    final generation = _generation;
    try {
      final barcode = LookupProduct.validate(raw);
      if (!retry && barcode == _lastBarcode) return;
      _lastBarcode = barcode;
      _retryBarcode = barcode;
      final lookup = ref.read(lookupProductProvider);
      state = const AsyncLoading();
      final product = await lookup(barcode, refresh: retry);
      if (ref.mounted && generation == _generation) {
        state = AsyncData(ProductLookup(barcode: barcode, product: product));
      }
    } on FormatException catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        _retryBarcode = null;
        state = AsyncError(
          const AppFailure(
            FailureKind.validation,
            'Scan a valid product barcode.',
          ),
          stack,
        );
      }
    } on AppFailure catch (error, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(error, stack);
      }
    } on Exception catch (_, stack) {
      if (ref.mounted && generation == _generation) {
        state = AsyncError(
          const AppFailure(
            FailureKind.backend,
            'Unable to look up this product.',
          ),
          stack,
        );
      }
    }
  }

  Future<void> retry() async {
    final barcode = _retryBarcode;
    final failure = state.error;
    if (barcode != null &&
        failure is AppFailure &&
        {FailureKind.network, FailureKind.timeout}.contains(failure.kind)) {
      await scan(barcode, retry: true);
    }
  }

  void scanAgain() {
    if (state.isLoading) return;
    _generation++;
    _lastBarcode = null;
    _retryBarcode = null;
    state = const AsyncData(null);
  }
}

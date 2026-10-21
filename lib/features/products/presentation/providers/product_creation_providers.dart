import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/use_cases/create_product.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';

enum ProductCreationPhase { editing, creating, saved, uncertain }

class ProductCreationState {
  const new({
    required this.context,
    this.name = '',
    this.price = '',
    this.taxIds,
    this.phase = ProductCreationPhase.editing,
    this.message,
    this.created,
  });
  final ProductCreationContext context;
  final String name;
  final String price;
  final List<int>? taxIds;
  final ProductCreationPhase phase;
  final String? message;
  final ProductDetails? created;
  bool get busy => phase == ProductCreationPhase.creating;
  bool get editable =>
      phase == ProductCreationPhase.editing && context.canCreate;
  String? get nameError {
    if (name.isEmpty) return null;
    try {
      NewProduct.validateName(name);
    } on FormatException catch (e) {
      return e.message;
    }
    return null;
  }

  String? get priceError {
    if (price.isEmpty) return null;
    try {
      ChfPrice.parse(price);
    } on FormatException catch (e) {
      return e.message;
    }
    return null;
  }

  bool get canSubmit =>
      editable &&
      name.trim().isNotEmpty &&
      price.isNotEmpty &&
      nameError == null &&
      priceError == null &&
      taxIds != null;
  String get taxLabel => taxIds == null
      ? 'Select Tax'
      : taxIds!.isEmpty
      ? 'No Tax'
      : context.taxes
            .where((t) => taxIds!.contains(t.id))
            .map((t) => t.label)
            .join(', ');
}

final AsyncNotifierProviderFamily<
  ProductCreationController,
  ProductCreationState,
  String
>
productCreationControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ProductCreationController, ProductCreationState, String>(
      ProductCreationController.new,
      name: 'productCreationControllerProvider',
      retry: (count, error) => null,
    );

class ProductCreationController extends AsyncNotifier<ProductCreationState> {
  new(this.barcode);
  final String barcode;
  int _generation = 0;
  bool _recovering = false;

  @override
  Future<ProductCreationState> build() async {
    _generation++;
    ref.listen(readCacheRecoveryProvider, (previous, next) {
      if (next.hasValue) unawaited(_recover());
    });
    NewProduct.validateBarcode(barcode);
    final repository = ref.watch(productDetailsRepositoryProvider);
    return ProductCreationState(
      context: await repository.prepareCreation(barcode),
    );
  }

  /// Retry an initial read failure without submitting or replaying a save.
  Future<void> retryInitialLoad() async {
    if (state.isLoading || !state.hasError) return;
    final generation = _generation;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      NewProduct.validateBarcode(barcode);
      final context = await ref
          .read(productDetailsRepositoryProvider)
          .prepareCreation(barcode, refresh: true);
      return ProductCreationState(context: context);
    });
    if (ref.mounted && generation == _generation) state = result;
  }

  Future<void> _recover() async {
    final current = state.value;
    if (_recovering ||
        current == null ||
        current.busy ||
        current.phase != ProductCreationPhase.editing) {
      return;
    }
    _recovering = true;
    final generation = _generation;
    try {
      final context = await ref
          .read(productDetailsRepositoryProvider)
          .prepareCreation(barcode);
      if (!ref.mounted || generation != _generation) return;
      final latest = state.value;
      if (latest == null || latest.busy) return;
      state = AsyncData(
        ProductCreationState(
          context: context,
          name: latest.name,
          price: latest.price,
          taxIds: latest.taxIds,
          message: 'Product availability refreshed. Review before creating.',
        ),
      );
    } on AppFailure catch (error) {
      if (ref.mounted && generation == _generation) {
        final latest = state.value ?? current;
        state = AsyncData(
          ProductCreationState(
            context: latest.context,
            name: latest.name,
            price: latest.price,
            taxIds: latest.taxIds,
            message: error.message,
          ),
        );
      }
    } finally {
      _recovering = false;
    }
  }

  void edit({String? name, String? price, List<int>? taxIds}) {
    final current = state.value;
    if (current == null || !current.editable) return;
    state = AsyncData(
      ProductCreationState(
        context: current.context,
        name: name ?? current.name,
        price: price ?? current.price,
        taxIds: taxIds ?? current.taxIds,
      ),
    );
  }

  Future<void> save() async {
    final current = state.value;
    if (_recovering || current == null || !current.canSubmit) return;
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    final useCase = CreateProduct(repository);
    final draft = useCase.validate(
      barcode: barcode,
      name: current.name,
      price: current.price,
      taxIds: current.taxIds,
      context: current.context,
    );
    state = AsyncData(
      ProductCreationState(
        context: current.context,
        name: current.name,
        price: current.price,
        taxIds: current.taxIds,
        phase: ProductCreationPhase.creating,
      ),
    );
    try {
      final created = await useCase(draft);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        ProductCreationState(
          context: current.context,
          name: created.name,
          price: created.price.toStringAsFixed(2),
          taxIds: current.taxIds,
          phase: ProductCreationPhase.saved,
          created: created,
        ),
      );
      ref.invalidate(productDetailsControllerProvider(barcode));
    } on Exception catch (error) {
      if (!ref.mounted || generation != _generation) return;
      final rejected =
          error is AppFailure &&
          {
            FailureKind.validation,
            FailureKind.forbidden,
            FailureKind.unauthenticated,
          }.contains(error.kind);
      state = AsyncData(
        ProductCreationState(
          context: current.context,
          name: current.name,
          price: current.price,
          taxIds: current.taxIds,
          phase: rejected
              ? ProductCreationPhase.editing
              : ProductCreationPhase.uncertain,
          message:
              error is AppFailure &&
                  (rejected || error.kind == FailureKind.conflict)
              ? error.message
              : 'Creation could not be confirmed. '
                    'Check the barcode before trying again.',
        ),
      );
    }
  }

  Future<void> check() async {
    final current = state.value;
    if (current == null || current.busy) return;
    final generation = _generation;
    final repository = ref.read(productDetailsRepositoryProvider);
    state = AsyncData(
      ProductCreationState(
        context: current.context,
        name: current.name,
        price: current.price,
        taxIds: current.taxIds,
        phase: ProductCreationPhase.creating,
      ),
    );
    try {
      final context = await repository.prepareCreation(barcode, refresh: true);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        ProductCreationState(
          context: context,
          name: current.name,
          price: current.price,
          taxIds: current.taxIds,
        ),
      );
    } on Exception {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        ProductCreationState(
          context: current.context,
          name: current.name,
          price: current.price,
          taxIds: current.taxIds,
          phase: ProductCreationPhase.uncertain,
          message: 'Unable to check this barcode. Your entries are preserved.',
        ),
      );
    }
  }
}

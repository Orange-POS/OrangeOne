import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/core/storage/read_cache_providers.dart';
import 'package:orange_one/features/products/domain/entities/chf_price.dart';
import 'package:orange_one/features/products/domain/entities/new_product.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/stock_count.dart';
import 'package:orange_one/features/products/domain/use_cases/create_product.dart';
import 'package:orange_one/features/products/presentation/providers/product_details_providers.dart';
import 'package:orange_one/features/products/presentation/providers/product_success_providers.dart';

enum ProductCreationPhase { editing, creating, saved, uncertain }

class ProductCreationState {
  const new({
    required this.context,
    this.name = '',
    this.price = '',
    this.stock = '',
    this.taxIds,
    this.categoryId,
    this.phase = ProductCreationPhase.editing,
    this.message,
    this.created,
  });

  /// A fresh form: the backend's default tax (when one is configured) is
  /// already applied, so the user need not choose a tax.
  factory initial(ProductCreationContext context) =>
      ProductCreationState(context: context, taxIds: context.initialTaxIds);

  final ProductCreationContext context;
  final String name;

  /// Optional; empty means 0.00.
  final String price;

  /// Optional; empty means *not set* (never zero).
  final String stock;
  final List<int>? taxIds;
  final int? categoryId;
  final ProductCreationPhase phase;
  final String? message;
  final ProductDetails? created;

  ProductCreationState copy({
    ProductCreationContext? context,
    String? name,
    String? price,
    String? stock,
    List<int>? taxIds,
    int? categoryId,
    ProductCreationPhase phase = ProductCreationPhase.editing,
    String? message,
    ProductDetails? created,
  }) => ProductCreationState(
    context: context ?? this.context,
    name: name ?? this.name,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    taxIds: taxIds ?? this.taxIds,
    categoryId: categoryId ?? this.categoryId,
    phase: phase,
    message: message,
    created: created,
  );

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

  String? get stockError {
    if (stock.trim().isEmpty) return null;
    try {
      StockCount.parse(stock);
    } on FormatException catch (e) {
      return e.message;
    }
    return null;
  }

  /// Name, tax and category are required; price and stock are optional.
  bool get canSubmit =>
      editable &&
      name.trim().isNotEmpty &&
      nameError == null &&
      priceError == null &&
      stockError == null &&
      taxIds != null &&
      categoryId != null;

  /// The tax names for the confirmation; null while none is chosen.
  String? taxText(String noTax) => taxIds == null
      ? null
      : taxIds!.isEmpty
      ? noTax
      : context.taxes
            .where((t) => taxIds!.contains(t.id))
            .map((t) => t.label)
            .join(', ');

  String? get categoryName {
    for (final category in context.categories) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }

  /// The price that will be sent: 0.00 when none was entered.
  String get effectivePrice =>
      ChfPrice.parse(price.trim().isEmpty ? '0.00' : price).formatted;
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
    return ProductCreationState.initial(
      await repository.prepareCreation(barcode),
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
      return ProductCreationState.initial(context);
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
        latest.copy(
          context: context,
          message: 'Product availability refreshed. Review before creating.',
        ),
      );
    } on AppFailure catch (error) {
      if (ref.mounted && generation == _generation) {
        final latest = state.value ?? current;
        state = AsyncData(latest.copy(message: error.message));
      }
    } finally {
      _recovering = false;
    }
  }

  void edit({
    String? name,
    String? price,
    String? stock,
    List<int>? taxIds,
    int? categoryId,
  }) {
    final current = state.value;
    if (current == null || !current.editable) return;
    state = AsyncData(
      current.copy(
        name: name,
        price: price,
        stock: stock,
        taxIds: taxIds,
        categoryId: categoryId,
      ),
    );
  }

  /// Creates a category (`POST /categories`) and applies it to this form.
  /// Failures are rethrown for the picker to show.
  Future<ProductCategory> createCategory(String name) async {
    final current = state.value;
    if (current == null ||
        !current.editable ||
        !current.context.details.access.createCategory) {
      throw const FormatException('Category creation is not available.');
    }
    final created = await ref
        .read(productDetailsRepositoryProvider)
        .createCategory(name);
    if (!ref.mounted) return created;
    final latest = state.value ?? current;
    final context = latest.context;
    state = AsyncData(
      latest.copy(
        context: ProductCreationContext(
          details: context.details,
          taxes: context.taxes,
          defaultTaxIds: context.defaultTaxIds,
          categories: List.unmodifiable([
            ...context.categories.where((c) => c.id != created.id),
            created,
          ]),
        ),
        categoryId: created.id,
      ),
    );
    return created;
  }

  Future<void> save() async {
    final current = state.value;
    if (_recovering || current == null || !current.canSubmit) return;
    final generation = _generation;
    final scope = ref.read(unsetStockScopeProvider);
    final repository = ref.read(productDetailsRepositoryProvider);
    final useCase = CreateProduct(repository);
    final draft = useCase.validate(
      barcode: barcode,
      name: current.name,
      price: current.price,
      taxIds: current.taxIds,
      categoryId: current.categoryId,
      stock: current.stock,
      context: current.context,
    );
    state = AsyncData(current.copy(phase: ProductCreationPhase.creating));
    try {
      final created = await useCase(draft);
      if (!ref.mounted || generation != _generation) return;
      // No quantity was entered: the stock is not set, which is not zero.
      if (draft.initialQuantity == null) {
        ref.read(unsetStockProvider.notifier).mark(created.id, scope: scope);
      }
      state = AsyncData(
        current.copy(
          name: created.name,
          price: created.price.toStringAsFixed(2),
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
        current.copy(
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
    state = AsyncData(current.copy(phase: ProductCreationPhase.creating));
    try {
      final context = await repository.prepareCreation(barcode, refresh: true);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(current.copy(context: context));
    } on Exception {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        current.copy(
          phase: ProductCreationPhase.uncertain,
          message: 'Unable to check this barcode. Your entries are preserved.',
        ),
      );
    }
  }
}

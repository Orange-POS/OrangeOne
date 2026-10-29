import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A confirmed change that Product Details announces in its success toast.
class ProductSuccess {
  const new({
    required this.barcode,
    required this.title,
    required this.message,
  });
  final String barcode;
  final String title;
  final String message;
}

/// Hands a success message from a finished form to the Product Details
/// screen it returns to. Container-lived, so it survives the navigation.
final NotifierProvider<ProductSuccessController, ProductSuccess?>
productSuccessProvider =
    NotifierProvider<ProductSuccessController, ProductSuccess?>(
      ProductSuccessController.new,
      name: 'productSuccessProvider',
    );

class ProductSuccessController extends Notifier<ProductSuccess?> {
  @override
  ProductSuccess? build() => null;

  void show({
    required String barcode,
    required String title,
    required String message,
  }) =>
      state = ProductSuccess(barcode: barcode, title: title, message: message);

  void dismiss() => state = null;
}

/// Identity of the authenticated session that owns the unset-stock flags, or
/// null while signed out. The app binds it to the session identity; it changes
/// on logout, expiry, authentication rejection and session replacement.
final Provider<String?> unsetStockScopeProvider = Provider<String?>(
  (ref) => null,
  name: 'unsetStockScopeProvider',
);

/// Products created without a stock quantity, by backend product id within the
/// current session. Their stock is *not set*, which is different from a counted
/// quantity of zero, until a count is saved. A barcode is not an identity: two
/// shops can hold different products with the same one.
final NotifierProvider<UnsetStockController, Set<int>> unsetStockProvider =
    NotifierProvider<UnsetStockController, Set<int>>(
      UnsetStockController.new,
      name: 'unsetStockProvider',
    );

class UnsetStockController extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    // A different session (or none) starts with no flags.
    ref.watch(unsetStockScopeProvider);
    return const {};
  }

  /// Marks [productId] for the session that created it ([scope]); ignored when
  /// that session is no longer the active one.
  void mark(int productId, {required String? scope}) {
    if (scope == null || scope != ref.read(unsetStockScopeProvider)) return;
    state = {...state, productId};
  }

  void clear(int productId) => state = {...state}..remove(productId);
}

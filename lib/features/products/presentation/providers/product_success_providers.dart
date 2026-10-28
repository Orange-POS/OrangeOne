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

/// Barcodes created without a stock quantity. Their stock is *not set*, which
/// is different from a counted quantity of zero, until a count is saved.
final NotifierProvider<UnsetStockController, Set<String>> unsetStockProvider =
    NotifierProvider<UnsetStockController, Set<String>>(
      UnsetStockController.new,
      name: 'unsetStockProvider',
    );

class UnsetStockController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String barcode) => state = {...state, barcode};

  void clear(String barcode) => state = {...state}..remove(barcode);
}

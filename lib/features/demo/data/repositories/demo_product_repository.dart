import 'package:orange_one/features/demo/data/repositories/demo_catalog.dart';
import 'package:orange_one/features/home/domain/entities/product.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';

/// Barcode lookup against the Demo Mode sample inventory only.
class DemoProductRepository implements ProductRepository {
  const new(this._catalog);
  final DemoCatalog _catalog;

  @override
  Future<Product?> findByBarcode(String barcode, {bool refresh = false}) async {
    final details = _catalog.byBarcode(barcode);
    if (details == null) return null;
    return Product(
      id: details.id,
      name: details.name,
      barcode: details.barcode,
      price: details.price,
      stockQuantity: details.stock,
      unit: details.unit,
      reference: details.reference,
      category: details.category?.name,
    );
  }
}

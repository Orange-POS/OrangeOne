class ProductCategory {
  const new({required this.id, required this.name});
  final int id;
  final String name;
}

/// A requested category assignment; a null [id] removes the category.
class CategoryChange {
  const new(this.id);
  final int? id;
}

class ProductDetails {
  const new({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
    this.unit = '',
    this.reference = '',
    this.taxes = const [],
    this.taxIds,
    this.currency,
    this.category,
    this.description,
    this.version,
    this.stockAdjustable = false,
  });
  final int id;
  final String name;
  final String barcode;
  final double price;

  /// On-hand quantity; null when the backend does not track this product's
  /// stock (shown as unavailable, never fabricated).
  final double? stock;
  final String unit;
  final String reference;
  final List<String> taxes;

  /// Null means the response did not supply complete tax identities.
  final List<int>? taxIds;

  /// ISO currency code of [price]; null for offline cached reads.
  final String? currency;
  final ProductCategory? category;

  /// Subtitle shown under the product name.
  final String? description;

  /// Write-concurrency token (`If-Match`); null for offline cached reads.
  final String? version;

  /// Whether the backend accepts an absolute stock count for this product.
  final bool stockAdjustable;
}

/// Effective permissions from the backend (never cached).
class ProductAccess {
  const new({
    this.editName = false,
    this.updatePrice = false,
    this.readReferences = false,
    this.updateTaxes = false,
    this.updateCategory = false,
    this.createProduct = false,
    this.adjustStock = false,
    this.readHistory = false,
  });
  final bool editName;
  final bool updatePrice;

  /// Tax and category options may be listed.
  final bool readReferences;
  final bool updateTaxes;
  final bool updateCategory;
  final bool createProduct;
  final bool adjustStock;
  final bool readHistory;
}

class ProductDetailsState {
  const new(this.product, this.access);
  final ProductDetails? product;
  final ProductAccess access;
}

/// One row of `GET /products`.
class ProductSummary {
  const new({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    this.barcode,
    this.stock,
  });
  final int id;
  final String name;
  final String? barcode;
  final double price;
  final String currency;
  final double? stock;
}

/// A page of products; [nextCursor] is null on the last page.
class ProductPage {
  const new(this.items, this.nextCursor);
  final List<ProductSummary> items;
  final String? nextCursor;
}

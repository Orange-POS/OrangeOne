import 'package:orange_one/core/errors/app_failure.dart';
import 'package:orange_one/features/products/domain/entities/product_details.dart';
import 'package:orange_one/features/products/domain/entities/product_tax.dart';

/// A product after a stock change and its quantity before the change.
class StockChange {
  const new(this.product, this.before);
  final ProductDetails product;
  final double before;
}

/// Isolated, in-memory sample inventory for Demo Mode. It never touches the
/// network, storage or any real customer data, and every run starts from the
/// same sample data.
class DemoCatalog {
  new _(this._records, this.taxes, this.categories);

  factory seeded() => DemoCatalog._(
    [for (final seed in _seeds) _DemoRecord.from(seed)],
    const [ProductTax(id: 1, label: '8.1%'), ProductTax(id: 2, label: '2.6%')],
    [
      const ProductCategory(id: 1, name: 'Beverages'),
      const ProductCategory(id: 2, name: 'Bakery'),
      const ProductCategory(id: 3, name: 'Dairy'),
      const ProductCategory(id: 4, name: 'Pantry'),
    ],
  );

  /// Sample taxes offered when creating or editing a product.
  final List<ProductTax> taxes;
  final List<ProductCategory> categories;
  final List<_DemoRecord> _records;
  var _nextId = 1000;
  var _nextCategoryId = 100;

  /// The barcode of every sample product.
  List<String> get sampleBarcodes => [
    for (final record in _records) record.barcode,
  ];

  ProductDetails? byBarcode(String barcode) {
    for (final record in _records) {
      if (record.barcode == barcode) return _details(record);
    }
    return null;
  }

  /// Name, barcode or reference match, ordered by name.
  List<ProductDetails> search({String? query, int? categoryId}) {
    final text = query?.toLowerCase();
    final matches = [
      for (final record in _records)
        if ((categoryId == null || record.categoryId == categoryId) &&
            (text == null ||
                record.name.toLowerCase().contains(text) ||
                record.barcode.contains(text) ||
                record.reference.toLowerCase().contains(text)))
          _details(record),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return matches;
  }

  ProductDetails create({
    required String barcode,
    required String name,
    required double price,
    required List<int> taxIds,
    int? categoryId,
    double? stock,
  }) {
    if (byBarcode(barcode) != null) {
      throw const AppFailure(
        FailureKind.conflict,
        'This barcode already exists. Open its product details.',
      );
    }
    final id = _nextId++;
    final record = _DemoRecord(
      id: id,
      name: name,
      barcode: barcode,
      price: price,
      stock: stock,
      categoryId: categoryId,
      taxIds: List.of(taxIds),
      reference: 'DEMO-$id',
    );
    _records.add(record);
    return _details(record);
  }

  ProductCategory createCategory(String name) {
    final category = ProductCategory(id: _nextCategoryId++, name: name);
    categories.add(category);
    return category;
  }

  ProductDetails rename(ProductDetails product, String name) =>
      _update(product.id, product.version, (record) => record.name = name);

  ProductDetails reprice(ProductDetails product, double price) =>
      _update(product.id, product.version, (record) => record.price = price);

  /// Sets the stock to `apply(stock before)` and reports the stock before.
  StockChange setStock(ProductDetails product, double Function(double) apply) {
    final before = product.stock ?? 0;
    final updated = _update(
      product.id,
      product.version,
      (record) => record.stock = apply(before),
    );
    return StockChange(updated, before);
  }

  ProductDetails updateInformation(
    ProductDetails product, {
    String? name,
    List<int>? taxIds,
    int? categoryId,
    bool changeCategory = false,
  }) => _update(product.id, product.version, (record) {
    if (name != null) record.name = name;
    if (taxIds != null) record.taxIds = List.of(taxIds);
    if (changeCategory) record.categoryId = categoryId;
  });

  /// Applies [change] when [version] is the current one, like the backend's
  /// `If-Match` guard; a stale version fails as a conflict.
  ProductDetails _update(
    int id,
    String? version,
    void Function(_DemoRecord record) change,
  ) {
    final record = _records.firstWhere(
      (record) => record.id == id,
      orElse: () => throw const AppFailure(
        FailureKind.notFound,
        'This product no longer exists.',
      ),
    );
    if (version != record.version.toString()) {
      throw const AppFailure(
        FailureKind.conflict,
        'This product changed. Reload it and try again.',
        code: 'VERSION_CONFLICT',
      );
    }
    change(record);
    record.version++;
    return _details(record);
  }

  ProductDetails _details(_DemoRecord record) {
    ProductCategory? category;
    for (final candidate in categories) {
      if (candidate.id == record.categoryId) category = candidate;
    }
    return ProductDetails(
      id: record.id,
      name: record.name,
      barcode: record.barcode,
      price: record.price,
      stock: record.stock,
      unit: 'Units',
      reference: record.reference,
      taxes: [
        for (final tax in taxes)
          if (record.taxIds.contains(tax.id)) tax.label,
      ],
      taxIds: List.of(record.taxIds),
      currency: 'CHF',
      category: category,
      version: record.version.toString(),
      stockAdjustable: record.stock != null,
      stockLocationId: 1,
      quantityDecimals: 0,
    );
  }
}

class _DemoRecord {
  new({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
    required this.categoryId,
    required this.taxIds,
    required this.reference,
  });

  factory from(_Seed seed) => _DemoRecord(
    id: seed.id,
    name: seed.name,
    barcode: seed.barcode,
    price: seed.price,
    stock: seed.stock,
    categoryId: seed.categoryId,
    taxIds: List.of(seed.taxIds),
    reference: 'DEMO-${seed.id}',
  );

  final int id;
  final String barcode;
  final String reference;
  String name;
  double price;
  double? stock;
  int? categoryId;
  List<int> taxIds;
  int version = 1;
}

class _Seed {
  const new(
    this.id,
    this.name,
    this.barcode,
    this.price,
    this.stock,
    this.categoryId,
    this.taxIds,
  );
  final int id;
  final String name;
  final String barcode;
  final double price;
  final double? stock;
  final int? categoryId;
  final List<int> taxIds;
}

/// Fictional products; the barcodes are not assigned to real goods.
const _seeds = [
  _Seed(1, 'Sparkling Water 1L', '2000000000011', 1.20, 120, 1, [1]),
  _Seed(2, 'Orange Juice 1L', '2000000000028', 3.50, 48, 1, [1]),
  _Seed(3, 'Iced Tea Peach 0.5L', '2000000000035', 2.40, 5, 1, [1]),
  _Seed(4, 'Sourdough Bread 500g', '2000000000042', 4.20, 22, 2, [2]),
  _Seed(5, 'Butter Croissant', '2000000000059', 1.80, 36, 2, [2]),
  _Seed(6, 'Whole Milk 1L', '2000000000066', 1.75, 64, 3, [2]),
  _Seed(7, 'Greek Yogurt 150g', '2000000000073', 1.10, 0, 3, [2]),
  _Seed(8, 'Alpine Cheese 200g', '2000000000080', 6.90, 18, 3, [2]),
  _Seed(9, 'Spaghetti 500g', '2000000000097', 2.30, 80, 4, [2]),
  _Seed(10, 'Olive Oil 750ml', '2000000000103', 11.90, 14, 4, [2]),
  _Seed(11, 'Dark Chocolate 100g', '2000000000110', 2.95, 60, 4, [1]),
  _Seed(12, 'Reusable Shopping Bag', '2000000000127', 3, null, null, []),
];

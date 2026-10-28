/// Read-only product information from a barcode scan.
class Product {
  const new({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stockQuantity,
    this.unit = '',
    this.reference = '',
    this.category,
  });

  final int id;
  final String name;
  final String barcode;
  final double price;

  /// Null when the backend does not track stock (shown as unavailable).
  final double? stockQuantity;
  final String unit;
  final String reference;

  /// Name of the product's category; null when it has none or the data does
  /// not say.
  final String? category;
}

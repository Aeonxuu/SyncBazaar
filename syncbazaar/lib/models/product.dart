class Product {
  const Product({
    required this.id,
    required this.name,
    this.description,
    required this.categoryId,
    required this.basePrice,
    this.stockQuantity = 0,
    this.imagePath,
  });

  final int id;
  final String name;
  final String? description;
  final int categoryId;
  final double basePrice;
  final int stockQuantity;
  final String? imagePath;

  // Backward-compatibility getters for legacy UI sections not yet migrated.
  String get variant => '-';
  String get size => '-';
}

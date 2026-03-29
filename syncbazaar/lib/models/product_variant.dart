class ProductVariantGroup {
  const ProductVariantGroup({
    required this.id,
    required this.productId,
    required this.name,
  });

  final int id;
  final int productId;
  final String name;
}

class ProductVariantOption {
  const ProductVariantOption({
    required this.id,
    required this.variantGroupId,
    required this.value,
    this.extraPrice = 0,
    this.stockQuantity = 0,
  });

  final int id;
  final int variantGroupId;
  final String value;
  final double extraPrice;
  final int stockQuantity;
}

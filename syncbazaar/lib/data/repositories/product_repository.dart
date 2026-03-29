import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';

class ProductAllocationItem {
  const ProductAllocationItem({
    required this.allocationKey,
    required this.product,
    required this.availableQuantity,
    this.group,
    this.option,
  });

  final String allocationKey;
  final Product product;
  final ProductVariantGroup? group;
  final ProductVariantOption? option;
  final int availableQuantity;

  String get displayLabel {
    if (group == null || option == null) {
      return product.name;
    }
    return '${product.name} - ${group!.name} ${option!.value}';
  }
}

class ProductRepository {
  final List<Category> _categories = [
    const Category(id: 1, name: 'Shoes'),
    const Category(id: 2, name: 'Watches'),
    const Category(id: 3, name: 'Bags'),
  ];

  final List<Product> _products = [
    const Product(
      id: 1,
      name: 'Runner Pro',
      categoryId: 1,
      basePrice: 2499,
      imagePath: null,
    ),
    const Product(
      id: 2,
      name: 'Street Lite',
      categoryId: 1,
      basePrice: 1899,
      imagePath: null,
    ),
    const Product(
      id: 3,
      name: 'Classic Watch',
      categoryId: 2,
      basePrice: 3299,
      imagePath: null,
    ),
    const Product(
      id: 4,
      name: 'Carry Mini',
      categoryId: 3,
      basePrice: 1599,
      imagePath: null,
    ),
  ];

  final Map<int, ProductVariantGroup> _variantGroupByProductId = {
    1: const ProductVariantGroup(id: 1001, productId: 1, name: 'Size'),
    3: const ProductVariantGroup(id: 1002, productId: 3, name: 'Color'),
  };

  final Map<int, List<ProductVariantOption>> _variantOptionsByGroupId = {
    1001: const [
      ProductVariantOption(id: 2001, variantGroupId: 1001, value: '41'),
      ProductVariantOption(id: 2002, variantGroupId: 1001, value: '42'),
      ProductVariantOption(id: 2003, variantGroupId: 1001, value: '43'),
    ],
    1002: const [
      ProductVariantOption(id: 2011, variantGroupId: 1002, value: 'Gold'),
      ProductVariantOption(id: 2012, variantGroupId: 1002, value: 'Silver'),
      ProductVariantOption(id: 2013, variantGroupId: 1002, value: 'Copper'),
    ],
  };

  final Map<String, int> _stockByAllocationKey = {
    '1:2001': 20,
    '1:2002': 20,
    '1:2003': 20,
    '2:0': 20,
    '3:2011': 10,
    '3:2012': 10,
    '3:2013': 10,
    '4:0': 20,
  };

  int _nextCategoryId = 100;
  int _nextProductId = 1000;
  int _nextVariantGroupId = 5000;
  int _nextVariantOptionId = 9000;

  String allocationKey(int productId, int? variantOptionId) {
    return '$productId:${variantOptionId ?? 0}';
  }

  int? variantOptionIdFromKey(String key) {
    final parts = key.split(':');
    if (parts.length != 2) return null;
    final parsed = int.tryParse(parts[1]);
    if (parsed == null || parsed == 0) return null;
    return parsed;
  }

  int productIdFromKey(String key) {
    final parts = key.split(':');
    return int.tryParse(parts.first) ?? 0;
  }

  Future<List<Product>> listProducts() async {
    return _products.map(_withComputedStock).toList();
  }

  Future<List<Category>> listCategories() async => List<Category>.from(_categories);

  Future<Category> addCategory({
    required String name,
    String? description,
  }) async {
    final category = Category(
      id: _nextCategoryId++,
      name: name.trim(),
      description: description?.trim().isEmpty == true ? null : description?.trim(),
    );
    _categories.add(category);
    return category;
  }

  Future<void> deleteCategory(int categoryId) async {
    _categories.removeWhere((c) => c.id == categoryId);
    _products.removeWhere((p) => p.categoryId == categoryId);
  }

  Future<void> saveProduct({
    int? id,
    required String name,
    String? description,
    required int categoryId,
    required double basePrice,
    String? imagePath,
    String? variantGroupName,
    List<ProductVariantOption> variantOptions = const [],
    int stockQuantity = 0,
  }) async {
    final normalizedName = name.trim();
    final normalizedDescription =
        description?.trim().isEmpty == true ? null : description?.trim();
    final productId = id ?? _nextProductId++;
    final existingIdx = _products.indexWhere((p) => p.id == productId);

    final next = Product(
      id: productId,
      name: normalizedName,
      description: normalizedDescription,
      categoryId: categoryId,
      basePrice: basePrice,
      imagePath: imagePath,
    );

    if (existingIdx == -1) {
      _products.add(next);
    } else {
      _products[existingIdx] = next;
    }

    _replaceVariantsForProduct(
      productId: productId,
      variantGroupName: variantGroupName,
      variantOptions: variantOptions,
    );

    _ensureStockEntriesForProduct(productId, initialStock: stockQuantity);
  }

  Future<void> deleteProduct(int id) async {
    _products.removeWhere((p) => p.id == id);
    final group = _variantGroupByProductId.remove(id);
    if (group != null) {
      final options = _variantOptionsByGroupId.remove(group.id) ?? const [];
      for (final option in options) {
        _stockByAllocationKey.remove(allocationKey(id, option.id));
      }
    }
    _stockByAllocationKey.remove(allocationKey(id, null));
  }

  Future<ProductVariantGroup?> variantGroupForProduct(int productId) async {
    return _variantGroupByProductId[productId];
  }

  Future<List<ProductVariantOption>> variantOptionsForProduct(int productId) async {
    final group = _variantGroupByProductId[productId];
    if (group == null) {
      return const [];
    }
    final options = _variantOptionsByGroupId[group.id] ?? const [];
    return options
        .map(
          (option) => ProductVariantOption(
            id: option.id,
            variantGroupId: option.variantGroupId,
            value: option.value,
            extraPrice: option.extraPrice,
            stockQuantity:
                _stockByAllocationKey[allocationKey(productId, option.id)] ?? 0,
          ),
        )
        .toList();
  }

  Future<int> availableStock({
    required int productId,
    required int? variantOptionId,
  }) async {
    return _stockByAllocationKey[allocationKey(productId, variantOptionId)] ?? 0;
  }

  Future<Map<int, int>> variantStocksByOptionId(int productId) async {
    final group = _variantGroupByProductId[productId];
    if (group == null) {
      return const {};
    }
    final options = _variantOptionsByGroupId[group.id] ?? const [];
    return {
      for (final option in options)
        option.id: _stockByAllocationKey[allocationKey(productId, option.id)] ?? 0,
    };
  }

  Future<List<ProductAllocationItem>> allocationItems() async {
    final items = <ProductAllocationItem>[];
    final products = await listProducts();
    for (final product in products) {
      final group = _variantGroupByProductId[product.id];
      if (group == null) {
        final key = allocationKey(product.id, null);
        items.add(
          ProductAllocationItem(
            allocationKey: key,
            product: product,
            availableQuantity: _stockByAllocationKey[key] ?? 0,
          ),
        );
        continue;
      }

      final options = _variantOptionsByGroupId[group.id] ?? const [];
      for (final option in options) {
        final key = allocationKey(product.id, option.id);
        items.add(
          ProductAllocationItem(
            allocationKey: key,
            product: product,
            group: group,
            option: option,
            availableQuantity: _stockByAllocationKey[key] ?? 0,
          ),
        );
      }
    }
    return items;
  }

  Future<Map<String, int>> stockByAllocationKey() async {
    return Map<String, int>.from(_stockByAllocationKey);
  }

  Future<Map<int, int>> stockByProductId() async {
    final result = <int, int>{};
    for (final product in _products) {
      final group = _variantGroupByProductId[product.id];
      if (group == null) {
        result[product.id] = _stockByAllocationKey[allocationKey(product.id, null)] ?? 0;
      } else {
        final options = _variantOptionsByGroupId[group.id] ?? const [];
        final total = options.fold<int>(
          0,
          (sum, option) => sum + (_stockByAllocationKey[allocationKey(product.id, option.id)] ?? 0),
        );
        result[product.id] = total;
      }
    }
    return result;
  }

  Future<bool> reserveStocksByAllocationKey(Map<String, int> allocations) async {
    for (final entry in allocations.entries) {
      final current = _stockByAllocationKey[entry.key];
      if (current == null || entry.value < 0 || current < entry.value) {
        return false;
      }
    }

    for (final entry in allocations.entries) {
      _stockByAllocationKey[entry.key] =
          (_stockByAllocationKey[entry.key] ?? 0) - entry.value;
    }
    return true;
  }

  Future<bool> adjustStocksByAllocationKey(Map<String, int> deltasByAllocationKey) async {
    for (final entry in deltasByAllocationKey.entries) {
      final current = _stockByAllocationKey[entry.key];
      if (current == null) {
        return false;
      }
      final next = current + entry.value;
      if (next < 0) {
        return false;
      }
    }

    for (final entry in deltasByAllocationKey.entries) {
      _stockByAllocationKey[entry.key] =
          (_stockByAllocationKey[entry.key] ?? 0) + entry.value;
    }
    return true;
  }

  Future<bool> reserveForSale({
    required int productId,
    required int? variantOptionId,
    required int quantity,
  }) async {
    final key = allocationKey(productId, variantOptionId);
    final current = _stockByAllocationKey[key];
    if (current == null || quantity <= 0 || current < quantity) {
      return false;
    }
    _stockByAllocationKey[key] = current - quantity;
    return true;
  }

  Future<String> categoryNameForProduct(Product product) async {
    final category = _categories.where((c) => c.id == product.categoryId).cast<Category?>().firstWhere(
      (c) => c != null,
      orElse: () => null,
    );
    return category?.name ?? 'Uncategorized';
  }

  Future<List<String>> categoryNames() async {
    return _categories.map((c) => c.name).toList();
  }

  Product _withComputedStock(Product product) {
    final group = _variantGroupByProductId[product.id];
    if (group == null) {
      return Product(
        id: product.id,
        name: product.name,
        description: product.description,
        categoryId: product.categoryId,
        basePrice: product.basePrice,
        imagePath: product.imagePath,
        stockQuantity: _stockByAllocationKey[allocationKey(product.id, null)] ?? 0,
      );
    }

    final options = _variantOptionsByGroupId[group.id] ?? const [];
    final total = options.fold<int>(
      0,
      (sum, option) => sum + (_stockByAllocationKey[allocationKey(product.id, option.id)] ?? 0),
    );

    return Product(
      id: product.id,
      name: product.name,
      description: product.description,
      categoryId: product.categoryId,
      basePrice: product.basePrice,
      imagePath: product.imagePath,
      stockQuantity: total,
    );
  }

  void _replaceVariantsForProduct({
    required int productId,
    String? variantGroupName,
    List<ProductVariantOption> variantOptions = const [],
  }) {
    final oldGroup = _variantGroupByProductId.remove(productId);
    if (oldGroup != null) {
      final oldOptions = _variantOptionsByGroupId.remove(oldGroup.id) ?? const [];
      for (final option in oldOptions) {
        _stockByAllocationKey.remove(allocationKey(productId, option.id));
      }
    }

    if (variantGroupName == null || variantGroupName.trim().isEmpty || variantOptions.isEmpty) {
      return;
    }

    final group = ProductVariantGroup(
      id: _nextVariantGroupId++,
      productId: productId,
      name: variantGroupName.trim(),
    );
    _variantGroupByProductId[productId] = group;

    _variantOptionsByGroupId[group.id] = variantOptions
        .where((option) => option.value.trim().isNotEmpty)
        .map(
          (option) => ProductVariantOption(
            id: _nextVariantOptionId++,
            variantGroupId: group.id,
            value: option.value.trim(),
            extraPrice: option.extraPrice,
            stockQuantity: option.stockQuantity,
          ),
        )
        .toList();
  }

  void _ensureStockEntriesForProduct(int productId, {int initialStock = 0}) {
    final group = _variantGroupByProductId[productId];
    if (group == null) {
      _stockByAllocationKey[allocationKey(productId, null)] = initialStock;
      return;
    }

    _stockByAllocationKey.remove(allocationKey(productId, null));
    final options = _variantOptionsByGroupId[group.id] ?? const [];
    for (final option in options) {
      _stockByAllocationKey[allocationKey(productId, option.id)] =
          option.stockQuantity;
    }
  }
}

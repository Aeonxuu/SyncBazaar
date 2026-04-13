import 'dart:convert';

import 'package:flutter/services.dart';

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
  ProductRepository() {
    _seedFuture = _loadSeedProducts();
  }

  final List<Category> _categories = [];

  final List<Product> _products = [];
  final Map<int, ProductVariantGroup> _variantGroupByProductId = {};
  final Map<int, List<ProductVariantOption>> _variantOptionsByGroupId = {};
  final Map<String, int> _stockByAllocationKey = {};

  int _nextCategoryId = 100;
  int _nextProductId = 1000;
  int _nextVariantGroupId = 5000;
  int _nextVariantOptionId = 9000;
  Future<void>? _seedFuture;

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
    await _ensureSeeded();
    return _products.map(_withComputedStock).toList();
  }

  Future<List<Category>> listCategories() async {
    await _ensureSeeded();
    return List<Category>.from(_categories);
  }

  Future<Category> addCategory({
    required String name,
    String? description,
  }) async {
    await _ensureSeeded();
    final category = Category(
      id: _nextCategoryId++,
      name: name.trim(),
      description: description?.trim().isEmpty == true ? null : description?.trim(),
    );
    _categories.add(category);
    return category;
  }

  Future<void> deleteCategory(int categoryId) async {
    await _ensureSeeded();
    _categories.removeWhere((c) => c.id == categoryId);
    _products.removeWhere((p) => p.categoryId == categoryId);
  }

  Future<void> updateCategoryName({
    required int categoryId,
    required String name,
  }) async {
    await _ensureSeeded();
    final index = _categories.indexWhere((category) => category.id == categoryId);
    if (index == -1) {
      return;
    }
    final current = _categories[index];
    _categories[index] = Category(
      id: current.id,
      name: name.trim(),
      description: current.description,
    );
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
    await _ensureSeeded();
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
    await _ensureSeeded();
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
    await _ensureSeeded();
    return _variantGroupByProductId[productId];
  }

  Future<List<ProductVariantOption>> variantOptionsForProduct(int productId) async {
    await _ensureSeeded();
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
    await _ensureSeeded();
    return _stockByAllocationKey[allocationKey(productId, variantOptionId)] ?? 0;
  }

  Future<Map<int, int>> variantStocksByOptionId(int productId) async {
    await _ensureSeeded();
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
    await _ensureSeeded();
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
    await _ensureSeeded();
    return Map<String, int>.from(_stockByAllocationKey);
  }

  Future<Map<int, int>> stockByProductId() async {
    await _ensureSeeded();
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
    await _ensureSeeded();
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
    await _ensureSeeded();
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
    await _ensureSeeded();
    final key = allocationKey(productId, variantOptionId);
    final current = _stockByAllocationKey[key];
    if (current == null || quantity <= 0 || current < quantity) {
      return false;
    }
    _stockByAllocationKey[key] = current - quantity;
    return true;
  }

  Future<String> categoryNameForProduct(Product product) async {
    await _ensureSeeded();
    final category = _categories.where((c) => c.id == product.categoryId).cast<Category?>().firstWhere(
      (c) => c != null,
      orElse: () => null,
    );
    return category?.name ?? 'Uncategorized';
  }

  Future<List<String>> categoryNames() async {
    await _ensureSeeded();
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

  Future<void> _ensureSeeded() async {
    final seedFuture = _seedFuture;
    if (seedFuture == null) {
      return;
    }
    await seedFuture;
    _seedFuture = null;
  }

  Future<void> _loadSeedProducts() async {
    final raw = await rootBundle.loadString('assets/data/sample_products.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final items = (decoded['master_inventory'] as List<dynamic>? ?? const []);

    _categories.clear();
    _products.clear();
    _variantGroupByProductId.clear();
    _variantOptionsByGroupId.clear();
    _stockByAllocationKey.clear();

    final brandToCategoryId = <String, int>{};
    var nextSeedCategoryId = 1;

    int categoryIdForBrand(String brand) {
      final existing = brandToCategoryId[brand];
      if (existing != null) {
        return existing;
      }
      final createdId = nextSeedCategoryId++;
      brandToCategoryId[brand] = createdId;
      _categories.add(Category(id: createdId, name: brand));
      return createdId;
    }

    var maxProductId = 0;
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final productId = (item['id'] as num?)?.toInt() ?? 0;
      final name = (item['shoe_name'] as String?)?.trim() ?? '';
      if (productId <= 0 || name.isEmpty) {
        continue;
      }
      final brand = ((item['brand'] as String?)?.trim().isNotEmpty ?? false)
          ? (item['brand'] as String).trim()
          : 'Unbranded';
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      final variants = (item['variants'] as List<dynamic>? ?? const []);
      final categoryId = categoryIdForBrand(brand);
      final imagePath = _defaultImagePathForProduct(name);

      _products.add(
        Product(
          id: productId,
          name: name,
          description: brand,
          categoryId: categoryId,
          basePrice: price,
          imagePath: imagePath,
        ),
      );

      final group = ProductVariantGroup(
        id: _nextVariantGroupId++,
        productId: productId,
        name: 'Size',
      );
      _variantGroupByProductId[productId] = group;

      final options = <ProductVariantOption>[];
      for (final variant in variants) {
        if (variant is! Map<String, dynamic>) {
          continue;
        }
        final size = variant['size'];
        final stock = (variant['stock'] as num?)?.toInt() ?? 0;
        if (size == null) {
          continue;
        }
        final option = ProductVariantOption(
          id: _nextVariantOptionId++,
          variantGroupId: group.id,
          value: size.toString(),
          stockQuantity: stock,
        );
        options.add(option);
        _stockByAllocationKey[allocationKey(productId, option.id)] = stock;
      }
      _variantOptionsByGroupId[group.id] = options;
      maxProductId = productId > maxProductId ? productId : maxProductId;
    }

    _nextCategoryId = nextSeedCategoryId;
    _nextProductId = maxProductId + 1;
  }

  String? _defaultImagePathForProduct(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (slug.isEmpty) {
      return null;
    }
    return 'assets/images/default_shoes/$slug.png';
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

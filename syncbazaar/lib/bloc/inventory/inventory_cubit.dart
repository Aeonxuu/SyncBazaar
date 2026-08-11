import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';

/// One row of the master inventory table: a single sellable combination — a
/// SKU — rather than a product.
///
/// A product with 3 colours and 7 sizes contributes 21 rows, each carrying its
/// own [stock]. That's the level stock actually exists at in this app (the
/// repository keys quantities by option combination), and the level stock
/// questions get asked at: "how many Triple White 37s are left?" is not
/// answerable from a product-level total.
class InventoryRow {
  const InventoryRow({
    required this.product,
    required this.allocationKey,
    required this.stock,
    required this.status,
    this.optionOneValue,
    this.optionTwoValue,
  });

  final Product product;

  /// Identifies this combination in the repository. Selection, archiving and
  /// restoring all act on this — it's what makes a single SKU manageable
  /// without touching its siblings.
  final String allocationKey;

  /// Stock held by this combination alone.
  final int stock;

  /// This SKU's effective state: archived when the combination itself has
  /// been retired *or* its whole product has, otherwise the product's own
  /// state. One value so the table never has to reconcile two.
  final ProductStatus status;

  /// Value from the product's first variant group, e.g. "Triple White". Null
  /// when the product has no variants — it is then its own single SKU.
  final String? optionOneValue;

  /// Value from the second variant group, e.g. "37". Null when the product
  /// has fewer than two groups.
  final String? optionTwoValue;
}

class InventoryState {
  const InventoryState({
    this.rows = const [],
    this.products = const [],
    this.totalVolume = 0,
    this.inventoryValue = 0,
    this.inventoryTurnover = 0,
    this.isLoading = true,
  });

  /// One entry per SKU. Several rows can share a product.
  final List<InventoryRow> rows;

  /// The distinct products behind [rows]. Anything counting *products* must
  /// read this — counting rows would multiply every product by its variants.
  final List<Product> products;

  /// Total units currently on hand across every product.
  final int totalVolume;

  /// Retail value of the units on hand.
  final double inventoryValue;

  /// Units sold ÷ units on hand. A simple stand-in for the accounting ratio
  /// (cost of goods sold over *average* inventory) — this app tracks neither
  /// unit cost nor historical stock levels, so current stock stands in for
  /// average inventory.
  final double inventoryTurnover;

  final bool isLoading;
}

class InventoryCubit extends Cubit<InventoryState> {
  InventoryCubit(this._productRepository, this._salesRepository)
    : super(const InventoryState());

  final ProductRepository _productRepository;
  final SalesRepository _salesRepository;

  Future<void> load() async {
    final products = await _productRepository.listProducts();
    final archivedKeys = await _productRepository.archivedAllocationKeys();

    /// A combination is archived if it was retired on its own or if the whole
    /// product was; otherwise it inherits the product's state.
    ProductStatus statusFor(Product product, String key) {
      if (product.status == ProductStatus.archived ||
          archivedKeys.contains(key)) {
        return ProductStatus.archived;
      }
      return product.status;
    }

    final rows = <InventoryRow>[];
    for (final product in products) {
      final groups = await _productRepository.variantGroupsForProduct(
        product.id,
      );

      final optionsA = groups.isEmpty
          ? const <ProductVariantOption>[]
          : await _productRepository.variantOptionsForGroup(groups[0].id);
      final optionsB = groups.length > 1
          ? await _productRepository.variantOptionsForGroup(groups[1].id)
          : const <ProductVariantOption>[];

      // No variants — or a group that was never given any values, which would
      // otherwise drop the product out of the table entirely. Either way the
      // product is its own single SKU.
      if (optionsA.isEmpty) {
        final key = _productRepository.allocationKey(product.id);
        rows.add(
          InventoryRow(
            product: product,
            allocationKey: key,
            stock: product.stockQuantity,
            status: statusFor(product, key),
          ),
        );
        continue;
      }

      final stocks = await _productRepository.combinationStocksForProduct(
        product.id,
      );
      for (final optionA in optionsA) {
        if (optionsB.isEmpty) {
          final key = _productRepository.allocationKey(
            product.id,
            optionIdA: optionA.id,
          );
          rows.add(
            InventoryRow(
              product: product,
              allocationKey: key,
              optionOneValue: optionA.value,
              stock: stocks[(optionA.id, null)] ?? 0,
              status: statusFor(product, key),
            ),
          );
          continue;
        }
        for (final optionB in optionsB) {
          final key = _productRepository.allocationKey(
            product.id,
            optionIdA: optionA.id,
            optionIdB: optionB.id,
          );
          rows.add(
            InventoryRow(
              product: product,
              allocationKey: key,
              optionOneValue: optionA.value,
              optionTwoValue: optionB.value,
              stock: stocks[(optionA.id, optionB.id)] ?? 0,
              status: statusFor(product, key),
            ),
          );
        }
      }
    }

    final totalVolume = products.fold<int>(
      0,
      (sum, p) => sum + p.stockQuantity,
    );
    final inventoryValue = products.fold<double>(
      0,
      (sum, p) => sum + (p.stockQuantity * p.basePrice),
    );
    final unitsSold = (await _salesRepository.listSales()).fold<int>(
      0,
      (sum, sale) => sum + sale.qty,
    );

    emit(
      InventoryState(
        rows: rows,
        products: products,
        totalVolume: totalVolume,
        inventoryValue: inventoryValue,
        inventoryTurnover: totalVolume == 0 ? 0 : unitsSold / totalVolume,
        isLoading: false,
      ),
    );
  }

  Future<void> delete(int id) async {
    await _productRepository.deleteProduct(id);
    await load();
  }

  /// Bulk-deletes the products backing the table's checkbox selection.
  Future<void> deleteMany(Iterable<int> ids) async {
    for (final id in ids) {
      await _productRepository.deleteProduct(id);
    }
    await load();
  }

  /// Archives or restores individual combinations.
  ///
  /// Operates on allocation keys rather than product ids so a single
  /// out-of-stock size can be retired while the rest of the product keeps
  /// selling — which product-level status can't express.
  Future<void> setArchivedForKeys(
    Iterable<String> allocationKeys, {
    required bool archived,
  }) async {
    await _productRepository.setCombinationsArchived(
      allocationKeys: allocationKeys,
      archived: archived,
    );
    await load();
  }

  Future<List<ProductAllocationItem>> allocationItems() {
    return _productRepository.allocationItems();
  }

  Future<List<ProductVariantGroup>> variantGroupsForProduct(int productId) {
    return _productRepository.variantGroupsForProduct(productId);
  }

  Future<List<ProductVariantOption>> variantOptionsForGroup(int groupId) {
    return _productRepository.variantOptionsForGroup(groupId);
  }

  Future<Map<(int?, int?), int>> combinationStocksForProduct(int productId) {
    return _productRepository.combinationStocksForProduct(productId);
  }

  Future<void> saveProduct({
    int? id,
    required String name,
    String? description,
    required double basePrice,
    String? imagePath,
    Uint8List? imageBytes,
    List<VariantCategoryDraft> variantGroups = const [],
    Map<String, int> combinationStocks = const {},
    int stockQuantity = 0,
    ProductStatus status = ProductStatus.active,
  }) async {
    await _productRepository.saveProduct(
      id: id,
      name: name,
      description: description,
      basePrice: basePrice,
      imagePath: imagePath,
      imageBytes: imageBytes,
      variantGroups: variantGroups,
      combinationStocks: combinationStocks,
      stockQuantity: stockQuantity,
      status: status,
    );
    await load();
  }
}

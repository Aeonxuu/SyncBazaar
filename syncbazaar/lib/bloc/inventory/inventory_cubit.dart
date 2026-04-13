import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/product_repository.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';

class InventoryCubit extends Cubit<List<Product>> {
  InventoryCubit(this._productRepository) : super(const []);

  final ProductRepository _productRepository;

  Future<void> load() async => emit(await _productRepository.listProducts());

  Future<void> delete(int id) async {
    await _productRepository.deleteProduct(id);
    await load();
  }

  Future<List<Category>> categories() => _productRepository.listCategories();

  Future<Category> addCategory({
    required String name,
    String? description,
  }) async {
    final category = await _productRepository.addCategory(
      name: name,
      description: description,
    );
    await load();
    return category;
  }

  Future<void> deleteCategory(int categoryId) async {
    await _productRepository.deleteCategory(categoryId);
    await load();
  }

  Future<void> updateCategoryName({
    required int categoryId,
    required String name,
  }) async {
    await _productRepository.updateCategoryName(
      categoryId: categoryId,
      name: name,
    );
    await load();
  }

  Future<List<ProductAllocationItem>> allocationItems() {
    return _productRepository.allocationItems();
  }

  Future<ProductVariantGroup?> variantGroupForProduct(int productId) {
    return _productRepository.variantGroupForProduct(productId);
  }

  Future<List<ProductVariantOption>> variantOptionsForProduct(int productId) {
    return _productRepository.variantOptionsForProduct(productId);
  }

  Future<Map<int, int>> variantStocksByOptionId(int productId) {
    return _productRepository.variantStocksByOptionId(productId);
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
    await _productRepository.saveProduct(
      id: id,
      name: name,
      description: description,
      categoryId: categoryId,
      basePrice: basePrice,
      imagePath: imagePath,
      variantGroupName: variantGroupName,
      variantOptions: variantOptions,
      stockQuantity: stockQuantity,
    );
    await load();
  }
}

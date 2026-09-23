import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
import '../../data/repositories/product_repository.dart';
import '../../models/brand.dart';
import '../../models/category.dart';

class CatalogState {
  const CatalogState({
    this.categories = const [],
    this.brands = const [],
    this.productCountByCategoryId = const {},
    this.productCountByBrandId = const {},
    this.isRemote = false,
    this.loaded = false,
    this.categoryError,
    this.brandError,
  });

  final List<Category> categories;
  final List<Brand> brands;

  /// How many of the vendor's products currently carry each category/brand
  /// — the consequence a delete would have, shown on the row itself rather
  /// than left for the confirmation dialog to explain from scratch.
  final Map<int, int> productCountByCategoryId;
  final Map<int, int> productCountByBrandId;

  /// Whether there is a server for this list to live on. False only in the
  /// demo build — a real vendor with nothing added yet is still [isRemote].
  final bool isRemote;

  /// Whether the first load has completed, so the screen can tell "loading"
  /// from "loaded, and genuinely empty."
  final bool loaded;

  /// The last action's failure for each list, shown inline next to that
  /// list's own add field rather than in a SnackBar, and cleared on that
  /// list's next attempt.
  final String? categoryError;
  final String? brandError;

  CatalogState copyWith({
    List<Category>? categories,
    List<Brand>? brands,
    Map<int, int>? productCountByCategoryId,
    Map<int, int>? productCountByBrandId,
    bool? isRemote,
    bool? loaded,
    String? categoryError,
    bool clearCategoryError = false,
    String? brandError,
    bool clearBrandError = false,
  }) {
    return CatalogState(
      categories: categories ?? this.categories,
      brands: brands ?? this.brands,
      productCountByCategoryId:
          productCountByCategoryId ?? this.productCountByCategoryId,
      productCountByBrandId:
          productCountByBrandId ?? this.productCountByBrandId,
      isRemote: isRemote ?? this.isRemote,
      loaded: loaded ?? this.loaded,
      categoryError: clearCategoryError
          ? null
          : (categoryError ?? this.categoryError),
      brandError: clearBrandError ? null : (brandError ?? this.brandError),
    );
  }
}

/// Drives the Catalog settings screen: the vendor's own product categories
/// and brands.
///
/// Kept out of the product form on purpose — see the note there. This is
/// their one home: add, rename, delete, all in one place a vendor visits to
/// set up their taxonomy rather than mid-way through adding a product.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._repository) : super(const CatalogState());

  final ProductRepository _repository;

  Future<void> load() async {
    final categories = await _repository.listCategories();
    final brands = await _repository.listBrands();
    final products = await _repository.listProducts();

    final categoryCounts = <int, int>{};
    final brandCounts = <int, int>{};
    for (final product in products) {
      final categoryId = product.categoryId;
      if (categoryId != null) {
        categoryCounts[categoryId] = (categoryCounts[categoryId] ?? 0) + 1;
      }
      final brandId = product.brandId;
      if (brandId != null) {
        brandCounts[brandId] = (brandCounts[brandId] ?? 0) + 1;
      }
    }

    emit(
      state.copyWith(
        categories: categories,
        brands: brands,
        productCountByCategoryId: categoryCounts,
        productCountByBrandId: brandCounts,
        isRemote: _repository.isRemote,
        loaded: true,
        clearCategoryError: true,
        clearBrandError: true,
      ),
    );
  }

  Future<void> addCategory(String name) async {
    try {
      await _repository.createCategory(name);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          categoryError: error.isOffline
              ? 'Cannot reach the server, so $name was not added.'
              : '$name could not be added. ${error.message}',
        ),
      );
    }
  }

  Future<void> renameCategory(Category category, String name) async {
    try {
      await _repository.renameCategory(id: category.id, name: name);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          categoryError: error.isOffline
              ? 'Cannot reach the server, so ${category.name} was not renamed.'
              : '${category.name} could not be renamed. ${error.message}',
        ),
      );
    }
  }

  Future<void> removeCategory(Category category) async {
    try {
      await _repository.deleteCategory(category.id);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          categoryError: error.isOffline
              ? 'Cannot reach the server, so ${category.name} was not removed.'
              : '${category.name} could not be removed. ${error.message}',
        ),
      );
    }
  }

  Future<void> addBrand(String name) async {
    try {
      await _repository.createBrand(name);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          brandError: error.isOffline
              ? 'Cannot reach the server, so $name was not added.'
              : '$name could not be added. ${error.message}',
        ),
      );
    }
  }

  Future<void> renameBrand(Brand brand, String name) async {
    try {
      await _repository.renameBrand(id: brand.id, name: name);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          brandError: error.isOffline
              ? 'Cannot reach the server, so ${brand.name} was not renamed.'
              : '${brand.name} could not be renamed. ${error.message}',
        ),
      );
    }
  }

  Future<void> removeBrand(Brand brand) async {
    try {
      await _repository.deleteBrand(brand.id);
      await load();
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          brandError: error.isOffline
              ? 'Cannot reach the server, so ${brand.name} was not removed.'
              : '${brand.name} could not be removed. ${error.message}',
        ),
      );
    }
  }
}

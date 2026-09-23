import 'dart:typed_data';

import '../../models/brand.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../remote/api_client.dart';
import '../remote/product_api_mapper.dart';
import 'auth_repository.dart';

/// One value a product's variant category can hold, e.g. "Ivory White" for a
/// "Color" category, paired with its stock for the parent product's other
/// selected values.
class VariantCategoryDraft {
  const VariantCategoryDraft({
    required this.name,
    required this.optionValues,
    this.extraPriceByValue = const {},
  });

  final String name;
  final List<String> optionValues;
  final Map<String, double> extraPriceByValue;
}

/// What came of a product-wide price change.
///
/// [updated] of [total] variants took the new price. When [failure] is set the
/// run stopped there, and the variants after it still hold the old price; the
/// caller has already refreshed, so the table shows the real mix.
class PriceUpdateOutcome {
  const PriceUpdateOutcome({
    required this.updated,
    required this.total,
    this.failure,
  });

  final int updated;
  final int total;
  final ApiException? failure;

  bool get isComplete => failure == null && updated == total;
}

/// A single sellable row surfaced for stock allocation (pre-bazaar) and
/// bazaar editing (POS) screens. When a product has two variant categories
/// this represents one cell of the Category A x Category B combination
/// matrix; with one category it's one option; with none, the product itself.
class ProductAllocationItem {
  const ProductAllocationItem({
    required this.allocationKey,
    required this.product,
    required this.availableQuantity,
    this.groupA,
    this.optionA,
    this.groupB,
    this.optionB,
  });

  final String allocationKey;
  final Product product;
  final int availableQuantity;
  final ProductVariantGroup? groupA;
  final ProductVariantOption? optionA;
  final ProductVariantGroup? groupB;
  final ProductVariantOption? optionB;

  String get displayLabel {
    final parts = <String>[];
    if (groupA != null && optionA != null) {
      parts.add('${groupA!.name}: ${optionA!.value}');
    }
    if (groupB != null && optionB != null) {
      parts.add('${groupB!.name}: ${optionB!.value}');
    }
    if (parts.isEmpty) {
      return product.name;
    }
    return '${product.name} - ${parts.join(', ')}';
  }

  /// Just what separates this row from its siblings — "Color: Black, Size: 42"
  /// — without the product name.
  ///
  /// Used where the product is already named above the row. Repeating it on
  /// every line spends most of the width on the one word that does not change.
  String get variantLabel {
    final parts = <String>[];
    if (groupA != null && optionA != null) {
      parts.add('${groupA!.name}: ${optionA!.value}');
    }
    if (groupB != null && optionB != null) {
      parts.add('${groupB!.name}: ${optionB!.value}');
    }
    return parts.isEmpty ? 'Standard' : parts.join(', ');
  }
}

class ProductRepository {
  /// Backed by the vendor's catalogue when [auth] is supplied, and by whatever
  /// `saveProduct` is given otherwise.
  ///
  /// One class rather than two implementations because only the *source* of the
  /// data changes: every method below reads the same in-memory maps either way,
  /// so no screen can tell the difference. Writes are still local-only —
  /// `saveProduct` and `deleteProduct` do not POST yet.
  ///
  /// Takes the repository rather than an [ApiClient] and a vendor id because
  /// neither exists yet when this is constructed: `app.dart` builds every
  /// repository in `initState`, and the token and vendor only arrive at login.
  /// Reading them from the session at first use is what lets one long-lived
  /// instance serve both states.
  ProductRepository({AuthRepository? auth}) : _auth = auth {
    _seedFuture = _loadSeedProducts();
  }

  final AuthRepository? _auth;

  /// Which vendor the loaded catalogue belongs to, so signing in as a different
  /// one refetches instead of showing the previous vendor's stock.
  int? _loadedVendorId;

  /// The in-flight catalogue fetch, shared by concurrent callers.
  ///
  /// Not an optimisation: `InventoryCubit.load()` calls into this repository
  /// around fifty times per screen load, and without a shared future that is
  /// fifty identical HTTP requests.
  Future<void>? _apiLoad;

  /// Allocation key to the server's `ProductVariant` id, empty until loaded
  /// from the API. Uploading a sale needs it: the server names what was sold by
  /// variant, never by the client's composite key.
  final Map<String, int> _variantIdByAllocationKey = {};

  /// The same mapping read the other way.
  ///
  /// Needed because traffic runs in both directions: a sale upload turns a
  /// combination into a variant id, while an event's stock allocation arrives
  /// from the server as variant ids that have to become combinations again.
  final Map<int, String> _allocationKeyByVariantId = {};

  /// Each variant's own price, from the API. `Product.lowestPrice` is the lowest
  /// of these; this keeps the rest so a product-wide price change can tell
  /// whether it is about to erase a real difference.
  final Map<String, double> _priceByAllocationKey = {};

  int? variantIdFor(String allocationKey) =>
      _variantIdByAllocationKey[allocationKey];

  /// Master stock held by one combination, or null if it is not known.
  int? stockFor(String allocationKey) => _stockByAllocationKey[allocationKey];

  /// Whether [allocationKey] can be edited in place on the server.
  ///
  /// False in the demo build, which has no server, and for anything the server
  /// has not issued a variant id for. The quick-edit control is hidden rather
  /// than disabled on false: online-only means the affordance should not exist
  /// where it cannot work.
  /// Whether this catalogue is the server's, so writes have somewhere to go.
  ///
  /// The one question the inventory screen asks before offering an edit that
  /// is not wired to the server yet. False in the demo build.
  bool get isRemote => _auth?.vendorId != null;

  bool canQuickEdit(String allocationKey) =>
      _auth?.vendorId != null &&
      _variantIdByAllocationKey[allocationKey] != null;

  /// Every variant price of one product, keyed by allocation key.
  ///
  /// Empty in the demo build. What the quick-edit dialog reads to decide
  /// whether a product-wide price change needs a warning first.
  Map<String, double> variantPricesForProduct(int productId) => {
    for (final entry in _priceByAllocationKey.entries)
      if (productIdFromKey(entry.key) == productId) entry.key: entry.value,
  };

  String? allocationKeyForVariant(int variantId) =>
      _allocationKeyByVariantId[variantId];

  /// Whether the catalogue has been fetched, so callers that depend on the
  /// variant mapping can make sure it is there first.
  Future<void> ensureLoaded() => _ensureSeeded();

  final List<Product> _products = [];

  /// The vendor's own categories and brands, refetched alongside the
  /// catalogue. Empty in the mock-seeded build — there is no local
  /// equivalent, so the picker built from [listCategories]/[listBrands]
  /// simply has nothing to offer there.
  final List<Category> _categories = [];
  final List<Brand> _brands = [];

  /// Up to 2 variant categories per product, in the order they were created.
  final Map<int, List<ProductVariantGroup>> _variantGroupsByProductId = {};
  final Map<int, List<ProductVariantOption>> _variantOptionsByGroupId = {};

  /// Stock is always tracked per combination key, even for a product with a
  /// single category or none at all (see [allocationKey]).
  final Map<String, int> _stockByAllocationKey = {};

  int _nextProductId = 1000;
  int _nextVariantGroupId = 5000;
  int _nextVariantOptionId = 9000;
  Future<void>? _seedFuture;

  static const int _maxVariantCategories = 2;

  /// Reserved attribute/value names used only to give a flat (no variant
  /// categories) product's single server-side variant an attribute value,
  /// since the server requires at least one. Never surfaced to a vendor —
  /// see the comment in [_saveProductRemote].
  static const String _flatAttributeName = 'SyncBazaar Internal';
  static const String _flatValueName = 'Single Variant';

  /// Combinations retired on their own, independent of their product's
  /// lifecycle state.
  ///
  /// Stock is held per combination, so "we're out of Triple White 37 and
  /// aren't restocking it" is a fact about one SKU, not about the shoe.
  /// Keeping this separate from [Product.status] lets a product stay active
  /// while individual combinations retire out of it.
  final Set<String> _archivedAllocationKeys = <String>{};

  Future<Set<String>> archivedAllocationKeys() async {
    await _ensureSeeded();
    return Set<String>.unmodifiable(_archivedAllocationKeys);
  }

  Future<void> setCombinationsArchived({
    required Iterable<String> allocationKeys,
    required bool archived,
  }) async {
    await _ensureSeeded();
    if (archived) {
      _archivedAllocationKeys.addAll(allocationKeys);
    } else {
      _archivedAllocationKeys.removeAll(allocationKeys.toList());
    }
  }

  String allocationKey(int productId, {int? optionIdA, int? optionIdB}) {
    return '$productId:${optionIdA ?? 0}:${optionIdB ?? 0}';
  }

  int productIdFromKey(String key) {
    final parts = key.split(':');
    return int.tryParse(parts.first) ?? 0;
  }

  Future<List<Product>> listProducts() async {
    await _ensureSeeded();
    return _products.map(_withComputedStock).toList();
  }

  /// The vendor's own categories, for the product form's picker. Empty
  /// without a session.
  Future<List<Category>> listCategories() async {
    await _ensureSeeded();
    return List<Category>.from(_categories);
  }

  /// The vendor's own brands, for the product form's picker. Empty without
  /// a session.
  Future<List<Brand>> listBrands() async {
    await _ensureSeeded();
    return List<Brand>.from(_brands);
  }

  /// Adds a category to the vendor's own list and returns it.
  Future<Category> createCategory(String name) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot create a category without a session.');
    }
    final created =
        await auth.api.post(
              '/api/core/vendor/$vendorId/category/',
              body: {'name': name.trim()},
            )
            as Map<String, dynamic>;
    final category = Category(
      id: (created['id'] as num).toInt(),
      name: created['name'] as String? ?? name.trim(),
    );
    _categories.add(category);
    return category;
  }

  /// Adds a brand to the vendor's own list and returns it.
  Future<Brand> createBrand(String name) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot create a brand without a session.');
    }
    final created =
        await auth.api.post(
              '/api/core/vendor/$vendorId/brand/',
              body: {'name': name.trim()},
            )
            as Map<String, dynamic>;
    final brand = Brand(
      id: (created['id'] as num).toInt(),
      name: created['name'] as String? ?? name.trim(),
    );
    _brands.add(brand);
    return brand;
  }

  /// Renames a category in place and returns the updated row.
  Future<Category> renameCategory({required int id, required String name}) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot rename a category without a session.');
    }
    final updated =
        await auth.api.patch(
              '/api/core/vendor/$vendorId/category/$id/',
              body: {'name': name.trim()},
            )
            as Map<String, dynamic>;
    final category = Category(
      id: id,
      name: updated['name'] as String? ?? name.trim(),
    );
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx == -1) {
      _categories.add(category);
    } else {
      _categories[idx] = category;
    }
    return category;
  }

  /// Renames a brand in place and returns the updated row.
  Future<Brand> renameBrand({required int id, required String name}) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot rename a brand without a session.');
    }
    final updated =
        await auth.api.patch(
              '/api/core/vendor/$vendorId/brand/$id/',
              body: {'name': name.trim()},
            )
            as Map<String, dynamic>;
    final brand = Brand(id: id, name: updated['name'] as String? ?? name.trim());
    final idx = _brands.indexWhere((b) => b.id == id);
    if (idx == -1) {
      _brands.add(brand);
    } else {
      _brands[idx] = brand;
    }
    return brand;
  }

  /// Removes a category. The server drops any product's reference to it
  /// rather than refusing (`on_delete=SET_NULL`), so this never fails
  /// because something is using it — those products simply end up
  /// uncategorised.
  Future<void> deleteCategory(int id) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot delete a category without a session.');
    }
    await auth.api.delete('/api/core/vendor/$vendorId/category/$id/');
    _categories.removeWhere((c) => c.id == id);
  }

  /// Removes a brand. Same `SET_NULL` behaviour as [deleteCategory].
  Future<void> deleteBrand(int id) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot delete a brand without a session.');
    }
    await auth.api.delete('/api/core/vendor/$vendorId/brand/$id/');
    _brands.removeWhere((b) => b.id == id);
  }

  /// Saves a product. [variantGroups] holds 0-2 variant categories (e.g.
  /// Color, Size). [combinationStocks] supplies the stock for each
  /// sellable combination, keyed by [combinationValueKey]. When
  /// [variantGroups] is empty, [stockQuantity] is used as the flat stock.
  ///
  /// Writes to the server when this catalogue is the vendor's
  /// ([isRemote]), and stays local-only otherwise. The two paths share a
  /// signature but not an implementation: the server splits a product into
  /// a product row plus one `ProductVariant` row per combination, created or
  /// updated separately, so [_saveProductRemote] handles that orchestration
  /// on its own rather than reusing [_replaceVariantsForProduct].
  Future<Product> saveProduct({
    int? id,
    required String name,
    String? description,
    required double lowestPrice,
    String? imagePath,
    Uint8List? imageBytes,
    List<VariantCategoryDraft> variantGroups = const [],
    Map<String, int> combinationStocks = const {},
    int stockQuantity = 0,
    ProductStatus status = ProductStatus.active,
    int? categoryId,
    String? categoryName,
    int? brandId,
    String? brandName,
  }) async {
    await _ensureSeeded();
    if (isRemote) {
      return _saveProductRemote(
        id: id,
        name: name,
        description: description,
        lowestPrice: lowestPrice,
        imagePath: imagePath,
        imageBytes: imageBytes,
        variantGroups: variantGroups,
        combinationStocks: combinationStocks,
        stockQuantity: stockQuantity,
        status: status,
        categoryId: categoryId,
        brandId: brandId,
      );
    }
    final normalizedName = name.trim();
    final normalizedDescription = description?.trim().isEmpty == true
        ? null
        : description?.trim();
    final productId = id ?? _nextProductId++;
    final existingIdx = _products.indexWhere((p) => p.id == productId);

    final next = Product(
      id: productId,
      name: normalizedName,
      description: normalizedDescription,
      lowestPrice: lowestPrice,
      imagePath: imagePath,
      imageBytes: imageBytes,
      status: status,
      categoryId: categoryId,
      categoryName: categoryName,
      brandId: brandId,
      brandName: brandName,
    );

    if (existingIdx == -1) {
      _products.add(next);
    } else {
      _products[existingIdx] = next;
    }

    _replaceVariantsForProduct(
      productId: productId,
      variantGroups: variantGroups.take(_maxVariantCategories).toList(),
      combinationStocks: combinationStocks,
    );

    if (variantGroups.isEmpty) {
      _stockByAllocationKey[allocationKey(productId)] = stockQuantity;
    }

    return next;
  }

  /// The server-backed half of [saveProduct].
  ///
  /// `description` and `status` have no server column at all — the
  /// backend's `Product` model has no such fields — so both are kept locally,
  /// the same way [imageBytes] already is for the local path. A save touches
  /// only its own product; every other product's locally-held fields are
  /// snapshotted first and reapplied after [refresh], since a plain refetch
  /// would otherwise reset them all to their defaults.
  Future<Product> _saveProductRemote({
    required int? id,
    required String name,
    required String? description,
    required double lowestPrice,
    required String? imagePath,
    required Uint8List? imageBytes,
    required List<VariantCategoryDraft> variantGroups,
    required Map<String, int> combinationStocks,
    required int stockQuantity,
    required ProductStatus status,
    int? categoryId,
    int? brandId,
  }) async {
    final api = _auth!.api;
    final vendorId = _auth.vendorId!;
    final normalizedName = name.trim();
    final normalizedDescription = description?.trim().isEmpty == true
        ? null
        : description?.trim();
    final groups = variantGroups.take(_maxVariantCategories).toList();

    // groupIndex -> trimmed option text -> its resolved server value.
    final resolvedByGroup = <int, Map<String, ({int id, double extraPrice})>>{};
    final attributeIds = <int>[];

    var attributes =
        (await api.get('/api/core/attribute/') as List)
            .cast<Map<String, dynamic>>();

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final groupName = group.name.trim();
      var attribute = _findByField(attributes, 'name', groupName);
      if (attribute == null) {
        attribute =
            await api.post('/api/core/attribute/', body: {'name': groupName})
                as Map<String, dynamic>;
        attribute = {...attribute, 'values': const []};
        attributes = [...attributes, attribute];
      }
      final attributeId = (attribute['id'] as num).toInt();
      attributeIds.add(attributeId);

      var values = (attribute['values'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final resolved = <String, ({int id, double extraPrice})>{};
      final seen = <String>{};
      for (final rawValue in group.optionValues) {
        final value = rawValue.trim();
        if (value.isEmpty || !seen.add(value.toUpperCase())) {
          continue;
        }
        var match = _findByField(values, 'value', value);
        if (match == null) {
          match =
              await api.post(
                    '/api/core/attribute/$attributeId/value/',
                    body: {'value': value},
                  )
                  as Map<String, dynamic>;
          values = [...values, match];
        }
        resolved[value] = (
          id: (match['id'] as num).toInt(),
          extraPrice: group.extraPriceByValue[rawValue] ?? 0,
        );
      }
      resolvedByGroup[i] = resolved;
    }

    // The server requires every variant to carry at least one attribute
    // value — there is no such thing as a bare `ProductVariant` there. A
    // flat product (no variant categories chosen in the form) still needs
    // exactly one variant to be its single sellable row, so it gets one
    // resolved value from a reserved attribute that is never added to the
    // product's own `attributes` list. That is what keeps it invisible: the
    // mapper only turns a value into a variant category when its attribute
    // is in `product.attributes`, so this one is read back as having none.
    int? flatValueId;
    if (groups.isEmpty) {
      var flatAttribute = _findByField(attributes, 'name', _flatAttributeName);
      if (flatAttribute == null) {
        flatAttribute =
            await api.post(
                  '/api/core/attribute/',
                  body: {'name': _flatAttributeName},
                )
                as Map<String, dynamic>;
        flatAttribute = {...flatAttribute, 'values': const []};
      }
      final flatAttributeId = (flatAttribute['id'] as num).toInt();
      final flatValues = (flatAttribute['values'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      var flatValue = _findByField(flatValues, 'value', _flatValueName);
      flatValue ??=
          await api.post(
                '/api/core/attribute/$flatAttributeId/value/',
                body: {'value': _flatValueName},
              )
              as Map<String, dynamic>;
      flatValueId = (flatValue['id'] as num).toInt();
    }

    final productBody = {
      'name': normalizedName,
      'attributes': attributeIds,
      'category': categoryId,
      'brand': brandId,
    };
    int productId;
    if (id == null) {
      final created =
          await api.post(
                '/api/core/vendor/$vendorId/product/',
                body: productBody,
              )
              as Map<String, dynamic>;
      productId = (created['id'] as num).toInt();
    } else {
      productId = id;
      await api.patch(
        '/api/core/vendor/$vendorId/product/$productId/',
        body: productBody,
      );
    }

    // Desired variant rows, keyed the same way the loaded catalogue is, so
    // they line up against `_variantIdByAllocationKey` below.
    final desired = <String, Map<String, dynamic>>{};
    if (groups.isEmpty) {
      desired[allocationKey(productId)] = {
        'attribute_values': [flatValueId!],
        'price': lowestPrice.toStringAsFixed(2),
        'stock_quantity': stockQuantity,
      };
    } else if (groups.length == 1) {
      for (final entry in resolvedByGroup[0]!.entries) {
        final key = allocationKey(productId, optionIdA: entry.value.id);
        desired[key] = {
          'attribute_values': [entry.value.id],
          'price': (lowestPrice + entry.value.extraPrice).toStringAsFixed(2),
          'stock_quantity':
              combinationStocks[combinationValueKey(entry.key)] ?? 0,
        };
      }
    } else {
      for (final entryA in resolvedByGroup[0]!.entries) {
        for (final entryB in resolvedByGroup[1]!.entries) {
          final key = allocationKey(
            productId,
            optionIdA: entryA.value.id,
            optionIdB: entryB.value.id,
          );
          desired[key] = {
            'attribute_values': [entryA.value.id, entryB.value.id],
            'price': (lowestPrice + entryA.value.extraPrice + entryB.value.extraPrice)
                .toStringAsFixed(2),
            'stock_quantity':
                combinationStocks[combinationValueKey(
                  entryA.key,
                  entryB.key,
                )] ??
                0,
          };
        }
      }
    }

    final previousKeys = id == null
        ? const <String>{}
        : _stockByAllocationKey.keys
              .where((key) => productIdFromKey(key) == productId)
              .toSet();

    // Any variant will do to carry the product's photo — the mapper reads
    // whichever one has an image, not a particular one — so the first
    // written this call is as good as any.
    int? primaryVariantId;
    for (final entry in desired.entries) {
      final body = {
        ...entry.value,
        if (imagePath != null) 'image_link': imagePath,
      };
      final existingVariantId = _variantIdByAllocationKey[entry.key];
      int variantId;
      if (existingVariantId != null) {
        await api.patch(
          '/api/core/vendor/$vendorId/product/$productId/variant/$existingVariantId/',
          body: body,
        );
        variantId = existingVariantId;
      } else {
        final created =
            await api.post(
                  '/api/core/vendor/$vendorId/product/$productId/variant/',
                  body: {'product': productId, ...body},
                )
                as Map<String, dynamic>;
        variantId = (created['id'] as num).toInt();
      }
      primaryVariantId ??= variantId;
    }

    // The picked photo itself: a separate multipart call, since the JSON
    // body above only carries a link for bundled/remote assets.
    if (imageBytes != null && primaryVariantId != null) {
      await api.uploadFile(
        '/api/core/vendor/$vendorId/product/$productId/variant/$primaryVariantId/image/',
        bytes: imageBytes,
        field: 'image',
        filename:
            '${normalizedName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.png',
      );
    }

    for (final key in previousKeys) {
      if (desired.containsKey(key)) {
        continue;
      }
      final variantId = _variantIdByAllocationKey[key];
      if (variantId != null) {
        await api.delete(
          '/api/core/vendor/$vendorId/product/$productId/variant/$variantId/',
        );
      }
    }

    final localOnly = <int, ({ProductStatus status, String? description, Uint8List? imageBytes})>{
      for (final product in _products)
        product.id: (
          status: product.status,
          description: product.description,
          imageBytes: product.imageBytes,
        ),
    };

    await refresh();

    final merged = _products.map((product) {
      final isSaved = product.id == productId;
      final local = localOnly[product.id];
      return Product(
        id: product.id,
        name: product.name,
        description: isSaved ? normalizedDescription : local?.description,
        lowestPrice: product.lowestPrice,
        stockQuantity: product.stockQuantity,
        imagePath: product.imagePath,
        imageBytes: isSaved ? imageBytes : local?.imageBytes,
        status: isSaved ? status : (local?.status ?? ProductStatus.active),
        categoryId: product.categoryId,
        categoryName: product.categoryName,
        brandId: product.brandId,
        brandName: product.brandName,
      );
    }).toList();
    _products
      ..clear()
      ..addAll(merged);

    return _products.firstWhere((product) => product.id == productId);
  }

  /// Case-insensitive lookup of the first row whose [field] matches [value].
  static Map<String, dynamic>? _findByField(
    List<Map<String, dynamic>> rows,
    String field,
    String value,
  ) {
    final needle = value.toLowerCase();
    for (final row in rows) {
      if ((row[field] as String? ?? '').trim().toLowerCase() == needle) {
        return row;
      }
    }
    return null;
  }

  /// Changes only a product's lifecycle status.
  ///
  /// Deliberately not routed through [saveProduct]: that call rebuilds the
  /// product's variant groups and stock from its arguments, so using it to
  /// flip a status would silently wipe the variants and per-combination
  /// stock of every product being archived.
  Future<void> updateProductStatus({
    required int id,
    required ProductStatus status,
  }) async {
    await _ensureSeeded();
    final idx = _products.indexWhere((p) => p.id == id);
    if (idx == -1) {
      return;
    }
    final current = _products[idx];
    _products[idx] = Product(
      id: current.id,
      name: current.name,
      description: current.description,
      lowestPrice: current.lowestPrice,
      imagePath: current.imagePath,
      imageBytes: current.imageBytes,
      stockQuantity: current.stockQuantity,
      status: status,
      categoryId: current.categoryId,
      categoryName: current.categoryName,
      brandId: current.brandId,
      brandName: current.brandName,
    );
  }

  /// Removes a product, on the server first when there is one.
  ///
  /// The local copy goes only after the server has answered 204. A product
  /// that vanished from the table but still exists on the server would come
  /// straight back on the next refresh, which reads as the delete "not
  /// working" when it never happened at all.
  ///
  /// The server refuses with a 409 when any variant has recorded sales, and
  /// that [ApiException] is left to the caller, whose job is to name the
  /// product and say why. What the server does *not* refuse is a product
  /// allocated to a bazaar that has not sold yet: those allocations are
  /// cascaded away silently. Warning about that is the caller's job too, and
  /// [EventRepository.eventsAllocating] is how it finds out.
  Future<void> deleteProduct(int id) async {
    await _ensureSeeded();
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth != null && vendorId != null) {
      await auth.api.delete('/api/core/vendor/$vendorId/product/$id/');
    }
    _products.removeWhere((p) => p.id == id);
    final groups = _variantGroupsByProductId.remove(id) ?? const [];
    for (final group in groups) {
      _variantOptionsByGroupId.remove(group.id);
    }
    _stockByAllocationKey.removeWhere((key, _) => productIdFromKey(key) == id);
    _archivedAllocationKeys.removeWhere((key) => productIdFromKey(key) == id);
  }

  Future<List<ProductVariantGroup>> variantGroupsForProduct(
    int productId,
  ) async {
    await _ensureSeeded();
    return List<ProductVariantGroup>.from(
      _variantGroupsByProductId[productId] ?? const [],
    );
  }

  Future<List<ProductVariantOption>> variantOptionsForGroup(int groupId) async {
    await _ensureSeeded();
    return List<ProductVariantOption>.from(
      _variantOptionsByGroupId[groupId] ?? const [],
    );
  }

  /// All variant options across every category of a product, e.g. for
  /// building an id-to-label lookup for reporting.
  Future<List<ProductVariantOption>> allVariantOptionsForProduct(
    int productId,
  ) async {
    await _ensureSeeded();
    final groups = _variantGroupsByProductId[productId] ?? const [];
    final result = <ProductVariantOption>[];
    for (final group in groups) {
      result.addAll(_variantOptionsByGroupId[group.id] ?? const []);
    }
    return result;
  }

  Future<int> combinationStock({
    required int productId,
    int? optionIdA,
    int? optionIdB,
  }) async {
    await _ensureSeeded();
    return _stockByAllocationKey[allocationKey(
          productId,
          optionIdA: optionIdA,
          optionIdB: optionIdB,
        )] ??
        0;
  }

  /// Stock for every sellable combination of a product, keyed by
  /// (optionIdA, optionIdB) — either may be null depending on how many
  /// categories the product has.
  Future<Map<(int?, int?), int>> combinationStocksForProduct(
    int productId,
  ) async {
    await _ensureSeeded();
    final groups = _variantGroupsByProductId[productId] ?? const [];
    final result = <(int?, int?), int>{};

    if (groups.isEmpty) {
      result[(null, null)] =
          _stockByAllocationKey[allocationKey(productId)] ?? 0;
      return result;
    }

    final optionsA = _variantOptionsByGroupId[groups[0].id] ?? const [];
    if (groups.length == 1) {
      for (final optionA in optionsA) {
        result[(optionA.id, null)] =
            _stockByAllocationKey[allocationKey(
              productId,
              optionIdA: optionA.id,
            )] ??
            0;
      }
      return result;
    }

    final optionsB = _variantOptionsByGroupId[groups[1].id] ?? const [];
    for (final optionA in optionsA) {
      for (final optionB in optionsB) {
        result[(optionA.id, optionB.id)] =
            _stockByAllocationKey[allocationKey(
              productId,
              optionIdA: optionA.id,
              optionIdB: optionB.id,
            )] ??
            0;
      }
    }
    return result;
  }

  /// Stock that may be allocated to a bazaar.
  ///
  /// Two rules, both enforced only here — every allocation surface reads from
  /// this method:
  ///
  /// 1. The product must be [ProductStatus.active]. Archiving is precisely the
  ///    act of taking something out of circulation, and a draft is a product
  ///    still being set up; neither is ready to sell.
  /// 2. The individual combination must not be archived. A product can be
  ///    perfectly active while one of its sizes has been retired.
  ///
  /// Existing allocations are left alone — those were already committed to a
  /// bazaar.
  Future<List<ProductAllocationItem>> allocationItems() async {
    await _ensureSeeded();
    final items = <ProductAllocationItem>[];
    final products = (await listProducts())
        .where((product) => product.status == ProductStatus.active)
        .toList();
    for (final product in products) {
      final groups = _variantGroupsByProductId[product.id] ?? const [];
      if (groups.isEmpty) {
        final key = allocationKey(product.id);
        items.add(
          ProductAllocationItem(
            allocationKey: key,
            product: product,
            availableQuantity: _stockByAllocationKey[key] ?? 0,
          ),
        );
        continue;
      }

      final optionsA = _variantOptionsByGroupId[groups[0].id] ?? const [];
      if (groups.length == 1) {
        for (final optionA in optionsA) {
          final key = allocationKey(product.id, optionIdA: optionA.id);
          items.add(
            ProductAllocationItem(
              allocationKey: key,
              product: product,
              availableQuantity: _stockByAllocationKey[key] ?? 0,
              groupA: groups[0],
              optionA: optionA,
            ),
          );
        }
        continue;
      }

      final optionsB = _variantOptionsByGroupId[groups[1].id] ?? const [];
      for (final optionA in optionsA) {
        for (final optionB in optionsB) {
          final key = allocationKey(
            product.id,
            optionIdA: optionA.id,
            optionIdB: optionB.id,
          );
          items.add(
            ProductAllocationItem(
              allocationKey: key,
              product: product,
              availableQuantity: _stockByAllocationKey[key] ?? 0,
              groupA: groups[0],
              optionA: optionA,
              groupB: groups[1],
              optionB: optionB,
            ),
          );
        }
      }
    }
    return items
        .where((item) => !_archivedAllocationKeys.contains(item.allocationKey))
        .toList();
  }

  Future<Map<String, int>> stockByAllocationKey() async {
    await _ensureSeeded();
    return Map<String, int>.from(_stockByAllocationKey);
  }

  Future<bool> reserveStocksByAllocationKey(
    Map<String, int> allocations,
  ) async {
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

  Future<bool> adjustStocksByAllocationKey(
    Map<String, int> deltasByAllocationKey,
  ) async {
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
    int? optionIdA,
    int? optionIdB,
    required int quantity,
  }) async {
    await _ensureSeeded();
    final key = allocationKey(
      productId,
      optionIdA: optionIdA,
      optionIdB: optionIdB,
    );
    final current = _stockByAllocationKey[key];
    if (current == null || quantity <= 0 || current < quantity) {
      return false;
    }
    _stockByAllocationKey[key] = current - quantity;
    return true;
  }

  Product _withComputedStock(Product product) {
    return Product(
      id: product.id,
      name: product.name,
      description: product.description,
      lowestPrice: product.lowestPrice,
      imagePath: product.imagePath,
      imageBytes: product.imageBytes,
      stockQuantity: _totalStockForProduct(product.id),
      status: product.status,
      categoryId: product.categoryId,
      categoryName: product.categoryName,
      brandId: product.brandId,
      brandName: product.brandName,
    );
  }

  int _totalStockForProduct(int productId) {
    var total = 0;
    for (final entry in _stockByAllocationKey.entries) {
      if (productIdFromKey(entry.key) == productId) {
        total += entry.value;
      }
    }
    return total;
  }

  Future<void> _ensureSeeded() async {
    final seedFuture = _seedFuture;
    if (seedFuture != null) {
      await seedFuture;
      _seedFuture = null;
    }
    await _ensureLoadedFromApi();
  }

  /// Fetches the catalogue once the session knows which vendor to ask for.
  ///
  /// Returns immediately when there is no session — before login, and in the
  /// mock-seeded and test paths — so the in-memory behaviour is unchanged.
  Future<void> _ensureLoadedFromApi() async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null || _loadedVendorId == vendorId) {
      return;
    }

    // Cleared in `whenComplete` rather than on success, so a failed fetch is
    // retried by the next caller instead of leaving the catalogue permanently
    // empty behind a future that already completed.
    final existing = _apiLoad;
    if (existing != null) {
      await existing;
      return;
    }
    final load = _loadFromApi(auth.api, vendorId).then((_) {
      _loadedVendorId = vendorId;
    });
    _apiLoad = load.whenComplete(() => _apiLoad = null);
    await _apiLoad;
  }

  Future<void> _loadSeedProducts() async {
    // Starts empty — products are added via saveProduct.
  }

  /// Fills the same maps `saveProduct` would, from the vendor's catalogue.
  ///
  /// Failure is deliberately not swallowed: an empty inventory and an
  /// unreachable server look identical on screen, and a cashier told "no
  /// products" will go looking for the products rather than for the wifi. The
  /// [ApiException] surfaces through `_ensureSeeded` to whichever cubit
  /// triggered the load.
  Future<void> _loadFromApi(ApiClient api, int vendorId) async {
    final results = await Future.wait([
      api.get('/api/core/vendor/$vendorId/product/'),
      api.get('/api/core/vendor/$vendorId/category/'),
      api.get('/api/core/vendor/$vendorId/brand/'),
    ]);
    final payload = results[0] as List;

    _categories
      ..clear()
      ..addAll(
        (results[1] as List).cast<Map<String, dynamic>>().map(
          (row) => Category(
            id: (row['id'] as num).toInt(),
            name: row['name'] as String? ?? '',
          ),
        ),
      );
    _brands
      ..clear()
      ..addAll(
        (results[2] as List).cast<Map<String, dynamic>>().map(
          (row) => Brand(
            id: (row['id'] as num).toInt(),
            name: row['name'] as String? ?? '',
          ),
        ),
      );

    final bundle = mapProductsResponse(
      payload,
      categoryNameById: {for (final c in _categories) c.id: c.name},
      brandNameById: {for (final b in _brands) b.id: b.name},
    );

    _products
      ..clear()
      ..addAll(bundle.products);
    _variantGroupsByProductId
      ..clear()
      ..addAll(bundle.groupsByProductId);
    _variantOptionsByGroupId
      ..clear()
      ..addAll(bundle.optionsByGroupId);
    _stockByAllocationKey
      ..clear()
      ..addAll(bundle.stockByAllocationKey);
    _variantIdByAllocationKey
      ..clear()
      ..addAll(bundle.variantIdByAllocationKey);
    _priceByAllocationKey
      ..clear()
      ..addAll(bundle.priceByAllocationKey);
    _allocationKeyByVariantId
      ..clear()
      ..addAll({
        for (final entry in bundle.variantIdByAllocationKey.entries)
          entry.value: entry.key,
      });

    // Ids come from the server now, so a locally created product must not be
    // handed one the server might also issue.
    _nextProductId = _above(_products.map((product) => product.id), 1000);
    _nextVariantGroupId = _above(
      _variantGroupsByProductId.values.expand((g) => g).map((g) => g.id),
      5000,
    );
    _nextVariantOptionId = _above(
      _variantOptionsByGroupId.values.expand((o) => o).map((o) => o.id),
      9000,
    );
  }

  /// Sets one variant's master stock on the server.
  ///
  /// The first write this repository has ever made. Everything else here is
  /// still in-memory, which is why this is deliberately narrow: one field, one
  /// row, an absolute value rather than a delta, and no attempt to queue it.
  /// A price or stock correction is the edit a booth operator actually makes,
  /// and it only needs a PATCH.
  ///
  /// Online-only by decision. There is no offline queue for this and no local
  /// change on failure: the row keeps showing the server's number until the
  /// server has confirmed a new one, so the table never shows a stock count
  /// that exists only on this tablet. The [ApiException] is left to the
  /// caller, whose job is to say so.
  ///
  /// On success the row takes the value the server echoed back, not the value
  /// sent, for the same reason.
  Future<void> updateVariantStock({
    required String allocationKey,
    required int stock,
  }) async {
    final target = _writeTarget(allocationKey);
    final row =
        await target.api.patch(target.path, body: {'stock_quantity': stock})
            as Map<String, dynamic>;
    _stockByAllocationKey[allocationKey] =
        (row['stock_quantity'] as num?)?.toInt() ?? stock;
  }

  /// Sets every variant of [productId] to [price] on the server.
  ///
  /// Product-wide by decision. The server prices each variant separately, but
  /// this app shows one price per product and that is how a booth operator
  /// thinks of it: "this shoe is 3,200 now", not "size 42 is 3,200 now". The
  /// caller is expected to have checked [variantPricesForProduct] and warned
  /// if the variants currently disagree, since this overwrites all of them.
  ///
  /// One call per variant, in order, stopping at the first failure. Bazaar
  /// wifi makes a half-finished run a real state rather than a corner case,
  /// so the outcome says how many were changed and the caller refreshes so
  /// the table shows whichever mix the server now holds. Sent as a decimal
  /// string: a bare double can serialise as `3200.5`, and this is money.
  ///
  /// The catalogue is re-fetched afterwards whenever anything was written.
  /// `Product.lowestPrice` is the lowest variant price, and after a partial run
  /// nothing on this side can compute that honestly; the server can.
  Future<PriceUpdateOutcome> updateProductPrice({
    required int productId,
    required double price,
  }) async {
    final keys = variantPricesForProduct(productId).keys.toList()..sort();
    var updated = 0;
    ApiException? failure;
    try {
      for (final key in keys) {
        final target = _writeTarget(key);
        await target.api.patch(
          target.path,
          body: {'price': price.toStringAsFixed(2)},
        );
        updated++;
      }
    } on ApiException catch (error) {
      failure = error;
    }
    if (updated > 0) {
      await refresh();
    }
    return PriceUpdateOutcome(
      updated: updated,
      total: keys.length,
      failure: failure,
    );
  }

  /// Where a variant is written to, or a [StateError] when there is nowhere.
  ///
  /// A StateError rather than an ApiException because reaching this without a
  /// server is a programming mistake, not a network condition: the control is
  /// meant to be hidden whenever [canQuickEdit] is false.
  ({ApiClient api, String path}) _writeTarget(String allocationKey) {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    final variantId = _variantIdByAllocationKey[allocationKey];
    if (auth == null || vendorId == null || variantId == null) {
      throw StateError('No server-side variant for $allocationKey');
    }
    final productId = productIdFromKey(allocationKey);
    return (
      api: auth.api,
      path: '/api/core/vendor/$vendorId/product/$productId/variant/$variantId/',
    );
  }

  /// Re-fetches the catalogue, discarding what is held now.
  ///
  /// Does nothing without a session, so calling it from a shared refresh
  /// control is safe in the mock-seeded build.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoadedFromApi();
  }

  static int _above(Iterable<int> ids, int floor) {
    var highest = floor;
    for (final id in ids) {
      if (id >= highest) {
        highest = id + 1;
      }
    }
    return highest;
  }

  /// Builds the key used in [saveProduct]'s `combinationStocks` map: the
  /// trimmed option value(s) for a combination, joined with `||` when there
  /// are two categories. With a single category, this is just that value.
  static String combinationValueKey(String valueA, [String? valueB]) {
    if (valueB == null) {
      return valueA.trim();
    }
    return '${valueA.trim()}||${valueB.trim()}';
  }

  void _replaceVariantsForProduct({
    required int productId,
    required List<VariantCategoryDraft> variantGroups,
    required Map<String, int> combinationStocks,
  }) {
    final oldGroups = _variantGroupsByProductId.remove(productId) ?? const [];
    for (final group in oldGroups) {
      _variantOptionsByGroupId.remove(group.id);
    }
    _stockByAllocationKey.removeWhere(
      (key, _) => productIdFromKey(key) == productId,
    );
    // Option ids are reissued when variants are rebuilt, so a stale archived
    // key would land on whatever combination inherits that id.
    _archivedAllocationKeys.removeWhere(
      (key) => productIdFromKey(key) == productId,
    );

    if (variantGroups.isEmpty) {
      return;
    }

    final groups = <ProductVariantGroup>[];
    final optionsByGroup = <List<ProductVariantOption>>[];

    for (final draft in variantGroups) {
      final group = ProductVariantGroup(
        id: _nextVariantGroupId++,
        productId: productId,
        name: draft.name.trim(),
      );
      groups.add(group);

      final seenValues = <String>{};
      final options = <ProductVariantOption>[];
      for (final rawValue in draft.optionValues) {
        final value = rawValue.trim();
        if (value.isEmpty || !seenValues.add(value.toUpperCase())) {
          continue;
        }
        options.add(
          ProductVariantOption(
            id: _nextVariantOptionId++,
            variantGroupId: group.id,
            value: value,
            extraPrice: draft.extraPriceByValue[rawValue] ?? 0,
          ),
        );
      }
      _variantOptionsByGroupId[group.id] = options;
      optionsByGroup.add(options);
    }
    _variantGroupsByProductId[productId] = groups;

    final optionsA = optionsByGroup[0];
    if (optionsByGroup.length == 1) {
      for (final optionA in optionsA) {
        final stock =
            combinationStocks[combinationValueKey(optionA.value)] ?? 0;
        _stockByAllocationKey[allocationKey(productId, optionIdA: optionA.id)] =
            stock;
      }
      return;
    }

    final optionsB = optionsByGroup[1];
    for (final optionA in optionsA) {
      for (final optionB in optionsB) {
        final stock =
            combinationStocks[combinationValueKey(
              optionA.value,
              optionB.value,
            )] ??
            0;
        _stockByAllocationKey[allocationKey(
              productId,
              optionIdA: optionA.id,
              optionIdB: optionB.id,
            )] =
            stock;
      }
    }
  }
}

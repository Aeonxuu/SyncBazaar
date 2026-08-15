import 'dart:typed_data';

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

  int? variantIdFor(String allocationKey) =>
      _variantIdByAllocationKey[allocationKey];

  String? allocationKeyForVariant(int variantId) =>
      _allocationKeyByVariantId[variantId];

  /// Whether the catalogue has been fetched, so callers that depend on the
  /// variant mapping can make sure it is there first.
  Future<void> ensureLoaded() => _ensureSeeded();

  final List<Product> _products = [];

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

  /// Saves a product. [variantGroups] holds 0-2 variant categories (e.g.
  /// Color, Size). [combinationStocks] supplies the stock for each
  /// sellable combination, keyed by [combinationValueKey]. When
  /// [variantGroups] is empty, [stockQuantity] is used as the flat stock.
  Future<Product> saveProduct({
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
    await _ensureSeeded();
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
      basePrice: basePrice,
      imagePath: imagePath,
      imageBytes: imageBytes,
      status: status,
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
      basePrice: current.basePrice,
      imagePath: current.imagePath,
      imageBytes: current.imageBytes,
      stockQuantity: current.stockQuantity,
      status: status,
    );
  }

  Future<void> deleteProduct(int id) async {
    await _ensureSeeded();
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
      basePrice: product.basePrice,
      imagePath: product.imagePath,
      imageBytes: product.imageBytes,
      stockQuantity: _totalStockForProduct(product.id),
      status: product.status,
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
    final payload =
        await api.get('/api/core/vendor/$vendorId/product/') as List;
    final bundle = mapProductsResponse(payload);

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

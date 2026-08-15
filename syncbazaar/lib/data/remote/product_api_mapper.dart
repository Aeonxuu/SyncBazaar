import '../../core/config/api_config.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';

/// Everything `ProductRepository` keeps in memory, built from one API response.
///
/// A plain result object rather than the repository reaching into JSON itself,
/// so the translation can be tested without a server and the repository stays
/// about storage.
class ApiProductBundle {
  const ApiProductBundle({
    required this.products,
    required this.groupsByProductId,
    required this.optionsByGroupId,
    required this.stockByAllocationKey,
    required this.variantIdByAllocationKey,
  });

  final List<Product> products;
  final Map<int, List<ProductVariantGroup>> groupsByProductId;
  final Map<int, List<ProductVariantOption>> optionsByGroupId;
  final Map<String, int> stockByAllocationKey;

  /// Allocation key to the server's `ProductVariant` id.
  ///
  /// The bridge between the two ways of naming a sellable unit. Nothing reads
  /// it yet; uploading a sale needs it, because the server identifies what was
  /// sold by variant, never by the client's composite string.
  final Map<String, int> variantIdByAllocationKey;
}

/// Turns `GET /api/core/vendor/<id>/product/` into the shapes the app already
/// uses.
///
/// The app models a product as having up to two *variant categories* whose
/// names the vendor chooses — Colour and Size for shoes, Size and Flavour for
/// ice cream. The server models the same thing as `Attribute` and
/// `AttributeValue`. This maps between them.
///
/// **`attributes` is read only as a lookup table, never as a list of what a
/// product offers.** `Attribute.name` is globally unique server-side, so a
/// single "Size" row is shared by every product in the system and carries every
/// value anyone ever attached to it — a shoe currently reports `S`, `M` and `L`
/// alongside `36`-`43`. What a product actually comes in is only knowable from
/// its own variants, so the option lists here are built from those and the
/// `attributes` block is used solely to learn which category a value belongs
/// to.
ApiProductBundle mapProductsResponse(List<dynamic> payload) {
  final products = <Product>[];
  final groupsByProductId = <int, List<ProductVariantGroup>>{};
  final optionsByGroupId = <int, List<ProductVariantOption>>{};
  final stockByAllocationKey = <String, int>{};
  final variantIdByAllocationKey = <String, int>{};

  for (final entry in payload) {
    final product = entry as Map<String, dynamic>;
    final productId = (product['id'] as num).toInt();
    final variants = (product['variants'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    // valueId -> (attributeId, value). Built from `attributes`, which is the
    // only place the value's own name and its category are given.
    final attributeIdByValueId = <int, int>{};
    final valueTextByValueId = <int, String>{};
    final attributeNameById = <int, String>{};
    for (final attribute in (product['attributes'] as List? ?? const [])) {
      final map = attribute as Map<String, dynamic>;
      final attributeId = (map['id'] as num).toInt();
      attributeNameById[attributeId] = map['name'] as String? ?? '';
      for (final value in (map['values'] as List? ?? const [])) {
        final valueMap = value as Map<String, dynamic>;
        final valueId = (valueMap['id'] as num).toInt();
        attributeIdByValueId[valueId] = attributeId;
        valueTextByValueId[valueId] = valueMap['value'] as String? ?? '';
      }
    }

    // Which categories this product genuinely uses, and which values of each,
    // taken from the variants rather than from `attributes`.
    final valueIdsByAttributeId = <int, Set<int>>{};
    for (final variant in variants) {
      for (final raw in (variant['attribute_values'] as List? ?? const [])) {
        final valueId = (raw as num).toInt();
        final attributeId = attributeIdByValueId[valueId];
        if (attributeId == null) {
          continue;
        }
        valueIdsByAttributeId
            .putIfAbsent(attributeId, () => <int>{})
            .add(valueId);
      }
    }

    // Sorted by attribute id so category 1 and category 2 stay in the same
    // order between loads. The server does not record which the vendor meant
    // to be first, so a stable arbitrary order beats one that shuffles.
    final attributeIds = valueIdsByAttributeId.keys.toList()..sort();
    final usedAttributeIds = attributeIds.take(_maxCategories).toList();

    final groups = <ProductVariantGroup>[];
    for (final attributeId in usedAttributeIds) {
      final groupId = _groupId(productId, attributeId);
      groups.add(
        ProductVariantGroup(
          id: groupId,
          productId: productId,
          name: attributeNameById[attributeId] ?? 'Category',
        ),
      );
      final valueIds = valueIdsByAttributeId[attributeId]!.toList()..sort();
      optionsByGroupId[groupId] = [
        for (final valueId in valueIds)
          ProductVariantOption(
            id: valueId,
            variantGroupId: groupId,
            value: valueTextByValueId[valueId] ?? '',
          ),
      ];
    }
    if (groups.isNotEmpty) {
      groupsByProductId[productId] = groups;
    }

    for (final variant in variants) {
      final valueIds = (variant['attribute_values'] as List? ?? const [])
          .map((raw) => (raw as num).toInt())
          .toList();

      int? optionFor(int index) {
        if (index >= usedAttributeIds.length) {
          return null;
        }
        final attributeId = usedAttributeIds[index];
        for (final valueId in valueIds) {
          if (attributeIdByValueId[valueId] == attributeId) {
            return valueId;
          }
        }
        return null;
      }

      // Resolved by looking up each value's attribute rather than by position:
      // `attribute_values` is a many-to-many, and its order is whatever the
      // database returns, not the order the categories are displayed in.
      final key = allocationKeyFor(
        productId,
        optionIdA: optionFor(0),
        optionIdB: optionFor(1),
      );
      stockByAllocationKey[key] =
          (stockByAllocationKey[key] ?? 0) +
          ((variant['stock_quantity'] as num?)?.toInt() ?? 0);
      variantIdByAllocationKey[key] = (variant['id'] as num).toInt();
    }

    products.add(
      Product(
        id: productId,
        name: product['name'] as String? ?? '',
        basePrice: _basePriceOf(variants),
        // The server stores whatever the client sent, which for the seeded data
        // is the app's own asset path. A CDN URL will land here unchanged once
        // object storage exists; `ProductThumbnail` already handles both.
        imagePath: _imageOf(variants),
        stockQuantity: 0, // recomputed from the stock map by the repository
      ),
    );
  }

  return ApiProductBundle(
    products: products,
    groupsByProductId: groupsByProductId,
    optionsByGroupId: optionsByGroupId,
    stockByAllocationKey: stockByAllocationKey,
    variantIdByAllocationKey: variantIdByAllocationKey,
  );
}

const int _maxCategories = 2;

/// A group id unique to this product's use of an attribute.
///
/// Attribute ids are global — every product using "Size" shares attribute 1 —
/// but `optionsByGroupId` is keyed by group, so sharing an id would make two
/// products share one option list. Derived rather than counted so the same
/// product keeps the same group id across reloads.
int _groupId(int productId, int attributeId) => productId * 1000 + attributeId;

/// The client's composite key for one sellable combination.
///
/// Duplicated from `ProductRepository.allocationKey` rather than imported to
/// keep this file free of the repository; the format is asserted in tests on
/// both sides.
String allocationKeyFor(int productId, {int? optionIdA, int? optionIdB}) =>
    '$productId:${optionIdA ?? 0}:${optionIdB ?? 0}';

/// The lowest variant price, as the product's headline price.
///
/// The server prices each variant independently; the client carries one
/// `basePrice` per product plus an optional per-option surcharge. That is
/// narrower, and the two only agree exactly while every variant of a product
/// costs the same — true of everything seeded so far. Taking the lowest means a
/// mismatch understates rather than overstates, which is the safer way to be
/// wrong on a price tag.
double _basePriceOf(List<Map<String, dynamic>> variants) {
  double? lowest;
  for (final variant in variants) {
    final price = double.tryParse('${variant['price']}');
    if (price == null) {
      continue;
    }
    if (lowest == null || price < lowest) {
      lowest = price;
    }
  }
  return lowest ?? 0;
}

/// A product's picture, taken from whichever variant has one.
///
/// Reads `image_url`, which the server resolves for us: an uploaded photo's
/// URL where one exists, and the bundled asset path otherwise. Reading
/// `image_link` directly — as this did before photos could be uploaded — means
/// a product whose photo was replaced still shows the placeholder art it
/// shipped with.
///
/// An uploaded photo wins over a bundled one even if it belongs to a later
/// variant: a real photograph of the shoe is more use than stock art, whatever
/// order the variants arrive in.
String? _imageOf(List<Map<String, dynamic>> variants) {
  String? fallback;
  for (final variant in variants) {
    final uploaded = _trimmed(variant['image']);
    final resolved =
        _trimmed(variant['image_url']) ?? _trimmed(variant['image_link']);
    if (resolved == null) {
      continue;
    }
    if (uploaded != null) {
      return _absolute(resolved);
    }
    fallback ??= resolved;
  }
  return fallback == null ? null : _absolute(fallback);
}

String? _trimmed(Object? value) {
  final text = (value as String?)?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Makes a server path renderable.
///
/// The API answers with an absolute URL when photos live in the object store,
/// but with a host-relative one (`/media/products/...`) when they are served
/// by Django itself. Only this layer knows which server the path came from, so
/// it resolves it here rather than leaving a path no widget can load: the
/// thumbnail treats anything that is not `http(s)` as a bundled asset, and
/// would render the placeholder instead.
///
/// Bundled asset paths are left alone — they are not server paths at all.
String _absolute(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  if (!path.startsWith('/')) {
    return path;
  }
  return '${ApiConfig.baseUrl}$path';
}

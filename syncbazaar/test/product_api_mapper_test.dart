import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/product_api_mapper.dart';

/// One product shaped exactly like the live API's response, including the part
/// that is wrong: `attributes` lists every value the attribute has anywhere,
/// so a shoe is offered `S`, `M` and `L` from another vendor's clothing. The
/// mapper has to ignore that and read the variants instead.
const _payload = '''
[{
  "id": 16,
  "name": "Nike Air Max SC",
  "vendor": 3,
  "category": 1,
  "variants": [
    {"id": 208, "stock_quantity": 20, "price": "1900.00",
     "image_link": "assets/images/default_shoes/airmaxsc.png",
     "product": 16, "attribute_values": [7, 10]},
    {"id": 209, "stock_quantity": 14, "price": "1900.00",
     "image_link": "assets/images/default_shoes/airmaxsc.png",
     "product": 16, "attribute_values": [11, 7]},
    {"id": 210, "stock_quantity": 5, "price": "2400.00",
     "image_link": null,
     "product": 16, "attribute_values": [8, 10]}
  ],
  "attributes": [
    {"id": 1, "name": "Size", "values": [
      {"id": 10, "value": "36", "attribute": 1},
      {"id": 11, "value": "38", "attribute": 1},
      {"id": 3, "value": "L", "attribute": 1},
      {"id": 2, "value": "M", "attribute": 1},
      {"id": 1, "value": "S", "attribute": 1}
    ]},
    {"id": 2, "name": "Color", "values": [
      {"id": 7, "value": "Triple White", "attribute": 2},
      {"id": 8, "value": "Triple Black", "attribute": 2},
      {"id": 99, "value": "Never Used", "attribute": 2}
    ]}
  ]
}]
''';

void main() {
  ApiProductBundle mapped() =>
      mapProductsResponse(jsonDecode(_payload) as List);

  test('offers only the values the product actually has variants for', () {
    final bundle = mapped();
    final groups = bundle.groupsByProductId[16]!;

    final sizes = bundle.optionsByGroupId[groups.first.id]!
        .map((option) => option.value)
        .toList();
    final colours = bundle.optionsByGroupId[groups.last.id]!
        .map((option) => option.value)
        .toList();

    // S/M/L are another vendor's clothing sizes on the shared "Size" attribute,
    // and "Never Used" has no variant. None may reach the POS.
    expect(sizes, ['36', '38']);
    expect(colours, ['Triple White', 'Triple Black']);
  });

  test('names the categories from the server, not from hardcoded labels', () {
    // Category 1 and 2 are vendor-named slots -- an ice cream seller would get
    // Size and Flavour here -- so the names must come from the payload.
    final names = mapped().groupsByProductId[16]!.map((g) => g.name).toList();
    expect(names, ['Size', 'Color']);
  });

  test('resolves each value to its own category regardless of list order', () {
    // Variant 209 lists [11, 7] -- size first, then colour -- while 208 lists
    // [7, 10]. attribute_values is a many-to-many with no guaranteed order, so
    // reading it positionally would file the same shoe under two categories.
    final bundle = mapped();
    expect(bundle.stockByAllocationKey['16:10:7'], 20);
    expect(bundle.stockByAllocationKey['16:11:7'], 14);
    expect(bundle.stockByAllocationKey['16:10:8'], 5);
  });

  test('keeps the server variant id for every combination', () {
    // What a sale upload sends: the server names what was sold by variant.
    final bundle = mapped();
    expect(bundle.variantIdByAllocationKey['16:10:7'], 208);
    expect(bundle.variantIdByAllocationKey['16:11:7'], 209);
    expect(bundle.variantIdByAllocationKey['16:10:8'], 210);
  });

  test('gives products of different ids distinct category groups', () {
    // "Size" is one globally shared Attribute row, so two products would
    // collide on it if the group id were the attribute id.
    final bundle = mapProductsResponse([
      ...jsonDecode(_payload) as List,
      {...(jsonDecode(_payload) as List).first as Map<String, dynamic>, 'id': 17},
    ]);

    final a = bundle.groupsByProductId[16]!.map((g) => g.id).toSet();
    final b = bundle.groupsByProductId[17]!.map((g) => g.id).toSet();
    expect(a.intersection(b), isEmpty);
  });

  test('takes the lowest variant price as the headline price', () {
    // 1900 and 2400 across variants; the client carries one base price.
    expect(mapped().products.single.basePrice, 1900);
  });

  test('falls back to a variant that has an image', () {
    expect(
      mapped().products.single.imagePath,
      'assets/images/default_shoes/airmaxsc.png',
    );
  });

  test('handles a product with no variants at all', () {
    final bundle = mapProductsResponse([
      {'id': 5, 'name': 'Plain', 'variants': [], 'attributes': []},
    ]);

    expect(bundle.products.single.name, 'Plain');
    expect(bundle.groupsByProductId, isEmpty);
    expect(bundle.stockByAllocationKey, isEmpty);
    expect(bundle.products.single.basePrice, 0);
  });
}

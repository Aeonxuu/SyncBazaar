import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/product_variant.dart';

/// What the Return Stock dialog offers to put back.
///
/// The figures are not calculated here: a bazaar's allocations are decremented
/// as each sale is rung up, so what the app holds is already what should be
/// physically left on the table. The work is naming it -- turning
/// "1000:3:7 -> 4" into "Nike Air Max SC (Color Black, Size 42)  4" -- because
/// somebody is going to count shoes against this list.
void main() {
  late ProductRepository products;
  late int productId;
  late List<ProductVariantOption> colors;
  late List<ProductVariantOption> sizes;

  setUp(() async {
    products = ProductRepository();
    final product = await products.saveProduct(
      name: 'Nike Air Max SC',
      basePrice: 3500,
      variantGroups: const [
        VariantCategoryDraft(name: 'Color', optionValues: ['Black', 'White']),
        VariantCategoryDraft(name: 'Size', optionValues: ['42', '43']),
      ],
    );
    productId = product.id;
    final groups = await products.variantGroupsForProduct(productId);
    colors = await products.variantOptionsForGroup(groups[0].id);
    sizes = await products.variantOptionsForGroup(groups[1].id);
  });

  test('an allocation key round-trips to the product it came from', () async {
    final key = products.allocationKey(
      productId,
      optionIdA: colors[0].id,
      optionIdB: sizes[0].id,
    );

    // The screen splits on ':' to name the row, so the shape matters.
    expect(key.split(':'), hasLength(3));
    expect(products.productIdFromKey(key), productId);
    expect(key.split(':')[1], '${colors[0].id}');
    expect(key.split(':')[2], '${sizes[0].id}');
  });

  test('a product with no categories still keys cleanly', () async {
    final plain = await products.saveProduct(name: 'Tote', basePrice: 200);
    final key = products.allocationKey(plain.id);

    // Zeroes stand in for "no option", and must not be looked up as ids.
    expect(key, '${plain.id}:0:0');
    expect(products.productIdFromKey(key), plain.id);
  });

  test('only ended bazaars are offered for reconciling', () {
    // Returning stock from a bazaar that is still selling would take it out
    // from under a live till.
    BazaarEvent at(BazaarStatus status) => BazaarEvent(
      id: status.index,
      name: status.name,
      companyId: 1,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 2),
      status: status,
    );

    final all = [
      at(BazaarStatus.upcoming),
      at(BazaarStatus.ongoing),
      at(BazaarStatus.ended),
    ];
    final offered = all
        .where((event) => event.status == BazaarStatus.ended)
        .toList();

    expect(offered.map((e) => e.status), [BazaarStatus.ended]);
  });

  test('a fully sold bazaar has nothing left to bring back', () {
    // Every allocation decremented to zero. The dialog says so rather than
    // offering a Return Stock button that would move nothing.
    const allocations = {'1:2:3': 0, '1:2:4': 0};
    final withStock = allocations.entries.where((e) => e.value > 0);

    expect(withStock, isEmpty);
  });

  test('leftovers total the units somebody has to count', () {
    const allocations = {'1:2:3': 4, '1:2:4': 0, '1:5:3': 3};
    final total = allocations.values
        .where((quantity) => quantity > 0)
        .fold<int>(0, (sum, quantity) => sum + quantity);

    // Zero-quantity rows are dropped, not counted as lines.
    expect(total, 7);
    expect(allocations.values.where((q) => q > 0).length, 2);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';

/// What an allocation row is called.
///
/// The Edit Bazaar list used to print the product name on every line --
/// "Nike Air Max SC - Color: Triple White, Size: 36", forty times over -- so
/// most of each row's width went on the one word that does not change between
/// rows. The name is now printed once above the group, and each row carries
/// only what separates it from its siblings.
void main() {
  late ProductRepository products;

  setUp(() => products = ProductRepository());

  Future<List<ProductAllocationItem>> itemsFor({
    required String name,
    List<VariantCategoryDraft> categories = const [],
  }) async {
    final product = await products.saveProduct(
      name: name,
      basePrice: 3500,
      variantGroups: categories,
      stockQuantity: 5,
    );
    final all = await products.allocationItems();
    return all.where((item) => item.product.id == product.id).toList();
  }

  test('a two-category row names both, and not the product', () async {
    final items = await itemsFor(
      name: 'Nike Air Max SC',
      categories: const [
        VariantCategoryDraft(name: 'Color', optionValues: ['Triple White']),
        VariantCategoryDraft(name: 'Size', optionValues: ['36']),
      ],
    );

    expect(items.single.variantLabel, 'Color: Triple White, Size: 36');
    expect(items.single.variantLabel, isNot(contains('Nike Air Max SC')));
  });

  test(
    'the full label still carries the product, for lists without a header',
    () async {
      // Both spellings are needed: the pre-bazaar list is flat and has nowhere
      // to hang a product name.
      final items = await itemsFor(
        name: 'Nike Air Max SC',
        categories: const [
          VariantCategoryDraft(name: 'Color', optionValues: ['Triple White']),
        ],
      );

      expect(items.single.displayLabel, contains('Nike Air Max SC'));
      expect(items.single.displayLabel, contains('Color: Triple White'));
    },
  );

  test('a product with no categories is not left blank', () async {
    // An empty cell in a column of variants reads as a rendering fault.
    final items = await itemsFor(name: 'Tote Bag');

    expect(items.single.variantLabel, 'Standard');
    expect(items.single.displayLabel, 'Tote Bag');
  });

  test('one category names that one', () async {
    final items = await itemsFor(
      name: 'Cap',
      categories: const [
        VariantCategoryDraft(name: 'Color', optionValues: ['Black']),
      ],
    );

    expect(items.single.variantLabel, 'Color: Black');
  });
}

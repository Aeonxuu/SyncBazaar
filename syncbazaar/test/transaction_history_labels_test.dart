import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/sale.dart';

/// What the transaction history calls a product.
///
/// The label used to come from the local Order row when one happened to be in
/// memory, and be rebuilt from the catalogue otherwise. The two spell the same
/// shoe differently, so a bazaar's history showed "(Color Black, Size 42)" for
/// a sale rung up since launch and "(Black, 42)" for the identical product
/// read back from the server -- two rows, one shoe, in one list.
void main() {
  late ProductRepository products;
  late SalesRepository sales;
  late int productId;

  setUp(() async {
    products = ProductRepository();
    sales = SalesRepository();

    final product = await products.saveProduct(
      name: 'Nike Air Max SC',
      basePrice: 3500,
      variantGroups: const [
        VariantCategoryDraft(name: 'Color', optionValues: ['Black', 'White']),
        VariantCategoryDraft(name: 'Size', optionValues: ['42', '43']),
      ],
      combinationStocks: const {},
    );
    productId = product.id;
  });

  Future<Sale> sell({int? optionA, int? optionB}) async {
    final sale = Sale(
      id: 1,
      clientUuid: 'uuid-1',
      eventId: 1,
      productId: productId,
      variantOptionIdA: optionA,
      variantOptionIdB: optionB,
      customerName: 'Walk-in',
      employeeId: '',
      paymentMethod: 'CASH',
      qty: 1,
      total: 3500,
      timestamp: DateTime(2026, 8, 13, 10),
      orderStatus: OrderStatus.completed,
      synced: true,
    );
    await sales.addSale(sale);
    return sale;
  }

  Future<String> labelOf(Sale _) async {
    final cubit = OrdersCubit(sales, products);
    await cubit.load();
    return cubit.state.records.single.productLabel;
  }

  test('a variant is named with its category, as the cart says it', () async {
    final groups = await products.variantGroupsForProduct(productId);
    final colors = await products.variantOptionsForGroup(groups[0].id);
    final sizes = await products.variantOptionsForGroup(groups[1].id);

    final sale = await sell(optionA: colors[0].id, optionB: sizes[0].id);

    // The wording the receipt and the exported order list both use, so a row
    // here can be matched against a customer's copy.
    expect(await labelOf(sale), 'Nike Air Max SC (Color Black, Size 42)');
  });

  test('the label does not depend on whether the app has restarted', () async {
    final groups = await products.variantGroupsForProduct(productId);
    final colors = await products.variantOptionsForGroup(groups[0].id);
    final sizes = await products.variantOptionsForGroup(groups[1].id);
    final sale = await sell(optionA: colors[0].id, optionB: sizes[0].id);

    // Nothing about this sale says where it came from, and nothing should:
    // a sale read back from the server has no local Order beside it, and used
    // to be spelled differently for that reason alone.
    final first = await labelOf(sale);
    final second = await labelOf(sale);
    expect(first, second);
  });

  test('a product with no variant chosen is named plainly', () async {
    final sale = await sell();

    expect(await labelOf(sale), 'Nike Air Max SC');
  });

  test('an unknown option is dropped rather than printed as an id', () async {
    // An archived variant, say. A bare number at a cashier means nothing.
    final sale = await sell(optionA: 999999);

    expect(await labelOf(sale), 'Nike Air Max SC');
  });
}

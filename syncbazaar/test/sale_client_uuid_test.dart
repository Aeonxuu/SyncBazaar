import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:uuid/uuid.dart';

/// Guards the property idempotent upload rests on: a sale's wire identity is
/// unique per sale and never changes afterwards.
///
/// Worth pinning down because both ways of breaking it are silent. Reusing a
/// uuid across sales makes the server treat the second as a duplicate and drop
/// it — takings quietly go missing. Minting a fresh one on each copy makes a
/// retry look like a new sale — takings quietly double. Neither shows up until
/// the numbers are reconciled after the bazaar.
void main() {
  Sale saleWith(String uuid) => Sale(
    id: 1,
    clientUuid: uuid,
    eventId: 1,
    productId: 1,
    customerName: 'Customer',
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: 100,
    timestamp: DateTime(2026, 8, 11),
    orderStatus: OrderStatus.completed,
    synced: false,
  );

  test('copyWith keeps the same uuid when a sale is marked synced', () {
    final sale = saleWith('abc-123');

    final synced = sale.copyWith(synced: true);

    expect(synced.synced, isTrue);
    // The same sale, not a second one.
    expect(synced.clientUuid, 'abc-123');
  });

  test('copyWith keeps the same uuid when the status changes', () {
    final returned = saleWith(
      'abc-123',
    ).copyWith(orderStatus: OrderStatus.returned);

    expect(returned.orderStatus, OrderStatus.returned);
    expect(returned.clientUuid, 'abc-123');
  });

  test('separate sales get separate uuids', () {
    const uuid = Uuid();
    // One per cart line, which is how PosCubit.completeSale mints them.
    final generated = List.generate(50, (_) => uuid.v4());

    expect(generated.toSet().length, 50);
  });

  test('order status has no pending state', () {
    // The POS hardcodes completed and nothing else ever produced a value, so
    // pending and incomplete counted zero forever in the post-bazaar report.
    expect(OrderStatus.values, [OrderStatus.completed, OrderStatus.returned]);
  });
}

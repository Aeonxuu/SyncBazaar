import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/sale_api_mapper.dart';
import 'package:syncbazaar/models/sale.dart';

void main() {
  // 1393 is a known stock row; 9999 is one this client cannot resolve.
  String? keyFor(int stockId) => stockId == 1393 ? '16:10:7' : null;
  String methodFor(int id) => id == 2 ? 'GCASH' : 'CASH';

  List<Sale> map(String sales, String payments) => mapSalesResponse(
    jsonDecode(sales) as List,
    eventId: 111,
    paymentsPayload: jsonDecode(payments) as List,
    allocationKeyForStockId: keyFor,
    paymentMethodNameById: methodFor,
  );

  test('joins the sale to its payment, which the server keeps apart', () {
    final sales = map(
      '''
      [{"id": 2302, "event_stock": 1393, "sold_by": 60, "client_uuid": null,
        "customer_name": "Aaron Domingo", "quantity": 2, "total": "2700.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM",
        "synced": true}]
      ''',
      '''
      [{"sale": 2302, "mode_of_payment": 2,
        "required_information": "0917-555-0101"}]
      ''',
    );

    final sale = sales.single;
    expect(sale.customerName, 'Aaron Domingo');
    expect(sale.qty, 2);
    expect(sale.total, 2700);
    expect(sale.productId, 16);
    expect(sale.variantOptionIdA, 10);
    expect(sale.variantOptionIdB, 7);
    expect(sale.paymentMethod, 'GCASH');
    expect(sale.employeeId, '0917-555-0101');
    expect(sale.orderStatus, OrderStatus.completed);
    // It came from the server, so by definition it is already there.
    expect(sale.synced, isTrue);
  });

  test('gives a server-side sale a stable identity of its own', () {
    final sales = map('''
      [{"id": 2302, "event_stock": 1393, "client_uuid": null,
        "customer_name": "A", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM"},
       {"id": 2303, "event_stock": 1393, "client_uuid": null,
        "customer_name": "B", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM"}]
      ''', '[]');

    // Seeded sales carry no client uuid. Two records sharing an empty string
    // would read as the same sale everywhere identity is used.
    expect(sales.map((s) => s.clientUuid).toSet(), hasLength(2));
    expect(sales.first.clientUuid, 'server-2302');
  });

  test('keeps the uuid of a sale this app rang up', () {
    final sales = map('''
      [{"id": 9, "event_stock": 1393, "client_uuid": "abc-123",
        "customer_name": "A", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM"}]
      ''', '[]');

    // Matching on this is what stops a sale being counted twice once it has
    // been uploaded and read back.
    expect(sales.single.clientUuid, 'abc-123');
  });

  test('skips a sale whose stock row cannot be resolved', () {
    final sales = map('''
      [{"id": 1, "event_stock": 9999, "client_uuid": null,
        "customer_name": "A", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM"}]
      ''', '[]');

    // An archived variant or a delisted product. Showing it against the wrong
    // shoe is worse than leaving it out of the history.
    expect(sales, isEmpty);
  });

  test('reads a returned sale as returned', () {
    final sales = map('''
      [{"id": 1, "event_stock": 1393, "client_uuid": null,
        "customer_name": "A", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "RT"}]
      ''', '[]');

    expect(sales.single.orderStatus, OrderStatus.returned);
  });

  test('falls back to cash when a sale has no payment row', () {
    final sales = map('''
      [{"id": 1, "event_stock": 1393, "client_uuid": null,
        "customer_name": "", "quantity": 1, "total": "1.00",
        "timestamp": "2026-08-03T00:00:00Z", "order_status": "CM"}]
      ''', '[]');

    expect(sales.single.paymentMethod, 'CASH');
    // An unnamed customer reads as Walk-in, the same as one rung up here.
    expect(sales.single.customerName, kWalkInCustomer);
  });
}

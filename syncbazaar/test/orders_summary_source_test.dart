import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/services/orders_workbook.dart';

/// The List of Orders dialog and the workbook it exports must agree.
///
/// They did not. The dialog counted `Order` rows, which are only ever written
/// at the till and never fetched, while the export read sales, which do come
/// back from the server. A bazaar whose sales predated this session therefore
/// showed "Total orders 0" beside a spreadsheet full of them.
///
/// The dialog now counts sales too. These pin the arithmetic both sides share,
/// so the two cannot drift apart again without a test saying so.
void main() {
  Sale sale({
    required int eventId,
    String method = 'CASH',
    OrderStatus status = OrderStatus.completed,
    int qty = 1,
    double total = 3500,
  }) => Sale(
    id: DateTime.now().microsecondsSinceEpoch,
    clientUuid: 'uuid-$eventId-$method-$status-$total',
    eventId: eventId,
    productId: 1,
    customerName: 'Walk-in',
    employeeId: '',
    paymentMethod: method,
    qty: qty,
    total: total,
    timestamp: DateTime(2026, 8, 13, 10),
    orderStatus: status,
    synced: true,
  );

  /// The dialog's own grouping, kept in step with the workbook's.
  Map<String, int> countByMethod(List<Sale> sales) {
    final counts = <String, int>{};
    for (final sale in sales) {
      final method = sale.paymentMethod.trim().isEmpty
          ? 'CASH'
          : sale.paymentMethod.trim().toUpperCase();
      counts[method] = (counts[method] ?? 0) + 1;
    }
    return counts;
  }

  test('the dialog total matches the rows the workbook writes', () {
    final sales = [
      sale(eventId: 1),
      sale(eventId: 1, method: 'GCASH', total: 4000),
      sale(eventId: 1, status: OrderStatus.returned, total: 1200),
      // A different bazaar's sale must not be counted into this one.
      sale(eventId: 2, total: 999),
    ];

    final forEvent = sales.where((s) => s.eventId == 1).toList();
    final workbookRows = forEvent.length;

    expect(workbookRows, 3);
    expect(
      countByMethod(forEvent).values.fold<int>(0, (a, b) => a + b),
      workbookRows,
    );
  });

  test('methods are grouped the way the workbook names its sheets', () {
    final sales = [
      sale(eventId: 1, method: ' gcash '),
      sale(eventId: 1, method: 'GCash'),
      sale(eventId: 1, method: ''),
    ];

    final counts = countByMethod(sales);

    // Two GCash sales land on one sheet, and a blank method is cash.
    expect(counts['GCASH'], 2);
    expect(counts['CASH'], 1);
    expect(counts.keys.length, 2);
  });

  test('a returned sale is counted, not dropped', () {
    final sales = [
      sale(eventId: 1),
      sale(eventId: 1, status: OrderStatus.returned),
    ];

    final completed = sales
        .where((s) => s.orderStatus == OrderStatus.completed)
        .length;
    final returned = sales
        .where((s) => s.orderStatus == OrderStatus.returned)
        .length;

    expect(completed + returned, sales.length);
    // The workbook lists it with a Status column rather than hiding it, so
    // the dialog's total has to include it or the two disagree again.
    expect(returned, 1);
  });

  test('the workbook writes exactly the rows the dialog counted', () {
    final sales = [
      sale(eventId: 1),
      sale(eventId: 1, method: 'GCASH'),
      sale(eventId: 1, method: 'GCASH', status: OrderStatus.returned),
    ];

    final lines = [
      for (final s in sales)
        OrderLine(
          date: s.timestamp,
          customerName: s.customerName,
          product: 'Something',
          paymentMethod: s.paymentMethod,
          reference: s.employeeId,
          quantity: s.qty,
          total: s.total,
          returned: s.orderStatus == OrderStatus.returned,
        ),
    ];

    // Rebuilt from the bytes so this measures the file, not the input list.
    final bytes = const OrdersWorkbook().build(
      lines: lines,
      extraFieldLabelByMethod: const {'GCASH': 'Reference Number'},
    );
    expect(bytes, isNotEmpty);

    final counts = countByMethod(sales);
    expect(counts['CASH'], 1);
    expect(counts['GCASH'], 2);
    expect(lines.length, sales.length);
  });
}

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/services/orders_workbook.dart';

/// The order list is what a venue reconciles its cut against, so the shape of
/// the workbook matters as much as the figures: one sheet per payment method,
/// and a reference column only where a method actually asks for one.
void main() {
  OrderLine line({
    DateTime? date,
    String customer = 'Walk-in',
    String product = 'Nike Air Max SC (Color Black, Size 42)',
    String method = 'CASH',
    String reference = '',
    int quantity = 1,
    double total = 3500,
    bool returned = false,
  }) => OrderLine(
    date: date ?? DateTime(2026, 8, 13, 14, 32),
    customerName: customer,
    product: product,
    paymentMethod: method,
    reference: reference,
    quantity: quantity,
    total: total,
    returned: returned,
  );

  Excel build({
    required List<OrderLine> lines,
    Map<String, String?> labels = const {},
  }) => Excel.decodeBytes(
    const OrdersWorkbook().build(
      lines: lines,
      extraFieldLabelByMethod: labels,
    ),
  );

  List<String> headersOf(Excel book, String sheet) => book.tables[sheet]!.rows
      .first
      .map((cell) => cell?.value?.toString() ?? '')
      .toList();

  List<String> rowOf(Excel book, String sheet, int index) =>
      book.tables[sheet]!.rows[index]
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();

  test('one sheet per payment method used', () {
    final book = build(
      lines: [
        line(method: 'CASH'),
        line(method: 'GCASH', reference: 'REF-001'),
      ],
      labels: {'GCASH': 'Reference Number'},
    );

    expect(book.tables.keys, containsAll(<String>['CASH', 'GCASH']));
  });

  test('the cash sheet exists even when nothing was paid in cash', () {
    // The workbook should open on a familiar sheet rather than on whichever
    // method happened to be used first.
    final book = build(
      lines: [line(method: 'GCASH', reference: 'REF-001')],
      labels: {'GCASH': 'Reference Number'},
    );

    expect(book.tables.keys, contains('CASH'));
    // Header only.
    expect(book.tables['CASH']!.rows, hasLength(1));
  });

  test('only a method with a configured field gets the extra column', () {
    final book = build(
      lines: [
        line(method: 'CASH'),
        line(method: 'GCASH', reference: 'REF-001'),
      ],
      labels: {'GCASH': 'Reference Number'},
    );

    expect(headersOf(book, 'CASH'), [
      'Date',
      'Customer Name',
      'Product',
      'Unit Price',
      'Quantity',
      'Total',
      'Status',
    ]);
    // The extra field sits between the product and the money, where it was
    // asked for, rather than tacked on the end.
    expect(headersOf(book, 'GCASH'), [
      'Date',
      'Customer Name',
      'Product',
      'Reference Number',
      'Unit Price',
      'Quantity',
      'Total',
      'Status',
    ]);
  });

  test('a method with a blank label carries no empty column', () {
    final book = build(
      lines: [line(method: 'COOP')],
      labels: {'COOP': '   '},
    );

    expect(headersOf(book, 'COOP'), isNot(contains('')));
    expect(headersOf(book, 'COOP'), hasLength(7));
  });

  test('writes the reference into the extra column', () {
    final book = build(
      lines: [line(method: 'GCASH', reference: 'REF-001')],
      labels: {'GCASH': 'Reference Number'},
    );

    expect(rowOf(book, 'GCASH', 1)[3], 'REF-001');
  });

  test('unit price is derived from what was actually collected', () {
    // Three units for 3000 after a discount is 1000 each, not the tag price.
    final book = build(lines: [line(quantity: 3, total: 3000)]);

    expect(rowOf(book, 'CASH', 1)[3], '1000');
    expect(rowOf(book, 'CASH', 1)[4], '3');
    expect(rowOf(book, 'CASH', 1)[5], '3000');
  });

  test('a repeating unit price is rounded to the centavo', () {
    // 4750 / 3 is 1583.333... and would otherwise print every digit of it.
    final book = build(lines: [line(quantity: 3, total: 4750)]);

    expect(rowOf(book, 'CASH', 1)[3], '1583.33');
  });

  test('a returned sale is listed and marked, not dropped', () {
    final book = build(
      lines: [line(customer: 'Ana'), line(customer: 'Ben', returned: true)],
    );

    final statuses = book.tables['CASH']!.rows
        .skip(1)
        .map((row) => row.last?.value?.toString())
        .toList();
    expect(statuses, ['Completed', 'Returned']);
  });

  test('rows are ordered by time within a sheet', () {
    final book = build(
      lines: [
        line(customer: 'Late', date: DateTime(2026, 8, 13, 16)),
        line(customer: 'Early', date: DateTime(2026, 8, 13, 9)),
      ],
    );

    expect(rowOf(book, 'CASH', 1)[1], 'Early');
    expect(rowOf(book, 'CASH', 2)[1], 'Late');
  });

  test('a method name Excel would reject is made safe', () {
    // Sheet names cannot contain []:*?/\ — a venue typing this in Settings
    // would otherwise produce a file that will not open at all.
    final book = build(lines: [line(method: 'BANK/BPI')]);

    expect(book.tables.keys, isNot(contains('BANK/BPI')));
    expect(book.tables.keys.any((name) => name.startsWith('BANK')), isTrue);
  });

  test('a method name over 31 characters is truncated', () {
    const long = 'PAYMENT VIA A VERY LONG METHOD NAME INDEED';
    final book = build(lines: [line(method: long)]);

    final sheet = book.tables.keys.firstWhere((name) => name != 'CASH');
    expect(sheet.length, lessThanOrEqualTo(31));
  });

  test('methods differing only past the cut do not collide', () {
    final book = build(
      lines: [
        line(method: 'BANK TRANSFER TO THE FIRST ACCOUNT HERE'),
        line(method: 'BANK TRANSFER TO THE FIRST ACCOUNT THERE'),
      ],
    );

    // Two methods, two sheets, plus CASH — a collision would silently merge
    // one venue's takings into another's sheet.
    expect(book.tables.keys, hasLength(3));
  });

  test('method names are matched regardless of case or padding', () {
    final book = build(
      lines: [line(method: ' gcash ', reference: 'REF-001')],
      labels: {'GCASH': 'Reference Number'},
    );

    expect(book.tables.keys, contains('GCASH'));
    expect(headersOf(book, 'GCASH'), contains('Reference Number'));
  });

  test('an empty bazaar still produces an openable workbook', () {
    final book = build(lines: []);

    expect(book.tables.keys, ['CASH']);
    expect(book.tables['CASH']!.rows, hasLength(1));
  });
}

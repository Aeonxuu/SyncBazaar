import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/sale.dart' show ReferenceSource;

/// One line of a bazaar's order list: a single product on a single sale.
///
/// Flat on purpose. A [Sale] in this app is already one cart line rather than a
/// whole basket, so the spreadsheet's row and the app's sale are the same
/// thing, and nothing has to be exploded on the way out.
class OrderLine {
  const OrderLine({
    required this.date,
    required this.customerName,
    required this.product,
    required this.paymentMethod,
    required this.reference,
    this.referenceSource,
    required this.quantity,
    required this.total,
    required this.returned,
  });

  final DateTime date;
  final String customerName;

  /// Product plus its variant, e.g. `Nike Air Max SC (Color Black, Size 42)`.
  final String product;

  /// Names the sheet this line lands on.
  final String paymentMethod;

  /// How [reference] arrived. Null on a sale that has none, and on any sale
  /// rung up before this was recorded.
  final ReferenceSource? referenceSource;

  /// Whatever the method's extra field asked for — a GCash reference number,
  /// a bank slip number. Empty for methods that ask for nothing, such as cash.
  final String reference;

  final int quantity;

  /// What was actually collected for this line, after any discount.
  final double total;

  final bool returned;

  /// Derived rather than stored: the app records a line total, and a discount
  /// is applied to it. Dividing back out gives the price the customer really
  /// paid per unit, which is the number that reconciles against the money in
  /// the box — not the tag price.
  double get unitPrice => quantity == 0 ? 0 : total / quantity;
}

/// Builds the workbook the venue is handed at the end of a bazaar.
///
/// One sheet per payment method, because that is how the money is counted:
/// cash is counted in the box, GCash is checked against the GCash app, and
/// nobody wants to filter a single sheet to do either. The columns therefore
/// differ per sheet — a method that asks for a reference number gets a column
/// for it, and cash does not carry an empty one.
class OrdersWorkbook {
  const OrdersWorkbook();

  /// Always present, even with nothing in it, so the workbook opens on a
  /// familiar sheet rather than on whichever method happened to be used first.
  static const String cashSheet = 'CASH';

  static const List<String> _leadingColumns = [
    'Date',
    'Customer Name',
    'Product',
  ];
  /// Header for the column qualifying the reference beside it.
  static const String referenceSourceColumn = 'Reference From';

  static const List<String> _trailingColumns = [
    'Unit Price',
    'Quantity',
    'Total',
    'Status',
  ];

  /// [extraFieldLabelByMethod] is keyed by payment method name and holds that
  /// method's configured field — `Reference Number` for GCash, and so on. A
  /// method absent from it, or mapped to a blank, gets no extra column.
  Uint8List build({
    required List<OrderLine> lines,
    required Map<String, String?> extraFieldLabelByMethod,
  }) {
    final byMethod = <String, List<OrderLine>>{};
    for (final line in lines) {
      final method = line.paymentMethod.trim().isEmpty
          ? cashSheet
          : line.paymentMethod.trim().toUpperCase();
      byMethod.putIfAbsent(method, () => []).add(line);
    }
    byMethod.putIfAbsent(cashSheet, () => []);

    // Cash first, then the rest alphabetically, so the same bazaar exported
    // twice produces the same workbook.
    final methods = byMethod.keys.toList()
      ..sort((a, b) {
        if (a == cashSheet) return -1;
        if (b == cashSheet) return 1;
        return a.compareTo(b);
      });

    final excel = Excel.createExcel();
    final placeholder = excel.getDefaultSheet();
    final usedNames = <String>{};

    for (final method in methods) {
      final sheetName = _uniqueSheetName(method, usedNames);
      final extraLabel = extraFieldLabelByMethod[method]?.trim();
      final hasExtra = extraLabel != null && extraLabel.isNotEmpty;

      final headers = [
        ..._leadingColumns,
        if (hasExtra) extraLabel,
        // Beside the reference rather than at the end, because it qualifies
        // that column and nothing else. A gateway-confirmed reference and a
        // hand-typed one are worth different amounts as evidence, and by the
        // time anyone asks, the sale is months old and nobody remembers.
        if (hasExtra) referenceSourceColumn,
        ..._trailingColumns,
      ];
      final sheet = excel[sheetName];
      sheet.appendRow([for (final header in headers) TextCellValue(header)]);

      final rows = byMethod[method]!..sort((a, b) => a.date.compareTo(b.date));
      for (final line in rows) {
        sheet.appendRow([
          TextCellValue(_formatDate(line.date)),
          TextCellValue(line.customerName),
          TextCellValue(line.product),
          if (hasExtra) TextCellValue(line.reference),
          // Blank rather than a guess where nothing was recorded.
          if (hasExtra) TextCellValue(line.referenceSource?.label ?? ''),
          DoubleCellValue(_round(line.unitPrice)),
          IntCellValue(line.quantity),
          DoubleCellValue(_round(line.total)),
          TextCellValue(line.returned ? 'Returned' : 'Completed'),
        ]);
      }

      _style(sheet, columnCount: headers.length, hasExtra: hasExtra);
    }

    // Excel's own starting sheet, which `createExcel` always makes and this
    // never writes to. Removed last: `delete` refuses to empty a workbook, so
    // it only succeeds once the real sheets exist.
    if (placeholder != null && !usedNames.contains(placeholder)) {
      excel.delete(placeholder);
    }
    excel.setDefaultSheet(cashSheet);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('The workbook could not be written.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Bold headers and columns wide enough to read without dragging. A venue's
  /// accounts clerk should not have to widen seven columns before they can
  /// check a single figure.
  void _style(Sheet sheet, {required int columnCount, required bool hasExtra}) {
    final header = CellStyle(bold: true);
    for (var column = 0; column < columnCount; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle =
          header;
    }
    sheet.setColumnWidth(0, 18); // Date
    sheet.setColumnWidth(1, 22); // Customer Name
    sheet.setColumnWidth(2, 38); // Product, the longest by far
    if (hasExtra) {
      sheet.setColumnWidth(3, 24); // The reference itself
      sheet.setColumnWidth(4, 16); // Reference From
    }
    // Two extra columns when a method has a reference, not one.
    final money = hasExtra ? 5 : 3;
    sheet.setColumnWidth(money, 12); // Unit Price
    sheet.setColumnWidth(money + 1, 10); // Quantity
    sheet.setColumnWidth(money + 2, 14); // Total
    sheet.setColumnWidth(money + 3, 12); // Status
  }

  /// Excel refuses a sheet name over 31 characters or containing `[]:*?/\`,
  /// and payment method names are typed by hand in Settings — so a venue
  /// calling one `Bank Transfer (BPI/BDO)` would produce a file that will not
  /// open at all.
  static String _uniqueSheetName(String method, Set<String> used) {
    var name = method.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (name.isEmpty) {
      name = 'OTHER';
    }
    if (name.length > 31) {
      name = name.substring(0, 31).trim();
    }
    // Truncation can collide where the full names did not.
    var candidate = name;
    var suffix = 2;
    while (used.contains(candidate)) {
      final tag = ' $suffix';
      candidate =
          '${name.substring(0, name.length.clamp(0, 31 - tag.length))}$tag';
      suffix++;
    }
    used.add(candidate);
    return candidate;
  }

  /// `2026-08-13 14:32` — sortable, unambiguous, and the same whichever
  /// locale the tablet is set to.
  static String _formatDate(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  /// Money to the centavo. Without this a derived unit price arrives as
  /// 1583.3333333333333 and prints that way in the cell.
  static double _round(double value) => (value * 100).roundToDouble() / 100;
}

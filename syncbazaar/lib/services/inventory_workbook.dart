import 'dart:typed_data';

import 'package:excel/excel.dart';

/// One row of the master inventory table, flattened for a spreadsheet.
///
/// One line per SKU rather than per product — the same grain the table
/// itself uses, so a size or colour with zero stock is still its own line
/// instead of disappearing into a product-level total.
class InventoryLine {
  const InventoryLine({
    required this.name,
    this.category,
    this.brand,
    this.attributeOne,
    this.attributeTwo,
    required this.quantity,
  });

  final String name;
  final String? category;
  final String? brand;

  /// Value from the product's first/second variant group, e.g. "Triple
  /// White" or "37". Null for a product with no variants, or fewer than
  /// two groups.
  final String? attributeOne;
  final String? attributeTwo;

  final int quantity;
}

/// Builds the master inventory export: one flat sheet, one row per SKU.
///
/// A single table rather than a workbook with several sheets — unlike the
/// orders export, there's no natural grouping (payment method) to split on
/// here, and a vendor checking stock wants one list, not several to
/// reassemble.
class InventoryWorkbook {
  const InventoryWorkbook();

  static const String sheetName = 'Inventory';

  static const List<String> _headers = [
    'Name',
    'Category',
    'Brand',
    'Attribute 1',
    'Attribute 2',
    'Quantity',
  ];

  Uint8List build(List<InventoryLine> lines) {
    final excel = Excel.createExcel();
    final placeholder = excel.getDefaultSheet();
    final sheet = excel[sheetName];

    sheet.appendRow([for (final header in _headers) TextCellValue(header)]);
    for (final line in lines) {
      sheet.appendRow([
        TextCellValue(line.name),
        TextCellValue(line.category ?? ''),
        TextCellValue(line.brand ?? ''),
        TextCellValue(line.attributeOne ?? ''),
        TextCellValue(line.attributeTwo ?? ''),
        IntCellValue(line.quantity),
      ]);
    }
    _style(sheet);

    // Excel's own starting sheet, which `createExcel` always makes and this
    // never writes to.
    if (placeholder != null && placeholder != sheetName) {
      excel.delete(placeholder);
    }
    excel.setDefaultSheet(sheetName);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('The workbook could not be written.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Bold header and columns wide enough to read without dragging.
  void _style(Sheet sheet) {
    final header = CellStyle(bold: true);
    for (var column = 0; column < _headers.length; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle =
          header;
    }
    sheet.setColumnWidth(0, 32); // Name, the longest by far
    sheet.setColumnWidth(1, 18); // Category
    sheet.setColumnWidth(2, 18); // Brand
    sheet.setColumnWidth(3, 16); // Attribute 1
    sheet.setColumnWidth(4, 16); // Attribute 2
    sheet.setColumnWidth(5, 12); // Quantity
  }
}

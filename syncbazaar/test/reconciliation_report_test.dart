import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/services/report_service.dart';

/// Reconciliation asks what a bazaar opened with, sold, and brought back.
///
/// The client cannot answer the first part: its allocations are decremented by
/// every sale, so by closing time it knows only what is left. These cover the
/// figures the server sends instead, and the arithmetic the screen leans on.
void main() {
  ReconciliationReport parse(String json) =>
      ReconciliationReport.fromJson(jsonDecode(json) as Map<String, dynamic>);

  test('reads the figures the server reports', () {
    final report = parse('''
    {"event_name": "August Fair", "allocated_stock_items": 20,
     "total_allocated_quantity": 201, "total_sold_quantity": 49,
     "total_remaining_quantity": 152, "completed_sales_records": 49}
    ''');

    expect(report.eventName, 'August Fair');
    // Combinations brought to the stall, not units.
    expect(report.allocatedStockItems, 20);
    expect(report.totalAllocatedQuantity, 201);
    expect(report.totalSoldQuantity, 49);
    expect(report.totalRemainingQuantity, 152);
    expect(report.completedSalesRecords, 49);
  });

  test('balances when sold and remaining account for the allocation', () {
    final report = parse('''
    {"event_name": "A", "allocated_stock_items": 20,
     "total_allocated_quantity": 201, "total_sold_quantity": 49,
     "total_remaining_quantity": 152, "completed_sales_records": 49}
    ''');

    expect(report.balances, isTrue);
    expect(report.discrepancy, 0);
  });

  test('reports stock that left without a sale', () {
    final report = parse('''
    {"event_name": "A", "allocated_stock_items": 20,
     "total_allocated_quantity": 201, "total_sold_quantity": 49,
     "total_remaining_quantity": 150, "completed_sales_records": 49}
    ''');

    // Two units unaccounted for. This is the whole point of reconciling: stock
    // left the bazaar and nothing recorded it going.
    expect(report.balances, isFalse);
    expect(report.discrepancy, 2);
  });

  test('a missing field reads as zero rather than throwing', () {
    // A report is closing paperwork; it should render even if the server grows
    // or drops a field, rather than taking the screen down.
    final report = parse('{"event_name": "A"}');

    expect(report.totalAllocatedQuantity, 0);
    expect(report.completedSalesRecords, 0);
    expect(report.balances, isTrue);
  });
}

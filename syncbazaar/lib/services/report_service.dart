import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';

/// What a bazaar started with, what it sold, and what came back.
///
/// Read from the server rather than counted here, because the client keeps
/// only what is *left* of an allocation — it decrements as sales happen, so
/// the opening figure is gone by the time anyone wants to reconcile against
/// it. Counting locally would report a bazaar as having been allocated
/// whatever survived the day.
class ReconciliationReport {
  const ReconciliationReport({
    required this.eventName,
    required this.allocatedStockItems,
    required this.totalAllocatedQuantity,
    required this.totalSoldQuantity,
    required this.totalRemainingQuantity,
    required this.completedSalesRecords,
  });

  final String eventName;

  /// Distinct combinations brought to the stall, not units.
  final int allocatedStockItems;

  final int totalAllocatedQuantity;
  final int totalSoldQuantity;
  final int totalRemainingQuantity;
  final int completedSalesRecords;

  /// Whether the three figures agree. They should always balance; a mismatch
  /// means stock left a bazaar without a sale recording it, which is exactly
  /// what reconciling is for.
  bool get balances =>
      totalAllocatedQuantity == totalSoldQuantity + totalRemainingQuantity;

  int get discrepancy =>
      totalAllocatedQuantity - (totalSoldQuantity + totalRemainingQuantity);

  factory ReconciliationReport.fromJson(Map<String, dynamic> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ReconciliationReport(
      eventName: json['event_name'] as String? ?? '',
      allocatedStockItems: number('allocated_stock_items'),
      totalAllocatedQuantity: number('total_allocated_quantity'),
      totalSoldQuantity: number('total_sold_quantity'),
      totalRemainingQuantity: number('total_remaining_quantity'),
      completedSalesRecords: number('completed_sales_records'),
    );
  }
}

/// The end-of-bazaar paperwork: reconciliation, and the documents that follow.
class ReportService {
  const ReportService({required AuthRepository auth}) : _auth = auth;

  final AuthRepository _auth;

  bool get isAvailable => _auth.vendorId != null;

  /// Null when there is no session, which is the in-memory build.
  Future<ReconciliationReport?> reconciliation(int eventId) async {
    if (!isAvailable) {
      return null;
    }
    final payload =
        await _auth.api.get(
              '/api/bazaar/event/$eventId/inventory-reconciliation/',
            )
            as Map<String, dynamic>;
    return ReconciliationReport.fromJson(payload);
  }
}

/// Thrown for a report that cannot be produced, with something printable.
class ReportException implements Exception {
  const ReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns an [ApiException] into a sentence about the report the user asked
/// for, rather than about HTTP.
ReportException reportFailure(ApiException error, String what) =>
    ReportException(
      error.isOffline
          ? 'Cannot reach the server, so the $what could not be prepared.'
          : 'The $what could not be prepared. ${error.message}',
    );

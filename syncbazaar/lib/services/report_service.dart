import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';
import 'document_saver.dart';
import 'orders_workbook.dart';

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
  const ReportService({
    required AuthRepository auth,
    DocumentSaver saver = const DocumentSaver(),
  }) : _auth = auth,
       _saver = saver;

  final AuthRepository _auth;
  final DocumentSaver _saver;

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

  /// Downloads the statement of account and writes it to Downloads.
  ///
  /// The server renders the document from its own template and names the file
  /// after the bazaar; both are honoured rather than rebuilt here, so the
  /// paperwork looks the same however it was produced.
  ///
  /// Returns the phrase to show the user.
  Future<String> exportStatementOfAccount({
    required int eventId,
    required String eventName,
  }) => _export(
    path: '/api/bazaar/event/$eventId/statement-of-account/',
    format: DocumentFormat.docx,
    fallbackName: 'SOA_${_slug(eventName)}',
    what: 'statement of account',
  );

  /// Downloads the list of orders as a spreadsheet-friendly CSV.
  ///
  /// Superseded for the venue's copy by [exportOrdersWorkbook], which the
  /// venue actually reconciles against; kept because a flat single-table CSV
  /// is still the easier thing to feed to another system.
  Future<String> exportListOfOrders({
    required int eventId,
    required String eventName,
  }) => _export(
    path: '/api/bazaar/event/$eventId/list-of-orders/',
    format: DocumentFormat.csv,
    fallbackName: 'ListOfOrders_${_slug(eventName)}',
    what: 'list of orders',
  );

  /// Writes the order list as an Excel workbook, one sheet per payment method.
  ///
  /// Built on the device rather than fetched, unlike every other report here.
  /// The server renders a single flat CSV, and this report is a workbook whose
  /// columns differ between sheets -- a shape a .csv cannot express at all. It
  /// therefore does not check [isAvailable]: the sales are already on the
  /// tablet, so this is the one document that can still be produced with the
  /// server unreachable.
  Future<String> exportOrdersWorkbook({
    required String eventName,
    required List<OrderLine> lines,
    required Map<String, String?> extraFieldLabelByMethod,
    OrdersWorkbook workbook = const OrdersWorkbook(),
  }) async {
    try {
      final bytes = workbook.build(
        lines: lines,
        extraFieldLabelByMethod: extraFieldLabelByMethod,
      );
      return _saver.save(
        bytes: bytes,
        fileName: 'ListOfOrders_${_slug(eventName)}',
        format: DocumentFormat.xlsx,
      );
    } on StateError {
      throw const ReportException(
        'The order list could not be written. Try again.',
      );
    }
  }

  Future<String> _export({
    required String path,
    required DocumentFormat format,
    required String fallbackName,
    required String what,
  }) async {
    if (!isAvailable) {
      throw const ReportException(
        'Sign in to export documents — they are prepared by the server.',
      );
    }
    final exportValue = format.apiValue;
    if (exportValue == null) {
      throw ReportException('The $what is not rendered by the server.');
    }
    try {
      final download = await _auth.api.getFile('$path?export=$exportValue');
      return _saver.save(
        bytes: download.bytes,
        // The server's own name, minus its extension, which file_saver adds.
        fileName: download.stem ?? fallbackName,
        format: format,
      );
    } on ApiException catch (error) {
      throw reportFailure(error, what);
    }
  }

  /// A filename-safe version of a bazaar name, for the rare case where the
  /// server does not send one.
  static String _slug(String name) =>
      name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
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

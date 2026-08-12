import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/event_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../models/sale.dart';

/// Sends completed sales to the server.
///
/// Sales are written locally first and pushed afterwards, never the other way
/// round: a till has to hand over a receipt whether or not the wifi is up, so
/// the sale is committed the moment it is rung and this runs behind it. A
/// failure here leaves the sale exactly as it was — recorded, unsynced, and
/// still on the next attempt's list.
///
/// Uploads are grouped per bazaar because the endpoint is
/// `/api/bazaar/event/<id>/batch-sale/`, and batched rather than sent one at a
/// time so a busy stall costs one request instead of one per shoe.
class SaleUploadService {
  SaleUploadService({
    required AuthRepository auth,
    required EventRepository events,
    required ProductRepository products,
    required SalesRepository sales,
  }) : _auth = auth,
       _events = events,
       _products = products,
       _sales = sales;

  final AuthRepository _auth;
  final EventRepository _events;
  final ProductRepository _products;
  final SalesRepository _sales;

  /// Payment method name to the id the API expects, fetched once.
  ///
  /// The client names a method ("CASH"); `Payment.mode_of_payment` is a foreign
  /// key. Matched case-insensitively because the names come from two seeders
  /// that disagreed on capitalisation once already.
  Map<String, int>? _paymentMethodIds;

  /// Pushes everything still unsynced, and returns how many the server now
  /// holds.
  ///
  /// Reports rather than throws for the common failures, so a caller on the
  /// checkout path can ignore the result: an unreachable server is the normal
  /// state at a bazaar, not an error worth interrupting a queue of customers
  /// for. The unsynced flag is what remembers the work.
  Future<SaleUploadResult> uploadPending() async {
    final pending = await _sales.listUnsyncedSales();
    if (pending.isEmpty) {
      return const SaleUploadResult(uploaded: 0, skipped: 0);
    }

    final Map<String, int> methodIds;
    try {
      methodIds = await _loadPaymentMethodIds();
    } on ApiException {
      return SaleUploadResult(uploaded: 0, skipped: pending.length);
    }

    final byEvent = <int, List<Sale>>{};
    for (final sale in pending) {
      byEvent.putIfAbsent(sale.eventId, () => []).add(sale);
    }

    var uploaded = 0;
    var skipped = 0;
    for (final entry in byEvent.entries) {
      final result = await _uploadEvent(entry.key, entry.value, methodIds);
      uploaded += result.uploaded;
      skipped += result.skipped;
    }
    return SaleUploadResult(uploaded: uploaded, skipped: skipped);
  }

  Future<SaleUploadResult> _uploadEvent(
    int eventId,
    List<Sale> sales,
    Map<String, int> methodIds,
  ) async {
    final payload = <Map<String, dynamic>>[];
    final sent = <String>[];
    var skipped = 0;

    for (final sale in sales) {
      final allocationKey = _products.allocationKey(
        sale.productId,
        optionIdA: sale.variantOptionIdA,
        optionIdB: sale.variantOptionIdB,
      );
      final stockId = _events.stockIdFor(
        eventId: eventId,
        allocationKey: allocationKey,
      );
      if (stockId == null) {
        // No stock row means this bazaar was never allocated that
        // combination, so the server has nothing to record the sale against.
        // Left unsynced rather than dropped: it is a real sale, and the reason
        // is worth finding rather than papering over.
        skipped++;
        continue;
      }

      payload.add({
        'client_uuid': sale.clientUuid,
        'event_stock': stockId,
        'customer_name': sale.customerName,
        'quantity': sale.qty,
        'order_status': 'CM',
        'synced': true,
        if (methodIds[sale.paymentMethod.trim().toUpperCase()] != null)
          'payment_method': methodIds[sale.paymentMethod.trim().toUpperCase()],
        if (sale.employeeId.trim().isNotEmpty)
          'required_information': sale.employeeId.trim(),
      });
      sent.add(sale.clientUuid);
    }

    if (payload.isEmpty) {
      return SaleUploadResult(uploaded: 0, skipped: skipped);
    }

    try {
      await _auth.api.post(
        '/api/bazaar/event/$eventId/batch-sale/',
        body: {'sales': payload},
      );
    } on ApiException {
      // Includes the retry case: a batch the server stored but whose response
      // was lost comes back through here, and the client uuid on every row is
      // what stops the second attempt recording them twice.
      return SaleUploadResult(uploaded: 0, skipped: skipped + sent.length);
    }

    await _sales.markSynced(sent.toSet());
    return SaleUploadResult(uploaded: sent.length, skipped: skipped);
  }

  Future<Map<String, int>> _loadPaymentMethodIds() async {
    final cached = _paymentMethodIds;
    if (cached != null) {
      return cached;
    }
    final payload = await _auth.api.get('/api/core/mode-of-payment/') as List;
    final ids = <String, int>{};
    for (final entry in payload) {
      final map = entry as Map<String, dynamic>;
      final name = (map['name'] as String?)?.trim().toUpperCase();
      final id = (map['id'] as num?)?.toInt();
      if (name != null && name.isNotEmpty && id != null) {
        ids[name] = id;
      }
    }
    _paymentMethodIds = ids;
    return ids;
  }
}

/// What one upload attempt achieved.
class SaleUploadResult {
  const SaleUploadResult({required this.uploaded, required this.skipped});

  /// Sales the server has confirmed it holds, including ones it recognised as
  /// duplicates of an earlier attempt.
  final int uploaded;

  /// Sales still waiting — no connection, or no stock row to record against.
  final int skipped;

  bool get isComplete => skipped == 0;
}

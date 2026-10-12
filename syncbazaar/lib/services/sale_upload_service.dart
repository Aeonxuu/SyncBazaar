import 'package:flutter/foundation.dart';

import '../data/remote/api_client.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/event_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../models/sale.dart';

/// One sale as the batch endpoint expects it.
///
/// Pulled out of the upload loop so the shape can be tested directly. The
/// service around it cannot reach a successful POST in a test without a server
/// issuing stock row ids, which left the actual JSON — the part a backend
/// rejects or silently drops — as the one thing never checked.
Map<String, dynamic> saleUploadPayload({
  required Sale sale,
  required int stockId,
  required Map<String, int> methodIds,
}) {
  final reference = sale.employeeId.trim();
  final source = sale.referenceSource;
  return {
    'client_uuid': sale.clientUuid,
    'event_stock': stockId,
    'customer_name': sale.customerName,
    'quantity': sale.qty,
    'order_status': 'CM',
    'synced': true,
    // Who made the sale, which is not always the account signed in: a shared
    // tablet is used by whoever is at the stall. The batch endpoint has to
    // honour this for per-employee figures to be right; until it does it still
    // credits the signed-in user and ignores the field.
    if (sale.soldById > 0) 'sold_by': sale.soldById,
    if (methodIds[sale.paymentMethod.trim().toUpperCase()] != null)
      'payment_method': methodIds[sale.paymentMethod.trim().toUpperCase()],
    if (reference.isNotEmpty) 'required_information': reference,
    // Only alongside a reference it can describe, and only when one was
    // actually recorded.
    //
    // Omitting it does not store null. The endpoint fills in MA, and that is
    // the agreed behaviour rather than an accident: the automatic path did not
    // exist until September 2026, so a sale carrying a reference and no source
    // really was typed by somebody. Recording those as manual is accurate.
    //
    // It does mean this cannot be used to say "unknown" later, if that ever
    // matters. Sending null explicitly would be the way, and the column allows
    // it; the endpoint's default is simply not it.
    if (reference.isNotEmpty && source != null)
      'required_information_source': source.wireCode,
  };
}

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
  Future<SaleUploadResult> uploadPending() {
    // One at a time. A sale triggers an upload the moment it is rung, and a
    // second trigger -- the Sync button, logging out, opening Orders -- can
    // arrive while that one is still on the wire. Run side by side they send
    // the same sales twice; the server's client uuid makes that harmless, but
    // the second would also race the first to mark them synced. Chained, the
    // second starts when the first is done and finds nothing left to send.
    final previous = _running;
    final next = (previous ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => _uploadPending());
    _running = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void>? _running;

  Future<SaleUploadResult> _uploadPending() async {
    final queued = await _sales.listUnsyncedSales();
    final here = _auth.api.baseUrl;

    // A sale belongs to the database that issued the ids it names. Offering it
    // to a different server is at best rejected and at worst accepted against
    // whatever happens to share those numbers, which is a real sale recorded
    // for the wrong product at the wrong bazaar.
    //
    // These are left in the queue rather than dropped. They are somebody's
    // records, and this is not the code that decides they are worthless; point
    // the app back at the server they came from and they upload as normal.
    final pending = <Sale>[];
    var elsewhere = 0;
    for (final sale in queued) {
      // Null means unknown, not foreign. See `Sale.originServer`: a real sale
      // queued before this was recorded is the only copy of that money.
      if (sale.originServer != null && sale.originServer != here) {
        elsewhere++;
        continue;
      }
      pending.add(sale);
    }

    if (pending.isEmpty) {
      return SaleUploadResult(uploaded: 0, skipped: 0, elsewhere: elsewhere);
    }

    final Map<String, int> methodIds;
    try {
      methodIds = await _loadPaymentMethodIds();
    } on ApiException catch (error) {
      debugPrint(
        'SaleUploadService: loading payment methods failed '
        '(${error.kind}, status ${error.statusCode}): ${error.message}',
      );
      return SaleUploadResult(
        uploaded: 0,
        skipped: pending.length,
        elsewhere: elsewhere,
      );
    }

    final byEvent = <int, List<Sale>>{};
    for (final sale in pending) {
      byEvent.putIfAbsent(sale.eventId, () => []).add(sale);
    }

    var uploaded = 0;
    var skipped = 0;
    var rejected = 0;
    String? rejectionReason;
    for (final entry in byEvent.entries) {
      final result = await _uploadEvent(entry.key, entry.value, methodIds);
      uploaded += result.uploaded;
      skipped += result.skipped;
      rejected += result.rejected;
      rejectionReason ??= result.rejectionReason;
    }
    return SaleUploadResult(
      uploaded: uploaded,
      skipped: skipped,
      elsewhere: elsewhere,
      rejected: rejected,
      rejectionReason: rejectionReason,
    );
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

      payload.add(
        saleUploadPayload(sale: sale, stockId: stockId, methodIds: methodIds),
      );
      sent.add(sale.clientUuid);
    }

    if (payload.isEmpty) {
      return SaleUploadResult(uploaded: 0, skipped: skipped);
    }

    final Object? reply;
    try {
      reply = await _auth.api.post(
        '/api/bazaar/event/$eventId/batch-sale/',
        body: {'sales': payload},
        // The client uuid on every row makes a repeat harmless.
        safeToRetry: true,
      );
    } on ApiException catch (error) {
      debugPrint(
        'SaleUploadService: batch-sale POST for event $eventId failed '
        '(${error.kind}, status ${error.statusCode}): ${error.message}',
      );

      // Includes the retry case: a batch the server stored but whose response
      // was lost comes back through here, and the client uuid on every row is
      // what stops the second attempt recording them twice.
      if (error.isOffline) {
        return SaleUploadResult(uploaded: 0, skipped: skipped + sent.length);
      }

      // The server was reached and it said no -- a 400 means the payload
      // itself was rejected, not that the connection dropped. Retrying the
      // exact same request on the next sync will not fix that on its own, so
      // this is reported apart from "skipped", which means "still waiting for
      // a connection" and nothing else. The sale stays unsynced either way:
      // this is not the code that decides it is safe to drop.
      return SaleUploadResult(
        uploaded: 0,
        skipped: skipped,
        rejected: sent.length,
        rejectionReason: error.message,
      );
    }

    await _sales.markSynced(
      sent.toSet(),
      serverIds: _serverIdsFrom(reply, sent),
    );
    return SaleUploadResult(uploaded: sent.length, skipped: skipped);
  }

  /// The server's id for each sale just uploaded.
  ///
  /// The reply lists one result per sale in the order they were sent, and a
  /// repeat of an earlier upload reports the existing sale's id the same way.
  /// A reply that does not line up with what was sent yields nothing rather
  /// than ids guessed onto the wrong sales.
  static Map<String, int> _serverIdsFrom(Object? reply, List<String> sent) {
    final results = reply is Map ? reply['batch_results'] : null;
    if (results is! List || results.length != sent.length) {
      return const {};
    }
    final ids = <String, int>{};
    for (var i = 0; i < sent.length; i++) {
      final row = results[i];
      final id = row is Map ? (row['sale_id'] as num?)?.toInt() : null;
      if (id != null) {
        ids[sent[i]] = id;
      }
    }
    return ids;
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
  const SaleUploadResult({
    required this.uploaded,
    required this.skipped,
    this.elsewhere = 0,
    this.rejected = 0,
    this.rejectionReason,
  });

  /// Sales the server has confirmed it holds, including ones it recognised as
  /// duplicates of an earlier attempt.
  final int uploaded;

  /// Sales still waiting — no connection, or no stock row to record against.
  final int skipped;

  /// Sales belonging to a different server, which this one was never offered.
  ///
  /// Counted apart from [skipped] deliberately. They are not waiting on
  /// anything here, and reporting them as pending would leave a permanent
  /// "still waiting" figure that no amount of syncing can ever clear.
  final int elsewhere;

  /// Sales the server actually answered and refused — a 4xx/5xx, not a
  /// connection failure.
  ///
  /// Also counted apart from [skipped]: that figure means "no connection yet",
  /// which invites the cashier to just try again later. A rejection is a
  /// different problem — the payload itself was refused — and saying "still
  /// waiting" about it is what turned a 400 into an overnight mystery.
  final int rejected;

  /// What the server said about the first rejection, safe to show a cashier.
  final String? rejectionReason;

  bool get isComplete => skipped == 0;
}

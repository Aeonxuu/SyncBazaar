/// What became of a sale.
///
/// There is no pending state in this business: a sale at the till is done the
/// moment it is rung up, and money has already changed hands. `pending` and
/// `incomplete` used to sit here and nothing ever produced either — the POS
/// hardcodes [completed] — so the post-bazaar report counted them forever at
/// zero. [returned] replaces them, matching the server's own `CM`/`RT` choices
/// and the `SaleReturn` it records.
enum OrderStatus { completed, returned }

/// What to call a customer who did not give a name.
const String kWalkInCustomer = 'Walk-in';

/// Normalises a typed customer name into what gets recorded and displayed.
///
/// One function rather than a check at each call site because the rule was
/// applied inconsistently and the gap was invisible: the POS tested an
/// untrimmed `isEmpty`, so a single stray space slipped past the substitution
/// and was stored as the customer's name. The transaction history then printed
/// that row with an empty customer cell — the sale was there, but nobody
/// looking for it could find it.
///
/// Applied on the way in *and* on the way out, so sales already recorded with
/// a blank name still read as [kWalkInCustomer].
String normalizeCustomerName(String? raw) {
  final trimmed = (raw ?? '').trim();
  return trimmed.isEmpty ? kWalkInCustomer : trimmed;
}

class Sale {
  const Sale({
    required this.id,
    required this.clientUuid,
    required this.eventId,
    required this.productId,
    this.variantOptionIdA,
    this.variantOptionIdB,
    required this.customerName,
    required this.employeeId,
    required this.paymentMethod,
    required this.qty,
    required this.total,
    required this.timestamp,
    required this.orderStatus,
    required this.synced,
  });

  final int id;

  /// Identity on the wire, generated at the till when the sale is rung up.
  ///
  /// Separate from [id], which only distinguishes rows in the in-memory list on
  /// this device and is built from a timestamp — two tablets can produce the
  /// same one. This is what the server dedupes on, so a batch upload whose
  /// response is lost can be re-sent without recording the sale twice.
  ///
  /// Generated at the moment of sale rather than at upload: an id minted per
  /// attempt is different on every retry, which defeats the whole mechanism.
  final String clientUuid;

  final int eventId;
  final int productId;
  final int? variantOptionIdA;
  final int? variantOptionIdB;
  final String customerName;
  final String employeeId;
  final String paymentMethod;
  final int qty;
  final double total;
  final DateTime timestamp;
  final OrderStatus orderStatus;
  final bool synced;

  Sale copyWith({OrderStatus? orderStatus, bool? synced}) {
    return Sale(
      id: id,
      // Deliberately carried through unchanged, and not exposed as a parameter:
      // a sale marked synced is the same sale, and a copy with a fresh uuid
      // would upload as a second one.
      clientUuid: clientUuid,
      eventId: eventId,
      productId: productId,
      variantOptionIdA: variantOptionIdA,
      variantOptionIdB: variantOptionIdB,
      customerName: customerName,
      employeeId: employeeId,
      paymentMethod: paymentMethod,
      qty: qty,
      total: total,
      timestamp: timestamp,
      orderStatus: orderStatus ?? this.orderStatus,
      synced: synced ?? this.synced,
    );
  }
}

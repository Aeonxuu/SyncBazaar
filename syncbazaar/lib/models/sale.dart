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
    this.soldById = 0,
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

  /// Which user rang it up, so an employee's transaction history can be
  /// narrowed to their own. Zero when unknown — a sale recorded before this
  /// was tracked, or one entered server-side.
  ///
  /// Not to be confused with [employeeId], which despite its name holds the
  /// reference a payment method asked for.
  final int soldById;

  final String employeeId;
  final String paymentMethod;
  final int qty;
  final double total;
  final DateTime timestamp;
  final OrderStatus orderStatus;
  final bool synced;

  /// Round-trips a sale through local storage.
  ///
  /// Separate from the API mappers, which translate the *server's* shape. This
  /// one has to preserve the client's own fields, `clientUuid` and `synced`
  /// above all: without the uuid the server would record a resent sale twice,
  /// and without the flag a queued sale would look already delivered.
  Map<String, dynamic> toJson() => {
    'id': id,
    'client_uuid': clientUuid,
    'event_id': eventId,
    'product_id': productId,
    'variant_option_id_a': variantOptionIdA,
    'variant_option_id_b': variantOptionIdB,
    'customer_name': customerName,
    'sold_by_id': soldById,
    'employee_id': employeeId,
    'payment_method': paymentMethod,
    'qty': qty,
    'total': total,
    'timestamp': timestamp.toIso8601String(),
    'order_status': orderStatus.name,
    'synced': synced,
  };

  /// Rebuilds a sale written by [toJson].
  ///
  /// Throws on anything it cannot read, so a corrupt row is caught by the
  /// caller and dropped rather than becoming a sale with a zero total.
  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
    id: (json['id'] as num).toInt(),
    clientUuid: json['client_uuid'] as String,
    eventId: (json['event_id'] as num).toInt(),
    productId: (json['product_id'] as num).toInt(),
    variantOptionIdA: (json['variant_option_id_a'] as num?)?.toInt(),
    variantOptionIdB: (json['variant_option_id_b'] as num?)?.toInt(),
    customerName: json['customer_name'] as String? ?? kWalkInCustomer,
    soldById: (json['sold_by_id'] as num?)?.toInt() ?? 0,
    employeeId: json['employee_id'] as String? ?? '',
    paymentMethod: json['payment_method'] as String? ?? 'CASH',
    qty: (json['qty'] as num).toInt(),
    total: (json['total'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    orderStatus: OrderStatus.values.firstWhere(
      (status) => status.name == json['order_status'],
      orElse: () => OrderStatus.completed,
    ),
    synced: json['synced'] as bool? ?? false,
  );

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
      soldById: soldById,
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

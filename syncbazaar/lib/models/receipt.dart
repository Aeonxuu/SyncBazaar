/// Everything printed on one receipt, resolved at the moment of sale.
///
/// Built from the POS cart rather than from the [Sale] rows the checkout
/// writes, because a `Sale` is one row per line item with no shared basket id,
/// no unit price and no product name — it cannot be reassembled into the
/// document a customer walks away with. `CartItem` already holds all of it, so
/// the receipt is snapshotted before the cart is cleared and nothing about the
/// persisted models has to change.
///
/// Deliberately a plain data object with no Flutter import: it is what the
/// cubit produces, what the renderer consumes, and what a test can assert on
/// without pumping a widget.
library;

/// One purchased line: a product, its variant, and what it cost.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.variantLabel,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;

  /// "Color Black, Size 42", or empty when the product has no variants.
  final String variantLabel;

  final int qty;
  final double unitPrice;
  final double lineTotal;
}

/// A `label ....... value` row in the receipt's payment block.
///
/// The unit of extension: a payment method contributes a list of these rather
/// than its own layout, so a new method can never break the document's shape.
class ReceiptDetail {
  const ReceiptDetail({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;

  /// Renders bold. For the figure the customer actually checks — change due,
  /// rather than the reference number they will never read.
  final bool emphasize;
}

class ReceiptData {
  const ReceiptData({
    required this.storeName,
    required this.venueName,
    required this.venueAddress,
    required this.venueContact,
    required this.eventName,
    required this.receiptNo,
    required this.cashierName,
    required this.customerName,
    required this.paymentMethod,
    required this.timestamp,
    required this.lines,
    required this.subtotal,
    required this.total,
    this.paymentDetails = const [],
    this.footerNote,
  });

  /// The seller — "SV KICKz". Distinct from [venueName], which is the bazaar
  /// host the stall is renting from.
  final String storeName;

  final String venueName;
  final String venueAddress;
  final String venueContact;
  final String eventName;

  /// Human-readable and sortable: `SB-260810-144233`.
  final String receiptNo;

  final String cashierName;
  final String customerName;
  final String paymentMethod;
  final DateTime timestamp;
  final List<ReceiptLine> lines;
  final double subtotal;
  final double total;

  /// Contributed by the payment method's [ReceiptPaymentSection]. Cash puts
  /// tendered and change here; a reference-based method puts its ref number.
  final List<ReceiptDetail> paymentDetails;

  final String? footerNote;

  /// Distinct products, i.e. how many lines print.
  int get itemCount => lines.length;

  /// Total pieces across all lines.
  int get unitCount => lines.fold(0, (sum, line) => sum + line.qty);

  /// Stem for the exported file — `receipt-SB-260810-144233`.
  String get fileName => 'receipt-$receiptNo';
}

import '../bloc/orders/orders_cubit.dart';
import '../models/bazaar_event.dart';
import '../models/company.dart';
import '../models/receipt.dart';
import '../models/refund.dart';

/// Gathers what a refund receipt prints, from the refund the server accepted
/// and the sale row it undoes.
///
/// No Flutter in here. What goes on the receipt is decided in one place that a
/// test can call, and the renderer only draws it.
///
/// [sale] is the Orders row the refund was started from, which already knows
/// what was sold, how many, at what price and how it was paid. [venue] and
/// [storeName] head the receipt as they head a sale's. The cashier is whoever
/// tapped refund, taken from the server's own record of it.
RefundReceiptData buildRefundReceipt({
  required Refund refund,
  required TransactionRecord sale,
  required BazaarEvent event,
  required String storeName,
  Company? venue,
}) {
  final (itemName, variantLabel) = _splitLabel(sale);
  return RefundReceiptData(
    storeName: storeName,
    venueName: venue?.name ?? '',
    venueAddress: venue?.address ?? '',
    venueContact: venue?.contact ?? '',
    eventName: event.name,
    receiptNo: refundReceiptNo(refund.createdAt),
    refundedAt: refund.createdAt,
    cashierName: refund.issuedByName,
    approvedByName: refund.authorizedByName,
    customerName: refund.customerName.isNotEmpty
        ? refund.customerName
        : sale.customerName,
    itemName: itemName,
    itemVariantLabel: variantLabel,
    qty: sale.quantity,
    unitPrice: sale.unitPrice,
    soldAt: sale.timestamp,
    soldPaymentMethod: sale.paymentMethod,
    refundAmount: refund.amount,
    refundMethod: refund.methodName.isNotEmpty
        ? refund.methodName
        : sale.paymentMethod,
    reference: refund.reference,
    reason: refund.reason,
  );
}

/// `RF-260810-144233` -- like a sale's `SB-` number but never mistakable for
/// one, and chronological.
String refundReceiptNo(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'RF-${two(at.year % 100)}${two(at.month)}${two(at.day)}'
      '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
}

/// The product and its variant as the sale receipt printed them:
/// "Nike Air Max SC" over "Color Black, Size 42".
(String, String) _splitLabel(TransactionRecord sale) {
  final label = sale.productLabel;
  final bracket = label.indexOf('(');
  if (bracket == -1) {
    return (label, '');
  }
  return (
    label.substring(0, bracket).trim(),
    label.substring(bracket + 1).replaceAll(')', '').trim(),
  );
}

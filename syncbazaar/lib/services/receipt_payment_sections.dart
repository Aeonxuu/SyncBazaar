/// What a payment method adds to a receipt, and what the POS must collect
/// before the sale can be committed.
///
/// The receipt body — store header, line items, subtotal, total — is identical
/// for every payment method. Only the block under the total differs: cash owes
/// the customer change, a wallet owes them a reference number, a coop tab owes
/// them a balance. Modelling that as a strategy keeps the alternative out of
/// the codebase: an `if (method == 'CASH') ... else if (method == 'GCASH')`
/// chain inside the renderer that every new method has to be threaded through.
///
/// Adding a method is one class plus one line in [ReceiptSectionRegistry].
library;

import '../core/utils/formatters.dart';
import '../models/receipt.dart';

/// The sale facts a section may draw on. Passed whole rather than as loose
/// arguments so a new section can use a field the existing ones ignore without
/// changing the signature every implementation shares.
class ReceiptPaymentContext {
  const ReceiptPaymentContext({
    required this.total,
    required this.paymentMethod,
    this.extraFieldLabel,
    this.extraFieldValue = '',
    this.cashTendered,
  });

  final double total;
  final String paymentMethod;

  /// The per-method label configured in settings, e.g. "GCash Ref No.".
  final String? extraFieldLabel;
  final String extraFieldValue;

  /// Only populated for methods whose section sets [
  /// ReceiptPaymentSection.requiresTendered].
  final double? cashTendered;

  double? get changeDue {
    final tendered = cashTendered;
    if (tendered == null) {
      return null;
    }
    final change = tendered - total;
    return change < 0 ? 0 : change;
  }
}

abstract class ReceiptPaymentSection {
  const ReceiptPaymentSection();

  /// Rows rendered beneath the total.
  List<ReceiptDetail> details(ReceiptPaymentContext ctx);

  /// Whether the POS must collect a numeric "amount received" before checkout.
  /// Declared here rather than checked against a method name in the UI so the
  /// screen never has to know which methods take cash.
  bool get requiresTendered => false;

  /// A closing line, e.g. terms for a credit method. Null prints nothing.
  String? footerNote(ReceiptPaymentContext ctx) => null;
}

/// Cash: the only method so far that hands money back.
class CashReceiptSection extends ReceiptPaymentSection {
  const CashReceiptSection();

  @override
  bool get requiresTendered => true;

  @override
  List<ReceiptDetail> details(ReceiptPaymentContext ctx) {
    final tendered = ctx.cashTendered;
    if (tendered == null) {
      return const [];
    }
    return [
      ReceiptDetail(label: 'Cash', value: formatPeso(tendered)),
      // Emphasised because it is the one number on the receipt the customer
      // verifies against what is in their hand.
      ReceiptDetail(
        label: 'Change',
        value: formatPeso(ctx.changeDue ?? 0),
        emphasize: true,
      ),
    ];
  }
}

/// The fallback for every method that is settled elsewhere and identified by a
/// reference — GCash, bank transfer, or any custom method an event defines.
///
/// It needs no per-method registration because [PaymentMethodMeta] already
/// carries `extraFieldLabel` and the POS already collects the matching value:
/// a new wallet added in settings prints its reference row with no code.
class ReferenceReceiptSection extends ReceiptPaymentSection {
  const ReferenceReceiptSection();

  @override
  List<ReceiptDetail> details(ReceiptPaymentContext ctx) {
    final label = ctx.extraFieldLabel?.trim();
    final value = ctx.extraFieldValue.trim();
    if (label == null || label.isEmpty || value.isEmpty) {
      return const [];
    }
    return [ReceiptDetail(label: label, value: value)];
  }
}

/// Maps a payment method name to its section.
///
/// Lookup is case- and whitespace-insensitive with a mandatory fallback, not
/// out of caution but because payment methods in this app are free text:
/// `_methodsForEvent` merges global methods with per-event custom ones, so an
/// unrecognised name is a normal input, not an error.
class ReceiptSectionRegistry {
  const ReceiptSectionRegistry._();

  static const ReceiptPaymentSection _fallback = ReferenceReceiptSection();

  static const Map<String, ReceiptPaymentSection> _byMethod = {
    'CASH': CashReceiptSection(),
  };

  static ReceiptPaymentSection resolve(String method) =>
      _byMethod[method.trim().toUpperCase()] ?? _fallback;
}

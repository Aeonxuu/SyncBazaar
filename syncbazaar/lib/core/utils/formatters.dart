import 'package:intl/intl.dart';

/// Number formatting for anything the user reads.
///
/// Eight files each declared their own `NumberFormat('#,##0.00')` and three
/// more their own `NumberFormat('#,##0')` — and the two POS screens, the
/// orders table and the post-bazaar summary skipped the formatter entirely and
/// printed `toStringAsFixed(2)`, so the same peso amount rendered as
/// `PHP 12,495.00` on the dashboard and `PHP 12495.00` at the till. A rule
/// that lives in eleven copies is a rule that will drift again.
///
/// Use these everywhere. If a number is going in front of a person, it comes
/// from this file.

final NumberFormat _amountFormat = NumberFormat('#,##0.00');
final NumberFormat _countFormat = NumberFormat('#,##0');

/// `PHP 12,495.00` — a peso amount with its currency marker.
///
/// The default for money on screen. Section 6 of DESIGN_GUIDELINES.md: every
/// peso amount gets thousands separators, because a till operator checking a
/// five-figure basket against a receipt cannot scan `12495.00`.
String formatPeso(num value) => 'PHP ${_amountFormat.format(value)}';

/// `12,495.00` — the amount alone.
///
/// For places where the currency is already stated by a column header, a
/// prefix widget, or an adjacent label.
String formatAmount(num value) => _amountFormat.format(value);

/// `12,495` — a whole number: stock counts, units, transactions.
String formatCount(num value) => _countFormat.format(value);

/// `10%`, `12.5%` — a whole percentage does not carry a decimal it does not
/// need.
///
/// Here rather than at each call site for the reason the money formats are:
/// the same rate was being written three ways across the app -- `10.0%` on the
/// venue list, `10%` in the statement of account, `10.0` in the approvals
/// table -- and a formatting rule re-implemented per file drifts.
String formatPercent(num value) {
  final text = value.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}%';
}

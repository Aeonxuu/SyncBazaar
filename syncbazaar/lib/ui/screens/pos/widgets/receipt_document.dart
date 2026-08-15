import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/receipt.dart';

/// The printable receipt, laid out as a thermal roll.
///
/// Never mounted in the app: it is rendered detached by `ReceiptService` and
/// captured straight to a PNG. Two constraints follow from that and are not
/// optional.
///
/// First, the capture runs with an **unbounded height** so the image can grow
/// with the basket, which means nothing in the outer [Column] may flex
/// vertically — no `Expanded`, `Flexible`, `Spacer` or scrollable. `Expanded`
/// inside a [Row] is fine, since width stays pinned at
/// `ReceiptService.documentWidth`.
///
/// Second, the capture wraps this in a *transparent* `Material`, so the white
/// background here is load-bearing: without it the receipt exports as dark text
/// on nothing.
///
/// Kept a pure widget over a plain [ReceiptData] so its layout can be tested
/// without a POS, a cubit or a real sale.
class ReceiptDocument extends StatelessWidget {
  const ReceiptDocument({super.key, required this.data});

  final ReceiptData data;

  /// Widest a thermal-roll receipt reads comfortably. Fixed, because the PNG
  /// must grow downward with the item count and only downward. Lives here
  /// rather than on the service so the layout owns its own geometry.
  static const double width = 380;

  static const double _pagePaddingV = 28;
  static const double _pagePaddingH = 24;

  // Measured against the rendered layout, not guessed: a receipt lays out at
  // exactly `_fixedHeight + _lineBlockHeight * lines + _detailRowHeight *
  // details`, and `receipt_capture_test.dart` fails if that stops holding.
  //
  // Getting these wrong is not cosmetic. They pick the capture's pixel ratio,
  // and an under-estimate picks a ratio too high — which is the truncation the
  // ratio exists to avoid.
  static const double _fixedHeight = 435;
  static const double _lineBlockHeight = 52;
  static const double _detailRowHeight = 20;

  /// Safety margin over the measured formula, covering a line that wraps onto
  /// a second row or a longer venue address than the base figure assumes.
  static const double _estimateMargin = 1.10;

  /// Rendered height in logical pixels, used to pick a capture pixel ratio
  /// that stays inside the GPU texture limit.
  ///
  /// Errs tall on purpose: over-estimating costs a little sharpness, while
  /// under-estimating risks losing the bottom of the receipt.
  static double estimateHeight(ReceiptData data) {
    final body =
        _fixedHeight +
        data.lines.length * _lineBlockHeight +
        data.paymentDetails.length * _detailRowHeight;

    return body * _estimateMargin;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.text) ??
        const TextStyle(color: AppColors.text);

    final customer = data.customerName.trim();

    return Container(
      width: width,
      // Load-bearing: the capture supplies a transparent Material.
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: _pagePaddingH,
        vertical: _pagePaddingV,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Store, then venue --------------------------------------
          Text(
            data.storeName.toUpperCase(),
            textAlign: TextAlign.center,
            style: base.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          if (data.venueName.trim().isNotEmpty)
            _centered(data.venueName, base, color: Colors.black54),
          if (data.venueAddress.trim().isNotEmpty)
            _centered(data.venueAddress, base),
          if (data.venueContact.trim().isNotEmpty)
            _centered(data.venueContact, base),

          const SizedBox(height: 12),
          const _DashedRule(),
          const SizedBox(height: 12),

          // ---- Transaction metadata -----------------------------------
          _MetaRow(label: 'Receipt', value: data.receiptNo, style: base),
          _MetaRow(
            label: 'Date',
            value: _timestamp(data.timestamp),
            style: base,
          ),
          if (data.eventName.trim().isNotEmpty)
            _MetaRow(label: 'Bazaar', value: data.eventName, style: base),
          _MetaRow(label: 'Cashier', value: data.cashierName, style: base),
          if (customer.isNotEmpty)
            _MetaRow(label: 'Customer', value: customer, style: base),

          const SizedBox(height: 12),
          const _DashedRule(),
          const SizedBox(height: 12),

          // ---- Line items ---------------------------------------------
          // The part that makes the PNG taller for a bigger basket.
          for (final line in data.lines) _LineBlock(line: line, style: base),

          const SizedBox(height: 2),
          const _DashedRule(),
          const SizedBox(height: 12),

          // ---- Money ---------------------------------------------------
          _AmountRow(
            label: 'Subtotal',
            value: formatPeso(data.subtotal),
            style: base,
          ),
          const SizedBox(height: 6),
          _AmountRow(
            label: 'TOTAL',
            value: formatPeso(data.total),
            style: base,
            emphasize: true,
          ),
          const SizedBox(height: 10),
          _AmountRow(
            label: 'Payment',
            value: data.paymentMethod.toUpperCase(),
            style: base,
          ),

          // ---- Whatever this payment method adds -----------------------
          for (final detail in data.paymentDetails) ...[
            const SizedBox(height: 4),
            _AmountRow(
              label: detail.label,
              value: detail.value,
              style: base,
              emphasize: detail.emphasize,
            ),
          ],

          const SizedBox(height: 12),
          const _DashedRule(),
          const SizedBox(height: 12),

          // ---- Footer ---------------------------------------------------
          _centered(
            '${formatCount(data.itemCount)} '
            '${data.itemCount == 1 ? 'item' : 'items'} · '
            '${formatCount(data.unitCount)} '
            '${data.unitCount == 1 ? 'unit' : 'units'}',
            base,
          ),
          if (data.footerNote != null &&
              data.footerNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _centered(data.footerNote!, base),
          ],
          const SizedBox(height: 10),
          Text(
            'Thank you!',
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          _centered('This serves as your proof of purchase.', base),
        ],
      ),
    );
  }

  static Widget _centered(
    String text,
    TextStyle style, {
    Color color = Colors.black45,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: style.copyWith(fontSize: 10.5, color: color, height: 1.35),
    );
  }

  static String _timestamp(DateTime value) {
    final h24 = value.hour;
    final hour = h24 % 12 == 0 ? 12 : h24 % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = h24 < 12 ? 'AM' : 'PM';
    final date =
        '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return '$date $hour:$minute $meridiem';
  }
}

/// `label            value` — label left, value right, one line.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: style.copyWith(fontSize: 10.5, color: Colors.black45),
          ),
          const SizedBox(width: 10),
          // Expanded is safe here: a Row's width is pinned even though the
          // document's height is not.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(fontSize: 10.5, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// One purchased line: name and variant, then `qty × unit` against the total.
class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line, required this.style});

  final ReceiptLine line;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final variant = line.variantLabel.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            line.name,
            style: style.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          if (variant.isNotEmpty)
            Text(
              variant,
              style: style.copyWith(
                fontSize: 10,
                color: Colors.black45,
                height: 1.3,
              ),
            ),
          const SizedBox(height: 1),
          Row(
            children: [
              Text(
                '${formatCount(line.qty)} × ${formatAmount(line.unitPrice)}',
                style: style.copyWith(fontSize: 10.5, color: Colors.black54),
              ),
              Expanded(
                child: Text(
                  formatAmount(line.lineTotal),
                  textAlign: TextAlign.right,
                  style: style.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A money row in the totals block. [emphasize] promotes it to the size and
/// weight of the grand total.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.style,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final TextStyle style;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final size = emphasize ? 13.0 : 11.0;
    final weight = emphasize ? FontWeight.w700 : FontWeight.w400;

    return Row(
      children: [
        Text(
          label,
          style: style.copyWith(
            fontSize: size,
            fontWeight: weight,
            color: emphasize ? AppColors.text : Colors.black54,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: style.copyWith(
              fontSize: size,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// A dashed rule, the receipt convention for separating sections.
///
/// Same construction as the one in the POS cart panel, copied rather than
/// imported: that one is a private widget inside a screen file, and a document
/// rendered off-screen should not depend on a screen.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 4.0;
          const gapWidth = 3.0;
          final count = (constraints.maxWidth / (dashWidth + gapWidth)).floor();
          return Row(
            children: List.generate(
              count,
              (_) => Padding(
                padding: const EdgeInsets.only(right: gapWidth),
                child: Container(
                  width: dashWidth,
                  height: 1,
                  color: Colors.black26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

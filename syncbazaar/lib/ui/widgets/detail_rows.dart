import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import 'info_hint.dart';

/// The one label style for facts: small, capitals, grey.
///
/// Every dialog that states facts about a thing uses this and nothing else, so
/// a label is recognisable as a label wherever it appears. Two or three
/// different label looks in one dialog read as a hierarchy that is not there.
class DetailLabel extends StatelessWidget {
  const DetailLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.black38,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// The width of the label column, so every value in a dialog starts at the same
/// x. Wide enough for "REFUND HANDLER" with its hint beside it.
const double kDetailLabelWidth = 152;

/// The style a value is set in. Heavier than the label's, so the eye lands on
/// the value and uses the label only to confirm what it is.
TextStyle? detailValueStyle(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.text,
    );

/// A label on the left and its value on the right, both on one baseline of
/// alignment: every row's label starts at the dialog's left edge and every
/// value at the same x beside it.
///
/// Rows are separated by hairlines the caller draws, not by boxes: the dialog is
/// the one surface, and grouping comes from spacing and rules inside it.
///
/// [hint] puts an "i" beside the label that explains it on hover or tap, for
/// the occasional row that needs a sentence. [controlHeight] is for a value
/// that is a control taller than a line of text: the label is centred on it
/// instead of sitting at the top.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.controlHeight,
    this.verticalPadding = 16,
  });

  /// A row whose value is plain text.
  DetailRow.text({
    super.key,
    required this.label,
    required String value,
    Color? valueColor,
    this.hint,
    this.verticalPadding = 16,
  }) : controlHeight = null,
       child = Builder(
         builder: (context) =>
             Text(value, style: detailValueStyle(context, color: valueColor)),
       );

  final String label;
  final Widget child;
  final String? hint;
  final double? controlHeight;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final labelCell = Row(
      children: [
        Flexible(child: DetailLabel(label)),
        if (hint != null) ...[
          const SizedBox(width: 4),
          InfoHint(message: hint!, semanticLabel: 'About $label'),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kDetailLabelWidth,
            height: controlHeight,
            // The label's own first line is shorter than the value's, so it is
            // nudged to share its middle; a taller control centres it instead.
            child: controlHeight != null
                ? Align(alignment: Alignment.centerLeft, child: labelCell)
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: labelCell,
                  ),
          ),
          Expanded(
            // At least a 24px line, so every text row is the same height and
            // the rows keep one rhythm whatever they hold.
            child: controlHeight != null
                ? child
                : ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 24),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A label over its value, for a grid of facts two to a row.
///
/// The stacked counterpart of [DetailRow], in the same label and value styles,
/// for a summary that has more to say than fits a column of rows.
class DetailFact extends StatelessWidget {
  const DetailFact(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailLabel(label),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: detailValueStyle(context),
        ),
      ],
    );
  }
}

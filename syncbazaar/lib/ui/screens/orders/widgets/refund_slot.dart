import 'package:flutter/material.dart';

import '../../../../bloc/orders/orders_cubit.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../data/repositories/refund_repository.dart';
import '../../../../models/bazaar_event.dart';
import '../../../../models/refund_access.dart';
import '../../../../models/user.dart';

/// The refund slot to the right of TOTAL. Fixed, on the header and on every
/// row, so the totals above and below a refunded sale stay in one column
/// whether the slot holds a button, a tag or nothing. Wide enough for the
/// "Refunded" tag.
const double kRefundColumnWidth = 76;

/// The refund button is square.
const double _refundButtonSize = 40;

/// What an Orders row shows in its refund slot.
///
/// A tag for a sale that has been refunded, the button for one that still can
/// be, and nothing otherwise. All the "may this person refund this sale here"
/// decisions are in one place: the sale itself ([TransactionRecord.isRefundable]),
/// the person and the bazaar ([canRefund]), and whether there is a server to
/// refund through at all.
class RefundSlot extends StatelessWidget {
  const RefundSlot({
    super.key,
    required this.record,
    required this.event,
    required this.user,
    required this.refunds,
    required this.onRefund,
  });

  final TransactionRecord record;

  /// The bazaar the sale belongs to, or null if it is not among those loaded.
  final BazaarEvent? event;
  final AppUser user;
  final RefundRepository refunds;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    if (record.refund != null) {
      return const RefundedTag();
    }
    final event = this.event;
    if (!refunds.isRemote ||
        !record.isRefundable ||
        event == null ||
        !canRefund(user, event)) {
      return const SizedBox.shrink();
    }
    return RefundButton(
      // Read on each build rather than watched: the saved-copy flag moves
      // whenever a load finishes, and the table rebuilds then anyway.
      enabled: !refunds.isOffline,
      onPressed: onRefund,
    );
  }
}

/// Marks a sale whose money has gone back to the customer.
///
/// Neutral rather than red: it is a record of something done, not a warning.
/// Small and content-sized, per the tag tier in the design guidelines.
class RefundedTag extends StatelessWidget {
  const RefundedTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Refunded',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// A square control that opens the refund dialog for its row.
///
/// Quiet at rest, like the other row actions, and neutral: refunding is
/// something an employee does on purpose after a customer asks, and a red
/// button on every row would read as a hazard rather than an option. The dialog
/// carries the weight. Offline it stays in place but dims, and its tooltip says
/// why, since the slot disappearing would leave nobody knowing refunds exist.
class RefundButton extends StatefulWidget {
  const RefundButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<RefundButton> createState() => _RefundButtonState();
}

class _RefundButtonState extends State<RefundButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.enabled ? 'Refund' : 'Refunds need a connection';
    final active = widget.enabled && _hovered;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: message,
      child: ExcludeSemantics(
        child: Tooltip(
          message: message,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: widget.enabled ? widget.onPressed : null,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: AppMotion.feedback,
                curve: AppMotion.easeOut,
                width: _refundButtonSize,
                height: _refundButtonSize,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFF2ECFC) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Icon(
                  Icons.undo_rounded,
                  size: 18,
                  color: !widget.enabled
                      ? Colors.black26
                      : (active ? AppColors.primary : Colors.black54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

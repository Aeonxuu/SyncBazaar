import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../core/utils/formatters.dart';

/// The last check before a sale is committed.
///
/// Was a bespoke dialog that repeated three problems `showConfirmationDialog`
/// had already been fixed for: **Cancel was red and Confirm was green**, so
/// the alarming colour sat on the safe choice; both buttons were equal-width
/// and full-bleed, giving "back out" the same weight as "take the money";
/// and both carried icons on a two-word decision.
///
/// It also showed nothing but a total. This is the highest-stakes moment in
/// the app — it takes payment and decrements stock — and the thing most
/// likely to be wrong at a till is not the arithmetic, it is the payment
/// method. So it now reads back what is actually being committed.
Future<bool> showConfirmSaleDialog({
  required BuildContext context,
  required double total,
  required int itemCount,
  required int unitCount,
  required String paymentMethod,
  required IconData paymentIcon,
  String? extraFieldLabel,
  String? extraFieldValue,
  String? customerName,
  double? cashTendered,
  double? changeDue,
}) async {
  final customer = (customerName ?? '').trim();
  final extraValue = (extraFieldValue ?? '').trim();

  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) {
      final theme = Theme.of(context);

      return Dialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.97, end: 1),
          duration: AppMotion.entrance,
          curve: AppMotion.easeOut,
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0, 1), child: child),
          ),
          child: ConstrainedBox(
            // 440, not the 400 a plain yes/no confirm uses: this footer
            // carries "Confirm sale" rather than "Confirm", and at 400 the
            // two buttons overflowed the body by 2px. Pinned by a test.
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_checkout_rounded,
                          size: 19,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Confirm sale',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$itemCount ${itemCount == 1 ? 'item' : 'items'} '
                              '· $unitCount ${unitCount == 1 ? 'unit' : 'units'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Amount due',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The figure the cashier reads back to the customer,
                      // so it gets the most weight on the surface.
                      Text(
                        formatPeso(total),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ConfirmSaleRow(
                        icon: paymentIcon,
                        label: 'Payment',
                        value: paymentMethod,
                      ),
                      if (extraFieldLabel != null)
                        _ConfirmSaleRow(
                          icon: Icons.tag_rounded,
                          label: extraFieldLabel,
                          value: extraValue.isEmpty ? '—' : extraValue,
                        ),
                      // Read back before committing for the same reason the
                      // payment method is: change is counted out of the till
                      // by hand, and a mistyped tendered amount is the one
                      // error the arithmetic below cannot catch.
                      if (cashTendered != null)
                        _ConfirmSaleRow(
                          icon: Icons.payments_outlined,
                          label: 'Cash received',
                          value: formatPeso(cashTendered),
                        ),
                      if (changeDue != null)
                        _ConfirmSaleRow(
                          icon: Icons.currency_exchange_rounded,
                          label: 'Change',
                          value: formatPeso(changeDue),
                        ),
                      if (customer.isNotEmpty)
                        _ConfirmSaleRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Customer',
                          value: customer,
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        // Focused on open so Enter commits and Esc backs
                        // out — at a till the keyboard is faster than the
                        // mouse, and this runs dozens of times a shift.
                        autofocus: true,
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Confirm sale'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

/// One `icon · label ......... value` line in the confirm-sale summary.
///
/// Label left, value right-aligned, so a stack of them lines up in two columns
/// and the values can be checked in one downward glance rather than read as
/// sentences.
class _ConfirmSaleRow extends StatelessWidget {
  const _ConfirmSaleRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black38),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(width: 12),
          // Expanded, and no Spacer beside it. A `Spacer` is `flex: 1` and so
          // is a bare `Flexible`, so having both split the leftover space in
          // half: the value started at the midpoint and then ran on by its own
          // width, leaving every row's right edge in a different place. One
          // tight flex child is what actually right-aligns a column of values.
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// One numbered stop in a multi-step dialog's header: a filled circle and a
/// label, purple once reached and grey ahead.
///
/// The recipe from DESIGN_GUIDELINES.md Section 7. Steps already cleared pass
/// an [onTap] to be revisited; steps ahead pass null, because moving forward is
/// what the dialog's own button gates.
class StepMarker extends StatelessWidget {
  const StepMarker({
    super.key,
    required this.number,
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = isDone || isCurrent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.small,
              curve: AppMotion.easeOut,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : Colors.black38,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: isActive ? AppColors.primary : Colors.black38,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

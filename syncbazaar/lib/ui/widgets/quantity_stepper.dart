import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// A `[ −  n  + ]` counter in a single bordered control.
///
/// One container rather than two loose icon buttons around a number: the
/// buttons and the value read as one object, and — the reason it exists — the
/// control has a **fixed width**, so a column of these lines up perfectly down
/// a list no matter how many digits each row shows. Two free-floating
/// `IconButton`s shift horizontally as the number beside them grows, which is
/// exactly the misalignment this replaces.
///
/// Each end disables itself at its limit rather than silently clamping, so
/// "you can't add any more" is visible before the tap (Nielsen: visibility of
/// system status).
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.enabled = true,
    this.width = 124,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  /// Upper bound. Null means unbounded.
  final int? max;
  final bool enabled;

  /// Fixed so a column of steppers aligns. Don't make this depend on content.
  final double width;

  @override
  Widget build(BuildContext context) {
    final canDecrease = enabled && value > min;
    final canIncrease = enabled && (max == null || value < max!);

    return SizedBox(
      width: width,
      height: 40,
      child: AnimatedContainer(
        duration: AppMotion.small,
        curve: AppMotion.easeOut,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surface : AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              tooltip: 'Decrease',
              onPressed: canDecrease ? () => onChanged(value - 1) : null,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$value',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    // A zero is "nothing allocated yet", not a real quantity —
                    // muting it lets the rows that carry stock stand out when
                    // scanning the column.
                    color: !enabled
                        ? Colors.black26
                        : value == 0
                        ? Colors.black38
                        : AppColors.text,
                  ),
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              tooltip: 'Increase',
              onPressed: canIncrease ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: double.infinity,
          child: Icon(
            icon,
            size: 17,
            color: onPressed == null ? Colors.black26 : Colors.black54,
          ),
        ),
      ),
    );
  }
}

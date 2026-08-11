import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// The app's one selection control: a flat button that communicates "picked"
/// by swapping fill colour rather than by adding a border or a check mark.
///
/// Colour rule (see `DESIGN_GUIDELINES.md` §3):
/// - unselected — flat [AppColors.primaryLight], no border, [AppColors.text]
/// - selected — flat [AppColors.accent], [AppColors.primary] label, bold
/// - disabled — the unselected fill with a `black38` label, so the option
///   stays readable even when it can't be chosen
///
/// Originally written for the POS variant picker (Color chips and Size grid);
/// lifted here so any screen needing a chip/toggle uses the same control
/// instead of growing a second visual language for the same concept.
class SelectableOptionButton extends StatefulWidget {
  const SelectableOptionButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
    this.borderRadius = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final String label;
  final bool isSelected;

  /// Dims the label without changing the fill. Pass `null` to [onTap] as well
  /// — this flag only handles the appearance.
  final bool isDisabled;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  State<SelectableOptionButton> createState() => _SelectableOptionButtonState();
}

class _SelectableOptionButtonState extends State<SelectableOptionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isSelected
        ? AppColors.accent
        : AppColors.primaryLight;
    final textColor = widget.isDisabled
        ? Colors.black38
        : (widget.isSelected ? AppColors.primary : AppColors.text);

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: widget.onTap == null
            ? null
            : (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          alignment: Alignment.center,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: AnimatedDefaultTextStyle(
            duration: AppMotion.small,
            curve: AppMotion.easeOut,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: widget.isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ) ??
                TextStyle(color: textColor),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

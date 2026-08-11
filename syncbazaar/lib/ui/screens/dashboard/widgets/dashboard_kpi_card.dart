import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';

class DashboardKpiCard extends StatefulWidget {
  const DashboardKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.iconWidget,
    this.onTap,
    this.isExpanded = false,
  });

  final String title;
  final String value;
  final IconData? icon;
  final Widget? iconWidget;

  /// When set, the whole card becomes tappable and shows a chevron
  /// affordance — used for KPIs that reveal another section on tap
  /// (e.g. Active Bazaars → Active Bazaars Summary).
  final VoidCallback? onTap;

  /// Whether the section this card controls is currently revealed.
  /// Only meaningful when [onTap] is set.
  final bool isExpanded;

  @override
  State<DashboardKpiCard> createState() => _DashboardKpiCardState();
}

class _DashboardKpiCardState extends State<DashboardKpiCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isToggle = widget.onTap != null;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: isToggle
            ? (value) => setState(() => _pressed = value)
            : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isExpanded ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Pins the label to the top inset and the value to the bottom one,
            // so whatever height the grid hands this card, the padding stays
            // 16 on all four sides and the slack lands in the gap between the
            // two — where it reads as breathing room rather than as a card
            // that is bottom-heavy with dead space.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (widget.iconWidget != null || widget.icon != null) ...[
                    SizedBox(
                      height: 20,
                      child:
                          widget.iconWidget ??
                          Icon(widget.icon, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isToggle)
                    Icon(
                      widget.isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: widget.isExpanded
                          ? AppColors.primary
                          : Colors.black38,
                    ),
                ],
              ),
              // A floor, not the gap itself: `spaceBetween` splits the tile's
              // slack around this box, so the label and value are never closer
              // than 10 apart even if the card is placed somewhere that gives
              // it no spare height at all.
              const SizedBox(height: 10),
              Text(
                widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

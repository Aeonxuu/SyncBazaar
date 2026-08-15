import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';
import '../../models/bazaar_event.dart';

/// Cycles a bazaar list through All → Upcoming → Ongoing → Ended.
///
/// One button rather than four chips: the states are mutually exclusive and
/// ordered, so a row of chips spends four slots saying what one slot can, and
/// the guidelines put a control whose job is to *filter* closer to a badge
/// than to a button.
///
/// Shared by Sales and Orders. Both pick a bazaar from the same list, and two
/// copies of a filter drift into two behaviours.
class BazaarStatusFilterButton extends StatefulWidget {
  const BazaarStatusFilterButton({
    super.key,
    required this.status,
    required this.onTap,
  });

  /// null means "All" (no filter applied).
  final BazaarStatus? status;
  final VoidCallback onTap;

  @override
  State<BazaarStatusFilterButton> createState() =>
      _BazaarStatusFilterButtonState();
}

class _BazaarStatusFilterButtonState extends State<BazaarStatusFilterButton> {
  bool _pressed = false;

  static const Map<BazaarStatus, Color> _statusColors = {
    BazaarStatus.ongoing: Color(0xFF2E7D32),
    BazaarStatus.upcoming: Color(0xFFB45309),
    BazaarStatus.ended: AppColors.error,
  };

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = status == null
        ? Colors.black54
        : (_statusColors[status] ?? AppColors.error);
    final label = switch (status) {
      null => 'All',
      BazaarStatus.upcoming => 'Upcoming',
      BazaarStatus.ongoing => 'Ongoing',
      BazaarStatus.ended => 'Ended',
    };

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: AppMotion.feedback,
      curve: AppMotion.easeOut,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: status == null
                ? Colors.black.withValues(alpha: 0.06)
                : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

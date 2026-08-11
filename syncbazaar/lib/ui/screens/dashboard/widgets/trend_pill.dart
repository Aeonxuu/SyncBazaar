import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class TrendPill extends StatelessWidget {
  const TrendPill({super.key, required this.text, required this.isPositive});

  final String text;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final fg = isPositive ? const Color(0xFF2E7D32) : AppColors.error;
    final bg = isPositive
        ? const Color(0x1A2E7D32)
        : AppColors.error.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

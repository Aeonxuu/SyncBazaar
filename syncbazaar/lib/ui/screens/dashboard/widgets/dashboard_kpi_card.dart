import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import 'trend_pill.dart';

class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.trendText,
    required this.trendIsPositive,
    this.icon,
    this.iconWidget,
  });

  final String title;
  final String value;
  final String trendText;
  final bool trendIsPositive;
  final IconData? icon;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconWidget != null || icon != null) ...[
            SizedBox(
              height: 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    iconWidget ??
                    Icon(icon, color: AppColors.primary, size: 20),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              TrendPill(text: trendText, isPositive: trendIsPositive),
            ],
          ),
        ],
      ),
    );
  }
}

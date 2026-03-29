import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import 'dashboard_section_card.dart';
import 'trend_pill.dart';

class AverageDailySalesCard extends StatelessWidget {
  const AverageDailySalesCard({
    super.key,
    required this.dailySales,
    required this.trendText,
    required this.trendIsPositive,
    this.showFilter = false,
    this.filterOptions = const [],
    this.selectedFilter,
    this.onFilterChanged,
  });

  final List<double> dailySales;
  final String trendText;
  final bool trendIsPositive;
  final bool showFilter;
  final List<String> filterOptions;
  final String? selectedFilter;
  final ValueChanged<String?>? onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Average Daily Sales',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrendPill(text: trendText, isPositive: trendIsPositive),
          if (showFilter) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: filterOptions.contains(selectedFilter)
                    ? selectedFilter
                    : (filterOptions.isNotEmpty ? filterOptions.first : null),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: onFilterChanged,
                items: filterOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 days',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 180, child: _SalesBars(dailySales: dailySales)),
        ],
      ),
    );
  }
}

class _SalesBars extends StatelessWidget {
  const _SalesBars({required this.dailySales});

  final List<double> dailySales;

  @override
  Widget build(BuildContext context) {
    final List<double> safeData = dailySales.length == 7
        ? dailySales
        : const [1200.0, 1400.0, 1300.0, 1700.0, 1500.0, 1800.0, 1600.0];
    final double maxValue = safeData.reduce(
      (double a, double b) => a > b ? a : b,
    );
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(safeData.length, (index) {
        final ratio = maxValue == 0 ? 0.0 : safeData[index] / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 120 * ratio,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C4AB6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  labels[index],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

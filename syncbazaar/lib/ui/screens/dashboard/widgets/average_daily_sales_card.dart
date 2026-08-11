import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import 'dashboard_section_card.dart';
import '../../../../core/utils/formatters.dart';

class AverageDailySalesCard extends StatelessWidget {
  const AverageDailySalesCard({
    super.key,
    required this.dailySales,
    this.chartHeight = 250,
  });

  final List<double> dailySales;

  /// Only applies when the card sizes itself — the stacked, narrow-screen
  /// layout. Beside the Analyze card the card is pinned to a fixed height and
  /// the chart is stretched to fill whatever the header leaves.
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Average Daily Sales',
      subtitle: 'This week, Monday to Friday',
      child: SizedBox(
        height: chartHeight,
        child: _SalesLineChart(dailySales: dailySales),
      ),
    );
  }
}

class _SalesLineChart extends StatelessWidget {
  const _SalesLineChart({required this.dailySales});

  final List<double> dailySales;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  /// Uniform gridline step. Axis labels must be evenly spaced in *value* as
  /// well as in pixels — an axis that jumped 0 → 5k → 10k → 20k would draw
  /// equal gaps for unequal amounts and visually misreport the data.
  static const double _yInterval = 5000;

  /// Baseline top of the axis. Grown (never clipped) when a day exceeds it,
  /// so a peak above ₱35k is still drawn truthfully instead of cut off.
  static const double _baselineMaxY = 35000;

  static const Color _gridColor = Color(0xFFECECF2);

  @override
  Widget build(BuildContext context) {
    final data = dailySales.length == _labels.length
        ? dailySales
        : List<double>.filled(_labels.length, 0);
    final dataMax = data.fold<double>(0, math.max);
    final maxY = math.max(
      _baselineMaxY,
      (dataMax / _yInterval).ceil() * _yInterval,
    );

    final axisLabelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black45,
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );

    return LineChart(
      duration: AppMotion.entrance,
      curve: AppMotion.easeOut,
      LineChartData(
        minX: 0,
        maxX: (_labels.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        // Checkered plot area: horizontal lines on every value gridline,
        // vertical lines on every weekday.
        gridData: FlGridData(
          horizontalInterval: _yInterval,
          verticalInterval: 1,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: _gridColor, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              const FlLine(color: _gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          border: const Border(
            left: BorderSide(color: _gridColor),
            bottom: BorderSide(color: _gridColor),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: _yInterval,
              reservedSize: 38,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _compactPeso(value),
                  textAlign: TextAlign.right,
                  style: axisLabelStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= _labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_labels[index], style: axisLabelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primary,
            tooltipBorderRadius: const BorderRadius.all(Radius.circular(8)),
            getTooltipItems: (spots) => spots.map((spot) {
              final label =
                  _labels[spot.x.round().clamp(0, _labels.length - 1)];
              return LineTooltipItem(
                '$label\n${formatPeso(spot.y)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            // Sharp day-to-day swings make a cubic curve bulge past the real
            // values; clamping it keeps the line from implying a peak (or a
            // dip below zero) that never happened.
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.5,
                color: Colors.white,
                strokeColor: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.28),
                  AppColors.primary.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `0`, `10k`, `70k` — keeps the left gutter narrow enough that the plot
  /// area, not the axis, gets the space in a side-by-side dashboard card.
  String _compactPeso(double value) {
    if (value == 0) return '0';
    return '${(value / 1000).round()}k';
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../services/dashboard_analytics_service.dart';
import 'dashboard_section_card.dart';
import 'trend_pill.dart';
import '../../../../core/utils/formatters.dart';

/// Descriptive analytics: the breakdowns behind the totals in the KPI row.
///
/// Replaces the old "AI analytics" card. Three things were wrong with it:
///
/// 1. **It claimed to be something it isn't.** Brain icon, "Regenerate
///    insights", thumbs up/down, and a footer asking the reader to review
///    "AI-generated content ... for inaccuracies or biases" — all wrapped
///    around counts and sums over the sales table. There is no model here, so
///    the disclaimer was false and the feedback buttons collected opinions on
///    arithmetic. The honest replacement is a provenance line: *based on N
///    recorded sales*.
/// 2. **It printed sentences.** Seven full lines with the number buried
///    mid-clause, all at one weight, in a 180px scroller. Nothing to scan.
///    Every fact is now label / value / evidence in a fixed position, so the
///    values line up in a column and the eye reads down them.
/// 3. **It restated the KPI row.** "Revenue across all bazaars" and "Today's
///    revenue" were already the two cards directly above it. This card now
///    only shows what the totals *don't*: the average behind them, what sold,
///    where, how it was paid for, and whether the orders actually closed.
///
/// Layout follows the usual descriptive-analytics ordering — one headline
/// figure, then the composition behind it, then a health indicator. Capped at
/// five figures, which sits inside the 5-7 metrics-per-view band that keeps a
/// dashboard scannable.
class AnalyzeCard extends StatelessWidget {
  const AnalyzeCard({super.key, required this.analytics});

  final DashboardAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Analyze',
      subtitle: analytics.isEmpty
          ? 'No sales recorded for ${analytics.scopeLabel} yet'
          : 'Based on ${formatCount(analytics.transactionCount)} '
                'recorded ${analytics.transactionCount == 1 ? 'sale' : 'sales'} '
                'across ${analytics.scopeLabel}',
      child: analytics.isEmpty
          ? const _EmptyState()
          : _AnalyticsBody(analytics: analytics),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.analytics});

  final DashboardAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final metrics = analytics.metrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns unless the card is genuinely narrow — a stat whose value
        // ellipsises after four characters says less than one stacked row.
        final columns = constraints.maxWidth >= 320 ? 2 : 1;
        final grid = _MetricGrid(metrics: metrics, columns: columns);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeadlineStat(
              value: analytics.averageOrderValue,
              trend: analytics.averageOrderValueTrend,
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            // The card is given a fixed height beside the sales chart. Letting
            // the grid take the slack keeps the completion strip pinned to the
            // bottom edge instead of floating mid-card, and the scroll view is
            // an overflow guard for an unusually long product name — not a
            // place content is expected to hide.
            if (constraints.maxHeight.isFinite)
              Expanded(child: SingleChildScrollView(child: grid))
            else
              grid,
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _CompletionStrip(
              completed: analytics.completedOrders,
              total: analytics.transactionCount,
              rate: analytics.completionRate,
            ),
          ],
        );
      },
    );
  }
}

/// Average order value, given the most visual weight on the card.
///
/// It earns the spot because it is the one figure a vendor can act on without
/// further arithmetic — it says whether baskets are getting bigger — and
/// because it is the only headline number on the dashboard that isn't already
/// a KPI card.
class _HeadlineStat extends StatelessWidget {
  const _HeadlineStat({required this.value, required this.trend});

  final double value;
  final double? trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = this.trend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Average order value',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                formatPeso(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  height: 1.1,
                ),
              ),
            ),
            // Shown only when the previous week actually holds transactions.
            // Against an empty baseline every change computes as "+100%",
            // which reads as a finding and is really just a lack of history.
            if (trend != null) ...[
              const SizedBox(width: 10),
              TrendPill(
                text: '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                isPositive: trend >= 0,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          trend == null
              ? 'Revenue divided by transactions'
              : 'vs. the previous 7 days',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black38),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.columns});

  final List<AnalyticsMetric> metrics;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const rowGap = 14.0;
    const columnGap = 16.0;

    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0) const SizedBox(height: rowGap),
            _MetricCell(metric: metrics[i]),
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i += columns) {
      final slice = metrics.skip(i).take(columns).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: columnGap),
              Expanded(
                child: column < slice.length
                    ? _MetricCell(metric: slice[column])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: rowGap),
          rows[i],
        ],
      ],
    );
  }
}

/// One fact, in three fixed lines: what it answers, the answer, the evidence.
///
/// No boxes or fills around the cells. They already form a grid with even
/// gutters, which is enough to read as one group (Gestalt proximity); adding
/// four tinted containers inside a card that is itself a container would be
/// two surfaces saying one thing.
class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final AnalyticsMetric metric;

  static const Map<AnalyticsMetricKind, IconData> _icons = {
    AnalyticsMetricKind.topProduct: Icons.local_fire_department_outlined,
    AnalyticsMetricKind.topVariant: Icons.straighten_outlined,
    AnalyticsMetricKind.topBazaar: Icons.storefront_outlined,
    AnalyticsMetricKind.paymentMix: Icons.payments_outlined,
    AnalyticsMetricKind.unitsSold: Icons.inventory_2_outlined,
    AnalyticsMetricKind.busiestDay: Icons.event_available_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_icons[metric.kind], size: 14, color: Colors.black38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          metric.detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black38),
        ),
      ],
    );
  }
}

/// Share of transactions that actually closed.
///
/// Kept out of the grid and given a bar because it is a different kind of
/// number: the grid says what sold, this says whether the money landed. A
/// proportion is also the one thing here that reads faster as a length than
/// as a percentage.
class _CompletionStrip extends StatelessWidget {
  const _CompletionStrip({
    required this.completed,
    required this.total,
    required this.rate,
  });

  final int completed;
  final int total;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Orders completed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${formatCount(completed)} of ${formatCount(total)}'
              '  ·  ${(rate * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: rate.clamp(0.0, 1.0)),
            duration: AppMotion.entrance,
            curve: AppMotion.easeOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: AppColors.inputFill,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the scope has no transactions.
///
/// The old card fell back to four hardcoded sentences — "₱120,450", "Sneaker
/// Model X", "62%" — which rendered as though they were this account's real
/// figures. Inventing numbers to fill a card is worse than an empty card;
/// say there is nothing yet and what will fill it.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.query_stats_outlined,
              size: 30,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing to analyze yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Breakdowns appear here once the POS\nrecords its first sale.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black45,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

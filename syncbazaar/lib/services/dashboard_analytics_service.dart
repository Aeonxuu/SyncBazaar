import 'package:intl/intl.dart';

import '../models/sale.dart';
import '../core/utils/formatters.dart';

/// Which fact a [AnalyticsMetric] states.
///
/// The service decides *what* is worth showing; the card decides how to draw
/// it. Passing a kind rather than an `IconData` keeps Material out of the
/// analytics layer, so this file stays a pure calculation that a REST backend
/// could later replace wholesale.
enum AnalyticsMetricKind {
  topProduct,
  topVariant,
  topBazaar,
  paymentMix,
  unitsSold,
  busiestDay,
}

/// One descriptive fact: a plain-language question, its answer, and the count
/// the answer rests on.
///
/// The three parts are separate fields rather than one sentence because a
/// sentence buries its number in the middle of a line. Split apart, the card
/// can put every [value] in the same place at the same weight, so the eye
/// scans a column of answers instead of reading five paragraphs.
class AnalyticsMetric {
  const AnalyticsMetric({
    required this.kind,
    required this.label,
    required this.value,
    required this.detail,
  });

  /// What the metric answers, e.g. "Best seller".
  final String label;

  /// The answer, e.g. "Nike Air Force 1 '07".
  final String value;

  /// The evidence behind it, e.g. "42 units sold".
  final String detail;

  final AnalyticsMetricKind kind;
}

/// Descriptive analytics for the dashboard: what already happened, measured
/// from recorded sales.
///
/// No forecasting, no scoring, no model — every field here is a count, a sum
/// or a ratio over [Sale] rows, which is why the card that renders it carries
/// a provenance line ("Based on N recorded transactions") instead of an
/// accuracy disclaimer.
class DashboardAnalytics {
  const DashboardAnalytics({
    required this.transactionCount,
    required this.averageOrderValue,
    required this.averageOrderValueTrend,
    required this.metrics,
    required this.completedOrders,
    required this.scopeLabel,
  });

  const DashboardAnalytics.empty({required this.scopeLabel})
    : transactionCount = 0,
      averageOrderValue = 0,
      averageOrderValueTrend = null,
      metrics = const [],
      completedOrders = 0;

  final int transactionCount;
  final double averageOrderValue;

  /// Percent change in average order value, last 7 days against the 7 before.
  ///
  /// Null when the earlier week holds no transactions. A baseline of zero
  /// makes every change "+100%", which looks like a finding and is really an
  /// artefact of having no history yet — so the card shows nothing instead.
  final double? averageOrderValueTrend;

  final List<AnalyticsMetric> metrics;
  final int completedOrders;

  /// Human-readable name for the slice being measured, e.g. "all bazaars".
  final String scopeLabel;

  bool get isEmpty => transactionCount == 0;

  /// Share of transactions that reached [OrderStatus.completed], 0-1.
  double get completionRate =>
      transactionCount == 0 ? 0 : completedOrders / transactionCount;
}

/// Computes [DashboardAnalytics] from the sales already loaded in memory.
///
/// Synchronous on purpose: this is arithmetic over a list, not I/O. It used to
/// sit behind an `abstract class` + `Future` so an AI service could be swapped
/// in; there is no AI service, and the indirection only made a sum look like a
/// network call.
class DashboardAnalyticsService {
  const DashboardAnalyticsService();

  static const String allBazaarsFilter = 'All bazaars';
  static const String employeeScopeFilter = 'My bazaars';

  /// How many metric cells the card shows. The list is built as an ordered
  /// set of candidates and trimmed to this, so a slice that can't produce one
  /// stat (no variants recorded, or a filter that makes "top bazaar" mean
  /// "the one you picked") falls through to the next useful thing rather than
  /// leaving a hole in the grid.
  static const int _metricSlots = 4;

  DashboardAnalytics compute({
    required String selectedFilter,
    required List<Sale> sales,
    required Map<int, String> eventNameById,
    required Map<int, String> productNameById,
    required Map<int, String> variantLabelByOptionId,
  }) {
    final isWholeScope =
        selectedFilter == allBazaarsFilter ||
        selectedFilter == employeeScopeFilter;
    final scopeLabel = switch (selectedFilter) {
      allBazaarsFilter => 'all bazaars',
      employeeScopeFilter => 'your bazaars',
      _ => selectedFilter,
    };

    final scoped = isWholeScope
        ? sales
        : sales
              .where((sale) => eventNameById[sale.eventId] == selectedFilter)
              .toList();

    if (scoped.isEmpty) {
      return DashboardAnalytics.empty(scopeLabel: scopeLabel);
    }

    final revenue = scoped.fold<double>(0, (sum, sale) => sum + sale.total);
    final units = scoped.fold<int>(0, (sum, sale) => sum + sale.qty);
    final completed = scoped
        .where((sale) => sale.orderStatus == OrderStatus.completed)
        .length;

    final candidates = <AnalyticsMetric?>[
      _topProduct(scoped, productNameById),
      _topVariant(scoped, variantLabelByOptionId),
      if (isWholeScope) _topBazaar(scoped, eventNameById),
      _paymentMix(scoped),
      _unitsSold(units, scoped.length),
      _busiestDay(scoped),
    ];

    return DashboardAnalytics(
      transactionCount: scoped.length,
      averageOrderValue: revenue / scoped.length,
      averageOrderValueTrend: _averageOrderValueTrend(scoped),
      metrics: candidates
          .whereType<AnalyticsMetric>()
          .take(_metricSlots)
          .toList(),
      completedOrders: completed,
      scopeLabel: scopeLabel,
    );
  }

  AnalyticsMetric? _topProduct(
    List<Sale> sales,
    Map<int, String> productNameById,
  ) {
    final unitsById = <int, int>{};
    for (final sale in sales) {
      unitsById[sale.productId] = (unitsById[sale.productId] ?? 0) + sale.qty;
    }
    if (unitsById.isEmpty) return null;

    final top = unitsById.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.topProduct,
      label: 'Best seller',
      value: productNameById[top.key] ?? 'Product #${top.key}',
      detail: '${top.value} ${_units(top.value)} sold',
    );
  }

  /// The single most-sold variant value — a size or a colourway.
  ///
  /// Worth its own cell because "which size moves" is a restocking decision a
  /// bazaar vendor makes every week, and the product-level total hides it.
  AnalyticsMetric? _topVariant(
    List<Sale> sales,
    Map<int, String> variantLabelByOptionId,
  ) {
    final unitsByOption = <int, int>{};
    for (final sale in sales) {
      for (final optionId in [sale.variantOptionIdA, sale.variantOptionIdB]) {
        if (optionId == null) continue;
        unitsByOption[optionId] = (unitsByOption[optionId] ?? 0) + sale.qty;
      }
    }
    if (unitsByOption.isEmpty) return null;

    final top = unitsByOption.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.topVariant,
      label: 'Top variant',
      value: variantLabelByOptionId[top.key] ?? 'Variant #${top.key}',
      detail: '${top.value} ${_units(top.value)} sold',
    );
  }

  AnalyticsMetric? _topBazaar(
    List<Sale> sales,
    Map<int, String> eventNameById,
  ) {
    final revenueByBazaar = <String, double>{};
    for (final sale in sales) {
      final name = eventNameById[sale.eventId] ?? 'Unknown bazaar';
      revenueByBazaar[name] = (revenueByBazaar[name] ?? 0) + sale.total;
    }
    // With one bazaar in scope this cell would restate the filter, so leave
    // the slot to the next candidate instead.
    if (revenueByBazaar.length < 2) return null;

    final top = revenueByBazaar.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.topBazaar,
      label: 'Top bazaar',
      value: top.key,
      detail: '${formatPeso(top.value)} earned',
    );
  }

  AnalyticsMetric _paymentMix(List<Sale> sales) {
    final countByMethod = <String, int>{};
    for (final sale in sales) {
      countByMethod[sale.paymentMethod] =
          (countByMethod[sale.paymentMethod] ?? 0) + 1;
    }
    final top = countByMethod.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final share = (top.value / sales.length) * 100;
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.paymentMix,
      label: 'Preferred payment',
      value: top.key,
      detail:
          '${share.toStringAsFixed(0)}% of sales (${top.value} of ${sales.length})',
    );
  }

  AnalyticsMetric _unitsSold(int units, int transactions) {
    final perOrder = units / transactions;
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.unitsSold,
      label: 'Units sold',
      value: '$units',
      detail: '${perOrder.toStringAsFixed(1)} per order',
    );
  }

  /// The weekday that earns the most, aggregated across every week in scope.
  ///
  /// A staffing and restocking cue: "Saturday brings in the most" is directly
  /// actionable in a way that a running total is not.
  AnalyticsMetric? _busiestDay(List<Sale> sales) {
    final revenueByWeekday = <int, double>{};
    for (final sale in sales) {
      final weekday = sale.timestamp.weekday;
      revenueByWeekday[weekday] = (revenueByWeekday[weekday] ?? 0) + sale.total;
    }
    if (revenueByWeekday.length < 2) return null;

    final top = revenueByWeekday.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return AnalyticsMetric(
      kind: AnalyticsMetricKind.busiestDay,
      label: 'Busiest day',
      value: DateFormat('EEEE').format(
        // Any date with the right weekday will do; 2024-01-01 was a Monday,
        // so adding weekday-1 days lands on the matching name.
        DateTime(2024, 1, 1).add(Duration(days: top.key - 1)),
      ),
      detail: '${formatPeso(top.value)} earned',
    );
  }

  double? _averageOrderValueTrend(List<Sale> sales) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));
    final previousStart = weekStart.subtract(const Duration(days: 7));

    final current = sales
        .where((sale) => !sale.timestamp.isBefore(weekStart))
        .toList();
    final previous = sales
        .where(
          (sale) =>
              !sale.timestamp.isBefore(previousStart) &&
              sale.timestamp.isBefore(weekStart),
        )
        .toList();

    if (current.isEmpty || previous.isEmpty) return null;

    final currentAov =
        current.fold<double>(0, (sum, sale) => sum + sale.total) /
        current.length;
    final previousAov =
        previous.fold<double>(0, (sum, sale) => sum + sale.total) /
        previous.length;
    if (previousAov == 0) return null;

    return ((currentAov - previousAov) / previousAov) * 100;
  }

  String _units(int count) => count == 1 ? 'unit' : 'units';
}

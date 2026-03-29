import '../models/bazaar_event.dart';
import '../models/sale.dart';
import '../models/user.dart';

class DashboardInsightsRequest {
  const DashboardInsightsRequest({
    required this.user,
    required this.selectedFilter,
    required this.events,
    required this.sales,
    required this.eventNameById,
  });

  final AppUser user;
  final String selectedFilter;
  final List<BazaarEvent> events;
  final List<Sale> sales;
  final Map<int, String> eventNameById;
}

abstract class DashboardInsightsService {
  Future<List<String>> generateInsights(DashboardInsightsRequest request);
}

class LocalDashboardInsightsService implements DashboardInsightsService {
  const LocalDashboardInsightsService();

  @override
  Future<List<String>> generateInsights(
    DashboardInsightsRequest request,
  ) async {
    final filteredSales = _filterSalesByBazaar(
      sales: request.sales,
      selectedFilter: request.selectedFilter,
      eventNameById: request.eventNameById,
    );

    if (filteredSales.isEmpty) {
      final scope = request.selectedFilter == 'All bazaars'
          ? 'all bazaars'
          : request.selectedFilter;
      return [
        'No transactions recorded for $scope yet.',
        'Record POS sales to generate richer insights.',
        'Once connected, AI API can enrich these insights automatically.',
      ];
    }

    final totalRevenue = filteredSales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );

    final completedCount = filteredSales
        .where((sale) => sale.orderStatus == OrderStatus.completed)
        .length;
    final completionRate = (completedCount / filteredSales.length) * 100;

    final paymentCounts = <String, int>{};
    for (final sale in filteredSales) {
      paymentCounts[sale.paymentMethod] =
          (paymentCounts[sale.paymentMethod] ?? 0) + 1;
    }
    final topPayment = paymentCounts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    final revenueByBazaar = <String, double>{};
    for (final sale in filteredSales) {
      final bazaar = request.eventNameById[sale.eventId] ?? 'Unknown Bazaar';
      revenueByBazaar[bazaar] = (revenueByBazaar[bazaar] ?? 0) + sale.total;
    }
    final topBazaar = revenueByBazaar.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    final now = DateTime.now();
    final todayRevenue = filteredSales
        .where(
          (sale) =>
              sale.timestamp.year == now.year &&
              sale.timestamp.month == now.month &&
              sale.timestamp.day == now.day,
        )
        .fold<double>(0, (sum, sale) => sum + sale.total);

    final scopeLabel = request.selectedFilter == 'All bazaars'
        ? 'across all bazaars'
        : 'for ${request.selectedFilter}';

    return [
      'Revenue $scopeLabel: PHP ${totalRevenue.toStringAsFixed(2)} from ${filteredSales.length} transactions.',
      'Today\'s revenue: PHP ${todayRevenue.toStringAsFixed(2)}.',
      'Most used payment method: ${topPayment.key} (${topPayment.value} transactions).',
      'Top grossing bazaar in scope: ${topBazaar.key} (PHP ${topBazaar.value.toStringAsFixed(2)}).',
      'Completion rate: ${completionRate.toStringAsFixed(1)}% ($completedCount/${filteredSales.length}).',
    ];
  }

  List<Sale> _filterSalesByBazaar({
    required List<Sale> sales,
    required String selectedFilter,
    required Map<int, String> eventNameById,
  }) {
    if (selectedFilter == 'All bazaars') {
      return sales;
    }

    return sales
        .where((sale) => eventNameById[sale.eventId] == selectedFilter)
        .toList();
  }
}

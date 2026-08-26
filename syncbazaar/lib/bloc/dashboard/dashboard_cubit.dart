import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/event_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/bazaar_event.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../services/dashboard_analytics_service.dart';
import '../../core/utils/formatters.dart';

const String _employeeScopeFilter = 'My bazaars';

class DashboardKpiData {
  const DashboardKpiData({required this.title, required this.value});

  final String title;
  final String value;
}

class BazaarSummaryData {
  const BazaarSummaryData({
    required this.bazaarName,
    required this.companyName,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  final String bazaarName;
  final String companyName;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final BazaarStatus status;
}

class CustomerHistoryData {
  const CustomerHistoryData({
    required this.timestamp,
    required this.customerName,
    required this.bazaarName,
    required this.paymentMethod,
    required this.amount,
    String? status,
  }) : _status = status;

  final DateTime timestamp;
  final String customerName;
  final String bazaarName;
  final String paymentMethod;
  final double amount;
  final String? _status;

  String get status => _status ?? 'Pending';
}

class DashboardState {
  const DashboardState({
    this.events = const [],
    List<DashboardKpiData>? kpis,
    List<BazaarSummaryData>? bazaarSummaries,
    List<double>? dailySales,
    this.analytics = const DashboardAnalytics.empty(scopeLabel: 'all bazaars'),
    List<CustomerHistoryData>? recentOrders,
    List<String>? bazaarFilterOptions,
    String? selectedBazaarFilter,
  }) : _kpis = kpis,
       _bazaarSummaries = bazaarSummaries,
       _dailySales = dailySales,
       _recentOrders = recentOrders,
       _bazaarFilterOptions = bazaarFilterOptions,
       _selectedBazaarFilter = selectedBazaarFilter;

  final List<BazaarEvent> events;
  final List<DashboardKpiData>? _kpis;
  final List<BazaarSummaryData>? _bazaarSummaries;
  final List<double>? _dailySales;

  /// Descriptive breakdowns of the same sales the KPI row totals up.
  final DashboardAnalytics analytics;
  final List<CustomerHistoryData>? _recentOrders;
  final List<String>? _bazaarFilterOptions;
  final String? _selectedBazaarFilter;

  List<DashboardKpiData> get kpis => _kpis ?? const [];
  List<BazaarSummaryData> get bazaarSummaries => _bazaarSummaries ?? const [];

  /// Mon-Fri revenue for the current week (5 values).
  List<double> get dailySales => _dailySales ?? const [0, 0, 0, 0, 0, 0, 0];
  List<CustomerHistoryData> get recentOrders => _recentOrders ?? const [];
  List<String> get bazaarFilterOptions =>
      _bazaarFilterOptions ?? const ['All bazaars'];
  String get selectedBazaarFilter => _selectedBazaarFilter ?? 'All bazaars';

  DashboardState copyWith({
    List<BazaarEvent>? events,
    List<DashboardKpiData>? kpis,
    List<BazaarSummaryData>? bazaarSummaries,
    List<double>? dailySales,
    DashboardAnalytics? analytics,
    List<CustomerHistoryData>? recentOrders,
    List<String>? bazaarFilterOptions,
    String? selectedBazaarFilter,
  }) {
    return DashboardState(
      events: events ?? this.events,
      kpis: kpis ?? this.kpis,
      bazaarSummaries: bazaarSummaries ?? this.bazaarSummaries,
      dailySales: dailySales ?? this.dailySales,
      analytics: analytics ?? this.analytics,
      recentOrders: recentOrders ?? this.recentOrders,
      bazaarFilterOptions: bazaarFilterOptions ?? this.bazaarFilterOptions,
      selectedBazaarFilter: selectedBazaarFilter ?? this.selectedBazaarFilter,
    );
  }
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(
    this._eventRepository,
    this._salesRepository, {
    required ProductRepository productRepository,
  }) : _productRepository = productRepository,
       super(const DashboardState());

  final EventRepository _eventRepository;
  final SalesRepository _salesRepository;
  final ProductRepository _productRepository;
  final DashboardAnalyticsService _analyticsService =
      const DashboardAnalyticsService();

  List<CustomerHistoryData> _allOrders = const [];
  List<Sale> _visibleSales = const [];
  Map<int, String> _eventNameById = const {};
  Map<int, String> _productNameById = const {};
  Map<int, String> _variantLabelByOptionId = const {};

  /// Goes back to the server, then rebuilds the dashboard from what it says.
  ///
  /// [load] alone re-reads what the repositories already hold, and they keep a
  /// per-vendor cache marker so they will not refetch once loaded. That is
  /// right for ordinary navigation and wrong for a pull to refresh, which
  /// showed a spinner and the same figures: a sale rung up on another device
  /// never appeared, and the sync looked broken when it was not.
  ///
  /// Ordered by dependency. The catalogue first, since an allocation is a
  /// variant id until the products are known; then bazaars; then sales, which
  /// are recorded against a bazaar's stock rows.
  ///
  /// Throws when the server cannot be reached, so the screen can say so rather
  /// than presenting stale figures as fresh ones.
  Future<void> refreshFromServer(AppUser user) async {
    await _productRepository.refresh();
    await _eventRepository.refresh();
    await _salesRepository.refresh();
    await load(user);
  }

  Future<void> load(AppUser user) async {
    final rawEvents = await _eventRepository.listVisibleForUser(user);
    final events = rawEvents;
    final summaryEvents = events
        .where((e) => e.status != BazaarStatus.ended)
        .toList();
    final summaries = _buildBazaarSummaries(summaryEvents);

    final summaryBazaarNames = summaries.map((s) => s.bazaarName).toList();
    final defaultFilter = user.isAdminOrOwner
        ? 'All bazaars'
        : _employeeScopeFilter;

    final filters = user.isAdminOrOwner
        ? <String>{'All bazaars', ...summaryBazaarNames}.toList()
        : const <String>[_employeeScopeFilter];

    final allSales = await _salesRepository.listSales();
    // Scoped to the bazaars the filter actually offers, which excludes ended
    // ones. "All bazaars" used to total every sale ever recorded while the
    // dropdown beside it listed only the live bazaars — so the aggregate was
    // larger than the sum of its own parts, and no choice in the list could
    // reproduce it. Finished bazaars are reported on in Post-Bazaar, where
    // their figures are final rather than moving.
    final eventNameById = {
      for (final event in summaryEvents) event.id: event.name,
    };
    final salesForVisibleEvents = allSales
        .where((sale) => eventNameById.containsKey(sale.eventId))
        .toList();

    _visibleSales = salesForVisibleEvents;
    _eventNameById = eventNameById;

    final products = await _productRepository.listProducts();
    _productNameById = {
      for (final product in products) product.id: product.name,
    };
    final variantLabels = <int, String>{};
    for (final product in products) {
      final options = await _productRepository.allVariantOptionsForProduct(
        product.id,
      );
      for (final option in options) {
        variantLabels[option.id] = option.value;
      }
    }
    _variantLabelByOptionId = variantLabels;

    final metrics = _metricsForFilter(
      selectedFilter: defaultFilter,
      events: events,
      sales: salesForVisibleEvents,
      eventNameById: eventNameById,
    );
    final analytics = _analyticsService.compute(
      selectedFilter: defaultFilter,
      sales: salesForVisibleEvents,
      eventNameById: eventNameById,
      productNameById: _productNameById,
      variantLabelByOptionId: _variantLabelByOptionId,
    );

    _allOrders = _buildCustomerHistoryFromSales(
      sales: salesForVisibleEvents,
      eventNameById: eventNameById,
    );

    final dailySales = _buildDailySalesForFilter(selectedFilter: defaultFilter);

    emit(
      state.copyWith(
        events: events,
        kpis: _buildKpis(
          user,
          totalRevenue: metrics.totalRevenue,
          todayRevenue: metrics.todayRevenue,
          activeBazaars: metrics.activeBazaars,
          totalOrders: metrics.totalOrders,
        ),
        bazaarSummaries: summaries,
        analytics: analytics,
        bazaarFilterOptions: filters,
        selectedBazaarFilter: defaultFilter,
        dailySales: dailySales,
        recentOrders: _applyOrderFilter(
          orders: _allOrders,
          selectedBazaarFilter: defaultFilter,
          isAdminOrOwner: user.isAdminOrOwner,
        ),
      ),
    );
  }

  void updateGlobalFilter({
    required String selectedFilter,
    required AppUser user,
  }) {
    final metrics = _metricsForFilter(
      selectedFilter: selectedFilter,
      events: state.events,
      sales: _visibleSales,
      eventNameById: _eventNameById,
    );
    final analytics = _analyticsService.compute(
      selectedFilter: selectedFilter,
      sales: _visibleSales,
      eventNameById: _eventNameById,
      productNameById: _productNameById,
      variantLabelByOptionId: _variantLabelByOptionId,
    );

    final dailySales = _buildDailySalesForFilter(
      selectedFilter: selectedFilter,
    );

    emit(
      state.copyWith(
        selectedBazaarFilter: selectedFilter,
        dailySales: dailySales,
        recentOrders: _applyOrderFilter(
          orders: _allOrders,
          selectedBazaarFilter: selectedFilter,
          isAdminOrOwner: user.isAdminOrOwner,
        ),
        kpis: _buildKpis(
          user,
          totalRevenue: metrics.totalRevenue,
          todayRevenue: metrics.todayRevenue,
          activeBazaars: metrics.activeBazaars,
          totalOrders: metrics.totalOrders,
        ),
        analytics: analytics,
      ),
    );
  }

  List<DashboardKpiData> _buildKpis(
    AppUser user, {
    required double totalRevenue,
    required double todayRevenue,
    required int activeBazaars,
    required int totalOrders,
  }) {
    final scopeSuffix = user.isAdminOrOwner ? '' : ' (My Bazaar)';
    return [
      DashboardKpiData(
        title: 'Total Sale$scopeSuffix',
        value: formatPeso(totalRevenue),
      ),
      DashboardKpiData(
        title: 'Today\'s Sale$scopeSuffix',
        value: formatPeso(todayRevenue),
      ),
      DashboardKpiData(
        title: 'Active Bazaars$scopeSuffix',
        value: '$activeBazaars',
      ),
      DashboardKpiData(
        title: 'Total Orders$scopeSuffix',
        value: '$totalOrders',
      ),
    ];
  }

  List<BazaarSummaryData> _buildBazaarSummaries(List<BazaarEvent> events) {
    final companyById = {
      1: 'Sync Traders Co.',
      2: 'Bazaar Retail Group',
      3: 'Luzon Pop-up Retail',
      4: 'Metro Weekend Markets',
    };
    final locationById = {
      1: 'Makati',
      2: 'Quezon City',
      3: 'Pasig',
      4: 'Taguig',
    };

    return events
        .map(
          (event) => BazaarSummaryData(
            bazaarName: event.name,
            companyName: companyById[event.companyId] ?? 'SyncBazaar Partner',
            location: locationById[event.companyId] ?? 'Metro Manila',
            startDate: event.startDate,
            endDate: event.endDate,
            status: event.status,
          ),
        )
        .toList();
  }

  /// Revenue for Mon-Fri of the current week, in that order (5 values).
  ///
  /// Anchored to the actual Monday rather than "the last N days" so the
  /// chart's Mon-Fri labels always line up with the data underneath them —
  /// a rolling window would silently mislabel days whenever the chart was
  /// opened on anything but a Monday.
  List<double> _buildDailySalesForFilter({required String selectedFilter}) {
    final filteredSales = _filterSalesByBazaar(
      sales: _visibleSales,
      selectedFilter: selectedFilter,
      eventNameById: _eventNameById,
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final daily = <double>[];

    // The whole week. A weekday-only chart hid the two days a pop-up bazaar
    // is most likely to be running.
    for (var offset = 0; offset < 7; offset++) {
      final day = monday.add(Duration(days: offset));
      final total = filteredSales
          .where(
            (sale) =>
                sale.timestamp.year == day.year &&
                sale.timestamp.month == day.month &&
                sale.timestamp.day == day.day,
          )
          .fold<double>(0, (sum, sale) => sum + sale.total);
      daily.add(double.parse(total.toStringAsFixed(2)));
    }

    return daily;
  }

  List<CustomerHistoryData> _buildCustomerHistoryFromSales({
    required List<Sale> sales,
    required Map<int, String> eventNameById,
  }) {
    final rows =
        sales
            .map(
              (sale) => CustomerHistoryData(
                timestamp: sale.timestamp,
                // Normalised on display too, not only when the POS records it,
                // so sales already stored with a blank name stop showing up as
                // an empty cell in the history.
                customerName: normalizeCustomerName(sale.customerName),
                bazaarName: eventNameById[sale.eventId] ?? 'Unknown Bazaar',
                paymentMethod: sale.paymentMethod,
                amount: sale.total,
                status:
                    '${sale.orderStatus.name[0].toUpperCase()}${sale.orderStatus.name.substring(1)}',
              ),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }

  List<CustomerHistoryData> _applyOrderFilter({
    required List<CustomerHistoryData> orders,
    required String selectedBazaarFilter,
    required bool isAdminOrOwner,
  }) {
    if (!isAdminOrOwner) {
      return orders;
    }
    if (selectedBazaarFilter == 'All bazaars') {
      return orders;
    }
    return orders
        .where((order) => order.bazaarName == selectedBazaarFilter)
        .toList();
  }
}

class _DashboardMetrics {
  const _DashboardMetrics({
    required this.totalRevenue,
    required this.todayRevenue,
    required this.totalOrders,
    required this.activeBazaars,
  });

  final double totalRevenue;
  final double todayRevenue;
  final int totalOrders;
  final int activeBazaars;
}

_DashboardMetrics _metricsForFilter({
  required String selectedFilter,
  required List<BazaarEvent> events,
  required List<Sale> sales,
  required Map<int, String> eventNameById,
}) {
  final filteredSales = _filterSalesByBazaar(
    sales: sales,
    selectedFilter: selectedFilter,
    eventNameById: eventNameById,
  );

  final now = DateTime.now();
  final totalRevenue = filteredSales.fold<double>(
    0,
    (sum, sale) => sum + sale.total,
  );
  final todayRevenue = filteredSales
      .where(
        (sale) =>
            sale.timestamp.year == now.year &&
            sale.timestamp.month == now.month &&
            sale.timestamp.day == now.day,
      )
      .fold<double>(0, (sum, sale) => sum + sale.total);

  return _DashboardMetrics(
    totalRevenue: totalRevenue,
    todayRevenue: todayRevenue,
    totalOrders: filteredSales.length,
    // Counted across every visible event, deliberately ignoring the bazaar
    // filter. The other three KPIs answer "how did sales go", which the filter
    // should scope; this one answers "how many bazaars are running", which it
    // should not. Scoping it meant selecting a bazaar dropped the count to 1
    // while the Active Bazaars Summary directly beneath — which never filters
    // — still listed two ongoing, so the card contradicted its own detail.
    activeBazaars: events
        .where((event) => event.status == BazaarStatus.ongoing)
        .length,
  );
}

List<Sale> _filterSalesByBazaar({
  required List<Sale> sales,
  required String selectedFilter,
  required Map<int, String> eventNameById,
}) {
  if (selectedFilter == 'All bazaars' ||
      selectedFilter == _employeeScopeFilter) {
    return sales;
  }

  return sales
      .where((sale) => eventNameById[sale.eventId] == selectedFilter)
      .toList();
}

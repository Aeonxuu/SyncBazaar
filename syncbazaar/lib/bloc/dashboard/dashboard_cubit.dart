import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/event_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/bazaar_event.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../services/dashboard_insights_service.dart';

class DashboardKpiData {
  const DashboardKpiData({
    required this.title,
    required this.value,
    required this.trendText,
    required this.trendIsPositive,
  });

  final String title;
  final String value;
  final String trendText;
  final bool trendIsPositive;
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
    this.todayRevenue = 0,
    this.totalOrders = 0,
    this.activeBazaars = 0,
    List<DashboardKpiData>? kpis,
    List<BazaarSummaryData>? bazaarSummaries,
    List<double>? dailySales,
    List<String>? aiInsights,
    List<CustomerHistoryData>? recentOrders,
    List<String>? bazaarFilterOptions,
    String? selectedBazaarFilter,
    List<String>? salesFilterOptions,
    String? selectedSalesFilter,
  }) : _kpis = kpis,
       _bazaarSummaries = bazaarSummaries,
       _dailySales = dailySales,
       _aiInsights = aiInsights,
       _recentOrders = recentOrders,
       _bazaarFilterOptions = bazaarFilterOptions,
       _selectedBazaarFilter = selectedBazaarFilter,
       _salesFilterOptions = salesFilterOptions,
       _selectedSalesFilter = selectedSalesFilter;

  final List<BazaarEvent> events;
  final double todayRevenue;
  final int totalOrders;
  final int activeBazaars;
  final List<DashboardKpiData>? _kpis;
  final List<BazaarSummaryData>? _bazaarSummaries;
  final List<double>? _dailySales;
  final List<String>? _aiInsights;
  final List<CustomerHistoryData>? _recentOrders;
  final List<String>? _bazaarFilterOptions;
  final String? _selectedBazaarFilter;
  final List<String>? _salesFilterOptions;
  final String? _selectedSalesFilter;

  List<DashboardKpiData> get kpis => _kpis ?? const [];
  List<BazaarSummaryData> get bazaarSummaries => _bazaarSummaries ?? const [];
  List<double> get dailySales =>
      _dailySales ?? const [1200, 1500, 1300, 1800, 1600, 1900, 1700];
  List<String> get aiInsights => _aiInsights ?? const [];
  List<CustomerHistoryData> get recentOrders => _recentOrders ?? const [];
  List<String> get bazaarFilterOptions =>
      _bazaarFilterOptions ?? const ['All bazaars'];
  String get selectedBazaarFilter => _selectedBazaarFilter ?? 'All bazaars';
  List<String> get salesFilterOptions =>
      _salesFilterOptions ?? const ['All bazaars'];
  String get selectedSalesFilter => _selectedSalesFilter ?? 'All bazaars';

  DashboardState copyWith({
    List<BazaarEvent>? events,
    double? todayRevenue,
    int? totalOrders,
    int? activeBazaars,
    List<DashboardKpiData>? kpis,
    List<BazaarSummaryData>? bazaarSummaries,
    List<double>? dailySales,
    List<String>? aiInsights,
    List<CustomerHistoryData>? recentOrders,
    List<String>? bazaarFilterOptions,
    String? selectedBazaarFilter,
    List<String>? salesFilterOptions,
    String? selectedSalesFilter,
  }) {
    return DashboardState(
      events: events ?? this.events,
      todayRevenue: todayRevenue ?? this.todayRevenue,
      totalOrders: totalOrders ?? this.totalOrders,
      activeBazaars: activeBazaars ?? this.activeBazaars,
      kpis: kpis ?? this.kpis,
      bazaarSummaries: bazaarSummaries ?? this.bazaarSummaries,
      dailySales: dailySales ?? this.dailySales,
      aiInsights: aiInsights ?? this.aiInsights,
      recentOrders: recentOrders ?? this.recentOrders,
      bazaarFilterOptions: bazaarFilterOptions ?? this.bazaarFilterOptions,
      selectedBazaarFilter: selectedBazaarFilter ?? this.selectedBazaarFilter,
      salesFilterOptions: salesFilterOptions ?? this.salesFilterOptions,
      selectedSalesFilter: selectedSalesFilter ?? this.selectedSalesFilter,
    );
  }
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(
    this._eventRepository,
    this._salesRepository, {
    DashboardInsightsService? insightsService,
  }) : _insightsService =
           insightsService ?? const LocalDashboardInsightsService(),
       super(const DashboardState());

  final EventRepository _eventRepository;
  final SalesRepository _salesRepository;
  final DashboardInsightsService _insightsService;

  List<CustomerHistoryData> _allOrders = const [];
  List<Sale> _visibleSales = const [];
  Map<int, String> _eventNameById = const {};

  Future<void> load(AppUser user) async {
    final rawEvents = await _eventRepository.listVisibleForUser(user);
    final events = user.role == UserRole.employee
        ? rawEvents
              .where(
                (e) =>
                    user.assignedEventId == null ||
                    e.id == user.assignedEventId,
              )
              .toList()
        : rawEvents;
    final summaryEvents = events
        .where((e) => e.status != BazaarStatus.ended)
        .toList();
    final summaries = _buildBazaarSummaries(summaryEvents);

    final summaryBazaarNames = summaries.map((s) => s.bazaarName).toList();
    final defaultFilter = user.isAdminOrOwner
        ? 'All bazaars'
        : (summaryBazaarNames.isNotEmpty
              ? summaryBazaarNames.first
              : 'My bazaar');

    final filters = user.isAdminOrOwner
        ? <String>{'All bazaars', ...summaryBazaarNames}.toList()
        : <String>[defaultFilter];

    final allSales = await _salesRepository.listSales();
    final eventNameById = {for (final event in events) event.id: event.name};
    final salesForVisibleEvents = allSales
        .where((sale) => eventNameById.containsKey(sale.eventId))
        .toList();

    _visibleSales = salesForVisibleEvents;
    _eventNameById = eventNameById;

    final metrics = _metricsForFilter(
      selectedFilter: defaultFilter,
      events: events,
      sales: salesForVisibleEvents,
      eventNameById: eventNameById,
    );
    final insights = await _insightsService.generateInsights(
      DashboardInsightsRequest(
        user: user,
        selectedFilter: defaultFilter,
        events: events,
        sales: salesForVisibleEvents,
        eventNameById: eventNameById,
      ),
    );

    _allOrders = _buildCustomerHistoryFromSales(
      sales: salesForVisibleEvents,
      eventNameById: eventNameById,
    );

    emit(
      state.copyWith(
        events: events,
        todayRevenue: metrics.todayRevenue,
        totalOrders: metrics.totalOrders,
        activeBazaars: metrics.activeBazaars,
        kpis: _buildKpis(
          user,
          totalRevenue: metrics.totalRevenue,
          todayRevenue: metrics.todayRevenue,
          activeBazaars: metrics.activeBazaars,
          totalOrders: metrics.totalOrders,
        ),
        bazaarSummaries: summaries,
        aiInsights: insights,
        bazaarFilterOptions: filters,
        selectedBazaarFilter: defaultFilter,
        salesFilterOptions: filters,
        selectedSalesFilter: defaultFilter,
        dailySales: _buildDailySalesForFilter(selectedFilter: defaultFilter),
        recentOrders: _applyOrderFilter(
          orders: _allOrders,
          selectedBazaarFilter: defaultFilter,
          isAdminOrOwner: user.isAdminOrOwner,
        ),
      ),
    );
  }

  void updateBazaarFilter({
    required String selectedFilter,
    required AppUser user,
  }) {
    emit(
      state.copyWith(
        selectedBazaarFilter: selectedFilter,
        recentOrders: _applyOrderFilter(
          orders: _allOrders,
          selectedBazaarFilter: selectedFilter,
          isAdminOrOwner: user.isAdminOrOwner,
        ),
      ),
    );
  }

  void updateSalesFilter({
    required String selectedFilter,
    required AppUser user,
  }) {
    emit(
      state.copyWith(
        selectedSalesFilter: selectedFilter,
        dailySales: _buildDailySalesForFilter(selectedFilter: selectedFilter),
      ),
    );
  }

  Future<void> updateGlobalFilter({
    required String selectedFilter,
    required AppUser user,
  }) async {
    final metrics = _metricsForFilter(
      selectedFilter: selectedFilter,
      events: state.events,
      sales: _visibleSales,
      eventNameById: _eventNameById,
    );
    final insights = await _insightsService.generateInsights(
      DashboardInsightsRequest(
        user: user,
        selectedFilter: selectedFilter,
        events: state.events,
        sales: _visibleSales,
        eventNameById: _eventNameById,
      ),
    );

    emit(
      state.copyWith(
        todayRevenue: metrics.todayRevenue,
        totalOrders: metrics.totalOrders,
        activeBazaars: metrics.activeBazaars,
        selectedBazaarFilter: selectedFilter,
        selectedSalesFilter: selectedFilter,
        dailySales: _buildDailySalesForFilter(selectedFilter: selectedFilter),
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
        aiInsights: insights,
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
        title: 'Total Revenue$scopeSuffix',
        value: 'PHP ${totalRevenue.toStringAsFixed(2)}',
        trendText: '+2.5%',
        trendIsPositive: true,
      ),
      DashboardKpiData(
        title: 'Today\'s Revenue$scopeSuffix',
        value: 'PHP ${todayRevenue.toStringAsFixed(2)}',
        trendText: '-1.2%',
        trendIsPositive: false,
      ),
      DashboardKpiData(
        title: 'Active Bazaars$scopeSuffix',
        value: '$activeBazaars',
        trendText: '+1.2%',
        trendIsPositive: true,
      ),
      DashboardKpiData(
        title: 'Total Orders$scopeSuffix',
        value: '$totalOrders',
        trendText: '+3.1%',
        trendIsPositive: true,
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

  List<double> _buildDailySalesForFilter({required String selectedFilter}) {
    final filteredSales = _filterSalesByBazaar(
      sales: _visibleSales,
      selectedFilter: selectedFilter,
      eventNameById: _eventNameById,
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daily = <double>[];

    for (var offset = 6; offset >= 0; offset--) {
      final day = today.subtract(Duration(days: offset));
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
                customerName: sale.customerName,
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

  final filteredEvents = selectedFilter == 'All bazaars'
      ? events
      : events.where((event) => event.name == selectedFilter).toList();

  return _DashboardMetrics(
    totalRevenue: totalRevenue,
    todayRevenue: todayRevenue,
    totalOrders: filteredSales.length,
    activeBazaars: filteredEvents
        .where((event) => event.status == BazaarStatus.ongoing)
        .length,
  );
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

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/dashboard/dashboard_cubit.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';

/// Two reported dashboard defects: the Active Bazaars KPI disagreeing with the
/// summary panel it expands into, and a walk-in sale that could not be found in
/// the transaction history.
void main() {
  // Sales are written to local storage as they are recorded, so these
  // need a binding and a fake store even when they never read one back.
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = AppUser(
    id: 1,
    name: 'Lalaine',
    email: 'l@example.com',
    role: UserRole.owner,
  );

  late EventRepository events;
  late SalesRepository sales;
  late ProductRepository products;
  late DashboardCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = EventRepository();
    sales = SalesRepository();
    products = ProductRepository();
    cubit = DashboardCubit(events, sales, productRepository: products);
  });

  /// Two bazaars running right now, plus one that has not started.
  Future<void> seedTwoOngoingBazaars() async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    await events.createEvent(
      name: 'Weekend Pop-Up Bazaar',
      companyId: 3,
      startDate: yesterday,
      endDate: tomorrow,
    );
    await events.createEvent(
      name: 'Midweek Office Bazaar',
      companyId: 3,
      startDate: today,
      endDate: tomorrow,
    );
    await events.createEvent(
      name: 'Back-to-School Bazaar',
      companyId: 1,
      startDate: today.add(const Duration(days: 14)),
      endDate: today.add(const Duration(days: 15)),
    );
  }

  String kpiValue(String title) =>
      cubit.state.kpis.firstWhere((k) => k.title == title).value;

  group('Active Bazaars KPI', () {
    test('counts every ongoing bazaar, not just the filtered one', () async {
      await seedTwoOngoingBazaars();
      await cubit.load(owner);

      expect(kpiValue('Active Bazaars'), '2');
    });

    test('stays consistent with the summary it expands into', () async {
      // The reported bug: filtering to one bazaar dropped the KPI to 1 while
      // the "Active Bazaars Summary" beneath it still listed two ONGOING rows.
      // "Active Bazaars" is a state-of-the-world figure, not a sales figure, so
      // narrowing the sales filter must not narrow it.
      await seedTwoOngoingBazaars();
      await cubit.load(owner);

      cubit.updateGlobalFilter(
        selectedFilter: 'Weekend Pop-Up Bazaar',
        user: owner,
      );

      expect(kpiValue('Active Bazaars'), '2');
    });

    test('sales KPIs do still narrow with the filter', () async {
      await seedTwoOngoingBazaars();
      await sales.addSale(_sale(id: 1, eventId: 1, total: 100));
      await sales.addSale(_sale(id: 2, eventId: 2, total: 250));
      await cubit.load(owner);

      expect(kpiValue('Total Orders'), '2');

      cubit.updateGlobalFilter(
        selectedFilter: 'Weekend Pop-Up Bazaar',
        user: owner,
      );

      expect(kpiValue('Total Orders'), '1');
      expect(kpiValue('Active Bazaars'), '2', reason: 'not a sales figure');
    });
  });

  group('bazaar status', () {
    test('a bazaar that opens today is ongoing, not upcoming', () async {
      // `createEvent` is handed a start date carrying the current time, which
      // is after midnight-today. Comparing those directly classified a bazaar
      // opening this morning as upcoming until tomorrow — so it was missing
      // from the Active Bazaars count on the one day it mattered most.
      final now = DateTime.now();
      await events.createEvent(
        name: 'Opens Today',
        companyId: 1,
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
      );

      final visible = await events.listVisibleForUser(owner);
      expect(visible.single.status, BazaarStatus.ongoing);
    });

    test('a bazaar ending today has not ended yet', () async {
      final now = DateTime.now();
      await events.createEvent(
        name: 'Last Day',
        companyId: 1,
        startDate: now.subtract(const Duration(days: 3)),
        endDate: DateTime(now.year, now.month, now.day),
      );

      final visible = await events.listVisibleForUser(owner);
      expect(visible.single.status, BazaarStatus.ongoing);
    });

    test('a bazaar starting tomorrow is still upcoming', () async {
      final now = DateTime.now();
      await events.createEvent(
        name: 'Next Week',
        companyId: 1,
        startDate: now.add(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 2)),
      );

      final visible = await events.listVisibleForUser(owner);
      expect(visible.single.status, BazaarStatus.upcoming);
    });
  });

  group('transaction history', () {
    test('includes a sale made with no customer name', () async {
      await seedTwoOngoingBazaars();
      await sales.addSale(_sale(id: 1, eventId: 1, total: 2300, customer: ''));
      await cubit.load(owner);

      expect(cubit.state.recentOrders, hasLength(1));
    });

    test('shows a blank customer as "Walk-in"', () async {
      await seedTwoOngoingBazaars();
      // Whitespace, not empty: the POS used an untrimmed `isEmpty` check, so a
      // stray space got past the Walk-in substitution and was recorded — and a
      // row whose customer cell renders blank is a row nobody can find.
      await sales.addSale(_sale(id: 1, eventId: 1, total: 2300, customer: ' '));
      await sales.addSale(_sale(id: 2, eventId: 1, total: 900, customer: ''));
      await cubit.load(owner);

      expect(
        cubit.state.recentOrders.map((o) => o.customerName),
        everyElement('Walk-in'),
      );
    });

    test('leaves a real customer name alone', () async {
      await seedTwoOngoingBazaars();
      await sales.addSale(
        _sale(id: 1, eventId: 1, total: 2300, customer: '  Emily  '),
      );
      await cubit.load(owner);

      expect(cubit.state.recentOrders.single.customerName, 'Emily');
    });
  });
}

Sale _sale({
  required int id,
  required int eventId,
  required double total,
  String customer = 'Emily',
}) {
  return Sale(
    id: id,
    clientUuid: 'test-sale-$id',
    eventId: eventId,
    productId: 1,
    customerName: customer,
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: total,
    timestamp: DateTime.now(),
    orderStatus: OrderStatus.completed,
    synced: false,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/dashboard/dashboard_cubit.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';

/// Pull to refresh has to reach the server.
///
/// It used to call [DashboardCubit.load], which re-reads what the repositories
/// already hold; they keep a per-vendor cache marker and will not refetch once
/// loaded. So a sale rung up on another device never appeared, and the sync
/// looked broken when it was not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = AppUser(
    id: 1,
    name: 'Lalaine',
    email: 'l@example.com',
    role: UserRole.owner,
  );

  late EventRepository events;
  late SalesRepository sales;
  late DashboardCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = EventRepository();
    sales = SalesRepository();
    cubit = DashboardCubit(
      events,
      sales,
      productRepository: ProductRepository(),
    );
  });

  final now = DateTime.now();

  Sale saleFor(int eventId, {required int id, required double total}) => Sale(
    id: id,
    clientUuid: 'uuid-$id',
    eventId: eventId,
    productId: 1,
    customerName: 'Walk-in',
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: total,
    timestamp: now,
    orderStatus: OrderStatus.completed,
    synced: true,
  );

  test('a refresh picks up a sale added since the last load', () async {
    final event = await events.createEvent(
      name: 'Live',
      companyId: 1,
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(event.id, id: 1, total: 500));
    await cubit.load(owner);
    expect(cubit.state.recentOrders, hasLength(1));

    // Stands in for a sale rung up on the other device.
    await sales.addSale(saleFor(event.id, id: 2, total: 1200));

    await cubit.refreshFromServer(owner);

    expect(
      cubit.state.recentOrders,
      hasLength(2),
      reason: 'the refresh did not pick up the newer sale',
    );
  });

  test('a refresh leaves the figures right, not just longer', () async {
    final event = await events.createEvent(
      name: 'Live',
      companyId: 1,
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(event.id, id: 1, total: 500));
    await cubit.load(owner);

    await sales.addSale(saleFor(event.id, id: 2, total: 1200));
    await cubit.refreshFromServer(owner);

    final total = cubit.state.kpis
        .firstWhere((k) => k.title.startsWith('Total Sale'))
        .value;
    expect(total, 'PHP 1,700.00');
  });

  test('a refresh with nothing new changes nothing', () async {
    final event = await events.createEvent(
      name: 'Live',
      companyId: 1,
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(event.id, id: 1, total: 500));
    await cubit.load(owner);
    final before = cubit.state.recentOrders.length;

    await cubit.refreshFromServer(owner);

    expect(cubit.state.recentOrders, hasLength(before));
  });
}

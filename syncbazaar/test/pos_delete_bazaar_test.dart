import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/pos/pos_cubit.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/orders_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';

/// Which bazaars may be deleted.
///
/// A bazaar that has taken money is a financial record and a finished one is
/// history; only one that was set up and never traded against is safely just a
/// plan. The server enforces the sales half and answers 409, but the till
/// should say so before the attempt rather than after it fails.
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
  late PosCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = EventRepository();
    sales = SalesRepository();
    cubit = PosCubit(
      events,
      ProductRepository(),
      sales,
      OrdersRepository(),
      SettingsRepository(),
    );
  });

  final now = DateTime.now();

  Future<BazaarEvent> makeEvent({
    required String name,
    required DateTime start,
    required DateTime end,
  }) => events.createEvent(
    name: name,
    companyId: 1,
    startDate: start,
    endDate: end,
  );

  Sale saleFor(int eventId) => Sale(
    id: eventId * 100,
    clientUuid: 'test-uuid-$eventId',
    eventId: eventId,
    productId: 1,
    customerName: 'Walk-in',
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: 500,
    timestamp: now,
    orderStatus: OrderStatus.completed,
    synced: false,
  );

  BazaarEvent found(String name) =>
      cubit.state.events.firstWhere((e) => e.name == name);

  test('a bazaar with no sales can be deleted', () async {
    await makeEvent(
      name: 'Fresh',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await cubit.load(owner);

    expect(cubit.state.canDeleteEvent(found('Fresh')), isTrue);
    expect(cubit.state.deleteBlockedReason(found('Fresh')), isNull);
  });

  test('a bazaar that has taken money cannot be deleted', () async {
    final event = await makeEvent(
      name: 'Traded',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(event.id));
    await cubit.load(owner);

    expect(cubit.state.canDeleteEvent(found('Traded')), isFalse);
    expect(
      cubit.state.deleteBlockedReason(found('Traded')),
      contains('recorded sales'),
    );
  });

  test('a finished bazaar is kept even with no sales', () async {
    await makeEvent(
      name: 'Finished',
      start: now.subtract(const Duration(days: 9)),
      end: now.subtract(const Duration(days: 3)),
    );
    await cubit.load(owner);

    final event = found('Finished');
    expect(event.status, BazaarStatus.ended);
    expect(cubit.state.canDeleteEvent(event), isFalse);
    expect(cubit.state.deleteBlockedReason(event), contains('finished'));
  });

  test('an upcoming bazaar nobody has used can be deleted', () async {
    await makeEvent(
      name: 'Planned',
      start: now.add(const Duration(days: 5)),
      end: now.add(const Duration(days: 6)),
    );
    await cubit.load(owner);

    expect(found('Planned').status, BazaarStatus.upcoming);
    expect(cubit.state.canDeleteEvent(found('Planned')), isTrue);
  });

  test('sales against one bazaar do not protect another', () async {
    final traded = await makeEvent(
      name: 'Traded',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await makeEvent(
      name: 'Untouched',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(traded.id));
    await cubit.load(owner);

    expect(cubit.state.canDeleteEvent(found('Traded')), isFalse);
    expect(cubit.state.canDeleteEvent(found('Untouched')), isTrue);
  });

  test('deleting a protected bazaar is refused, not just hidden', () async {
    // The rule has to hold in the cubit as well as on the button: a guard that
    // only the UI applies is one bypass away from deleting a sales record.
    final event = await makeEvent(
      name: 'Traded',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await sales.addSale(saleFor(event.id));
    await cubit.load(owner);

    expect(
      () => cubit.deleteEventFromPos(user: owner, event: found('Traded')),
      throwsA(isA<StateError>()),
    );
  });

  test('an allowed delete removes it from the list', () async {
    await makeEvent(
      name: 'Fresh',
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );
    await cubit.load(owner);

    await cubit.deleteEventFromPos(user: owner, event: found('Fresh'));

    expect(cubit.state.events.any((e) => e.name == 'Fresh'), isFalse);
  });
}

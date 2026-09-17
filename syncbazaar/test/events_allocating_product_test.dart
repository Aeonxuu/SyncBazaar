import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';

/// Which bazaars would lose stock if a product were deleted.
///
/// The server cascades a product delete through its bazaar allocations and
/// says nothing; only a recorded sale stops it. The delete confirmation names
/// these bazaars before the tap, because afterwards there is nothing left to
/// warn about.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late EventRepository events;

  setUp(() async {
    events = EventRepository();
    await events.createEvent(
      name: 'August Fair',
      companyId: 1,
      startDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 7),
      allocationsByAllocationKey: {'16:10:7': 5, '17:0:0': 0},
    );
    await events.createEvent(
      name: 'Freshmen Week',
      companyId: 1,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 3),
      allocationsByAllocationKey: {'16:11:7': 2},
    );
  });

  test('names every bazaar holding stock of the product', () async {
    final names = (await events.eventsAllocating(16)).map((e) => e.name);

    expect(names, containsAll(['August Fair', 'Freshmen Week']));
  });

  test('a zero allocation does not count', () async {
    // Allocated in name only. Nothing would be lost, so nothing to warn about.
    expect(await events.eventsAllocating(17), isEmpty);
  });

  test('a product nobody allocated is clear', () async {
    expect(await events.eventsAllocating(99), isEmpty);
  });

  test('matches the product id exactly, not as a prefix', () async {
    // Product 1 must not pick up product 16 or 17.
    expect(await events.eventsAllocating(1), isEmpty);
  });
}

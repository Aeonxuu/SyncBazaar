import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';

/// A bazaar sells from its own allocation, never from the master inventory.
///
/// Stock leaves the warehouse at the moment it is allocated to a bazaar — the
/// shoes are physically at that stall — so the two figures are different and
/// only the allocation is standing on the table. The POS used to read and
/// deduct from the master inventory instead, which offered a cashier sizes
/// that were never brought and counted every sale against the warehouse twice.
void main() {
  Future<EventRepository> repositoryWith(Map<String, int> allocations) async {
    final repository = EventRepository();
    await repository.createEvent(
      name: 'Test Bazaar',
      companyId: 1,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 3),
      allocationsByAllocationKey: allocations,
    );
    return repository;
  }

  test('a sale comes off the bazaar allocation', () async {
    final repository = await repositoryWith({'1:2:3': 5});

    final ok = await repository.consumeAllocation(
      eventId: 1,
      allocationKey: '1:2:3',
      quantity: 2,
    );

    expect(ok, isTrue);
    final remaining = await repository.allocationsForEventByAllocationKey(1);
    expect(remaining['1:2:3'], 3);
  });

  test('refuses to sell more than the stall was given', () async {
    final repository = await repositoryWith({'1:2:3': 2});

    final ok = await repository.consumeAllocation(
      eventId: 1,
      allocationKey: '1:2:3',
      quantity: 3,
    );

    // Refused, and nothing moved -- a partial deduction would leave the stall
    // short by the difference with no record of why.
    expect(ok, isFalse);
    final remaining = await repository.allocationsForEventByAllocationKey(1);
    expect(remaining['1:2:3'], 2);
  });

  test('refuses a combination this bazaar was never given', () async {
    final repository = await repositoryWith({'1:2:3': 5});

    // The size exists in the master inventory but was not brought here.
    final ok = await repository.consumeAllocation(
      eventId: 1,
      allocationKey: '1:2:9',
      quantity: 1,
    );

    expect(ok, isFalse);
  });

  test('one bazaar selling does not touch another', () async {
    final repository = await repositoryWith({'1:2:3': 5});
    await repository.createEvent(
      name: 'Other Bazaar',
      companyId: 1,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 3),
      allocationsByAllocationKey: {'1:2:3': 5},
    );

    await repository.consumeAllocation(
      eventId: 1,
      allocationKey: '1:2:3',
      quantity: 4,
    );

    expect(
      (await repository.allocationsForEventByAllocationKey(2))['1:2:3'],
      5,
      reason: 'each stall owns its own stock',
    );
  });

  test('a failed sale puts the units back', () async {
    final repository = await repositoryWith({'1:2:3': 5});

    await repository.consumeAllocation(
      eventId: 1,
      allocationKey: '1:2:3',
      quantity: 2,
    );
    await repository.restoreAllocation(
      eventId: 1,
      allocationKey: '1:2:3',
      quantity: 2,
    );

    final remaining = await repository.allocationsForEventByAllocationKey(1);
    expect(remaining['1:2:3'], 5);
  });
}

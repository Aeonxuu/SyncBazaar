import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/user.dart';
import 'package:syncbazaar/services/staff_scheduling.dart';

/// One person cannot stand at two stalls.
///
/// Nothing enforced this: the server's only rule is that the same person
/// cannot be added to the same bazaar twice, which says nothing about two
/// bazaars on the same weekend in different malls. An employee double-booked
/// that way is not stretched thin, they are absent from one of them, and
/// nobody finds out until the morning it opens.
void main() {
  DateTimeRange range(int startDay, int endDay) => DateTimeRange(
    start: DateTime(2026, 8, startDay),
    end: DateTime(2026, 8, endDay),
  );

  BazaarEvent event(int id, String name, int startDay, int endDay) =>
      BazaarEvent(
        id: id,
        name: name,
        companyId: 1,
        startDate: DateTime(2026, 8, startDay),
        endDate: DateTime(2026, 8, endDay),
        status: BazaarStatus.upcoming,
      );

  AppUser employee(int id, String name, List<int> assigned) => AppUser(
    id: id,
    name: name,
    email: '$name@syncbazaar.com',
    role: UserRole.employee,
    assignedEventIds: assigned,
  );

  final eventsById = {
    1: event(1, 'August Fair', 10, 14),
    2: event(2, 'Payday Pop-Up', 20, 22),
    3: event(3, 'One Day Only', 16, 16),
  };

  group('overlap', () {
    test('bazaars on the same days clash', () {
      expect(StaffScheduling.overlaps(range(10, 14), range(12, 16)), isTrue);
    });

    test('bazaars on separate weeks do not', () {
      expect(StaffScheduling.overlaps(range(10, 14), range(20, 22)), isFalse);
    });

    test('one ending the day another starts is a clash', () {
      // One person, two venues, one morning.
      expect(StaffScheduling.overlaps(range(10, 14), range(14, 18)), isTrue);
    });

    test('back-to-back days do not clash', () {
      expect(StaffScheduling.overlaps(range(10, 14), range(15, 18)), isFalse);
    });

    test('a bazaar entirely inside another clashes', () {
      expect(StaffScheduling.overlaps(range(10, 20), range(12, 14)), isTrue);
    });

    test('the time of day is ignored', () {
      // Dates are days. Two stalls open on the 16th clash whether or not the
      // stored times happen to cross.
      final morning = DateTimeRange(
        start: DateTime(2026, 8, 16, 8),
        end: DateTime(2026, 8, 16, 11),
      );
      final afternoon = DateTimeRange(
        start: DateTime(2026, 8, 16, 14),
        end: DateTime(2026, 8, 16, 18),
      );

      expect(StaffScheduling.overlaps(morning, afternoon), isTrue);
    });
  });

  group('conflicts', () {
    test('names the bazaar someone is already committed to', () {
      final clashes = StaffScheduling.conflicts(
        range: range(12, 16),
        employees: [
          employee(3, 'Via', [1]),
        ],
        eventsById: eventsById,
      );

      expect(clashes[3], 'August Fair');
    });

    test('an employee free that week is not listed', () {
      final clashes = StaffScheduling.conflicts(
        range: range(12, 16),
        employees: [
          employee(3, 'Via', [2]),
        ],
        eventsById: eventsById,
      );

      expect(clashes, isEmpty);
    });

    test('somebody with no bazaars at all is free', () {
      final clashes = StaffScheduling.conflicts(
        range: range(12, 16),
        employees: [employee(4, 'Missy', const [])],
        eventsById: eventsById,
      );

      expect(clashes, isEmpty);
    });

    test('the bazaar being edited is not a conflict with itself', () {
      // Otherwise nobody could ever be saved onto a bazaar twice, and simply
      // renaming it would empty its roster.
      final clashes = StaffScheduling.conflicts(
        range: range(10, 14),
        employees: [
          employee(3, 'Via', [1]),
        ],
        eventsById: eventsById,
        excludingEventId: 1,
      );

      expect(clashes, isEmpty);
    });

    test('an unknown bazaar is not treated as free time', () {
      // Another vendor's, or one since deleted. Claiming they are available
      // would be a guess dressed as a fact, so they are simply not flagged.
      final clashes = StaffScheduling.conflicts(
        range: range(12, 16),
        employees: [
          employee(3, 'Via', [999]),
        ],
        eventsById: eventsById,
      );

      expect(clashes, isEmpty);
    });

    test('only the first clash is reported, not every one', () {
      // The question is whether they are free, and one answer is enough to
      // say no.
      final clashes = StaffScheduling.conflicts(
        range: range(10, 22),
        employees: [
          employee(3, 'Via', [1, 2]),
        ],
        eventsById: eventsById,
      );

      expect(clashes[3], anyOf('August Fair', 'Payday Pop-Up'));
      expect(clashes, hasLength(1));
    });

    test('a single-day bazaar still blocks a range around it', () {
      final clashes = StaffScheduling.conflicts(
        range: range(14, 18),
        employees: [
          employee(5, 'TG', [3]),
        ],
        eventsById: eventsById,
      );

      expect(clashes[5], 'One Day Only');
    });
  });
}

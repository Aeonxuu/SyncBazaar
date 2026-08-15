import 'package:flutter/material.dart' show DateTimeRange;

import '../models/bazaar_event.dart';
import '../models/user.dart';

/// Who is already working somewhere else.
///
/// A bazaar is a physical stall. One person cannot stand at two of them, so an
/// employee assigned to bazaars whose dates overlap is not stretched thin —
/// they are simply absent from one of them, and nobody finds out until the
/// morning it opens.
///
/// Nothing enforced this before. The server's only rule is that the same
/// person cannot be added to the same bazaar twice, which says nothing about
/// two bazaars on the same weekend in different malls.
class StaffScheduling {
  const StaffScheduling._();

  /// Employee id to the name of the bazaar they are already committed to.
  ///
  /// [excludingEventId] is the bazaar being edited: its own assignments are
  /// not a conflict with itself, or nobody could ever be re-saved onto it.
  static Map<int, String> conflicts({
    required DateTimeRange range,
    required List<AppUser> employees,
    required Map<int, BazaarEvent> eventsById,
    int? excludingEventId,
  }) {
    final clashes = <int, String>{};

    for (final employee in employees) {
      for (final eventId in employee.assignedEventIdsEffective) {
        if (eventId == excludingEventId) {
          continue;
        }
        final event = eventsById[eventId];
        if (event == null) {
          // A bazaar this device has not loaded — an employee assigned to
          // another vendor's, or one since deleted. Silence is the only
          // honest answer: claiming they are free would be a guess.
          continue;
        }
        if (overlaps(
          range,
          DateTimeRange(start: event.startDate, end: event.endDate),
        )) {
          clashes[employee.id] = event.name;
          break;
        }
      }
    }

    return clashes;
  }

  /// Whether two bazaars are on at the same time.
  ///
  /// Compared by day rather than by instant: a bazaar's dates are days, and
  /// two stalls both open on the 16th clash whether or not their stored times
  /// happen to cross. Inclusive at both ends, so a bazaar ending the same day
  /// another starts is a conflict — that is one person, two venues, one
  /// morning.
  static bool overlaps(DateTimeRange a, DateTimeRange b) {
    final aStart = _dayOf(a.start);
    final aEnd = _dayOf(a.end);
    final bStart = _dayOf(b.start);
    final bEnd = _dayOf(b.end);

    return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

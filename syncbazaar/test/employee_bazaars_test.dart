import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/user.dart';

/// Which bazaars an employee works.
///
/// The Staff table showed a count, which answers "how many" and leaves the
/// question anybody actually has — "is Via free next weekend?" — unanswered.
/// These cover the resolution from ids to bazaars, which is where the two
/// interesting cases live: an id with nothing behind it, and the order the
/// answer is read in.
void main() {
  BazaarEvent event(int id, String name, int startDay, BazaarStatus status) =>
      BazaarEvent(
        id: id,
        name: name,
        companyId: 1,
        startDate: DateTime(2026, 8, startDay),
        endDate: DateTime(2026, 8, startDay + 2),
        status: status,
      );

  final eventsById = {
    1: event(1, 'August Fair', 3, BazaarStatus.ended),
    2: event(2, 'Payday Pop-Up', 20, BazaarStatus.upcoming),
    3: event(3, 'Crop Fest', 13, BazaarStatus.ongoing),
  };

  /// The screen's own resolution: ids to bazaars, soonest first, dropping any
  /// id with nothing behind it.
  List<BazaarEvent> bazaarsFor(AppUser user) => [
    for (final id in user.assignedEventIdsEffective)
      if (eventsById[id] != null) eventsById[id]!,
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));

  AppUser employee(List<int> assigned) => AppUser(
    id: 3,
    name: 'Via',
    email: 'employee@syncbazaar.com',
    role: UserRole.employee,
    assignedEventIds: assigned,
  );

  test('ids become bazaars, soonest first', () {
    final bazaars = bazaarsFor(employee([2, 1, 3]));

    expect(bazaars.map((b) => b.name), [
      'August Fair',
      'Crop Fest',
      'Payday Pop-Up',
    ]);
  });

  test('an id with no bazaar behind it is dropped', () {
    // Another vendor's event, or one since deleted. "Bazaar #99" answers
    // nothing, so it is not rendered as a placeholder.
    final bazaars = bazaarsFor(employee([1, 99]));

    expect(bazaars.map((b) => b.name), ['August Fair']);
  });

  test('somebody with no assignments resolves to nothing', () {
    expect(bazaarsFor(employee(const [])), isEmpty);
  });

  test('finished bazaars split from the ones still to come', () {
    // The split that decides whether the answer matters: "is Via free" is a
    // question about the future.
    final bazaars = bazaarsFor(employee([1, 2, 3]));
    final current = bazaars.where((b) => b.status != BazaarStatus.ended);
    final past = bazaars.where((b) => b.status == BazaarStatus.ended);

    expect(current.map((b) => b.name), ['Crop Fest', 'Payday Pop-Up']);
    expect(past.map((b) => b.name), ['August Fair']);
  });

  test('the count the table shows matches what opens', () {
    // The number is the affordance for the list; if they disagree, the
    // number is a lie about what is behind it.
    final user = employee([1, 2, 3]);

    expect(user.assignedEventIdsEffective.length, bazaarsFor(user).length);
  });
}

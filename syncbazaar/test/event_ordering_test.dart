import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/models/user.dart';

/// Bazaars are listed the way someone at a till looks for them.
///
/// The API returns them in creation order, which buries the one being sold at
/// today among bazaars that finished months ago — on a twelve-bazaar grid that
/// meant scrolling past a screen of finished ones to reach the live one.
void main() {
  final today = DateTime.now();
  DateTime days(int n) => DateTime(today.year, today.month, today.day + n);

  Future<EventRepository> withEvents(List<(String, int, int)> specs) async {
    final repository = EventRepository();
    for (final (name, startOffset, endOffset) in specs) {
      await repository.createEvent(
        name: name,
        companyId: 1,
        startDate: days(startOffset),
        endDate: days(endOffset),
      );
    }
    return repository;
  }

  test('ongoing bazaars come first, then upcoming, then ended', () async {
    // Deliberately created in the least helpful order.
    final repository = await withEvents([
      ('Ended last week', -14, -7),
      ('Upcoming next month', 30, 33),
      ('Ongoing now', -1, 2),
      ('Ended yesterday', -5, -1),
      ('Upcoming next week', 7, 9),
    ]);

    final names = (await repository.listAll()).map((e) => e.name).toList();

    expect(names, [
      'Ongoing now',
      // Soonest first: the next one to prepare for.
      'Upcoming next week',
      'Upcoming next month',
      // Most recent first: older history matters less the further back it goes.
      'Ended yesterday',
      'Ended last week',
    ]);
  });

  test('an ongoing bazaar closing soonest is listed first', () async {
    final repository = await withEvents([
      ('Closes in five days', -1, 5),
      ('Closes tomorrow', -3, 1),
    ]);

    final names = (await repository.listAll()).map((e) => e.name).toList();

    expect(names.first, 'Closes tomorrow');
  });

  test('the order holds for an employee, who sees only their own', () async {
    final repository = await withEvents([
      ('Ended', -10, -5),
      ('Ongoing', -1, 3),
    ]);
    final all = await repository.listAll();

    final employee = AppUserStub(
      assignedEventIds: all.map((e) => e.id).toList(),
    );
    final names = (await repository.listVisibleForUser(
      employee.user,
    )).map((e) => e.name).toList();

    // The scoped list is sorted too, not just the owner's.
    expect(names, ['Ongoing', 'Ended']);
  });
}

/// Minimal employee, since only the assignments and the role matter here.
class AppUserStub {
  AppUserStub({required List<int> assignedEventIds})
    : user = AppUser(
        id: 1,
        name: 'Missy',
        email: 'missy@syncbazaar.com',
        role: UserRole.employee,
        assignedEventIds: assignedEventIds,
      );

  final AppUser user;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/bazaar_event.dart';

/// Picking a bazaar to read the orders of.
///
/// The screen was titled "Select Active Bazaar" while listing every bazaar the
/// vendor has ever run — most of its own badges said ENDED. With a season's
/// worth of them and no way to narrow the list, finding one meant reading all
/// of them.
void main() {
  BazaarEvent event(String name, BazaarStatus status, int day) => BazaarEvent(
    id: name.hashCode,
    name: name,
    companyId: 1,
    startDate: DateTime(2026, 8, day),
    endDate: DateTime(2026, 8, day + 2),
    status: status,
  );

  final events = [
    event('TechVibe Expo', BazaarStatus.ongoing, 14),
    event('Weekend Test', BazaarStatus.upcoming, 20),
    event('August Fair', BazaarStatus.ended, 3),
    event('Midweek Office Bazaar', BazaarStatus.ended, 10),
  ];

  List<BazaarEvent> visible({String status = 'ALL', String search = ''}) {
    final query = search.trim().toLowerCase();
    return events
        .where((e) => status == 'ALL' || e.status.name.toUpperCase() == status)
        .where((e) => query.isEmpty || e.name.toLowerCase().contains(query))
        .toList();
  }

  String describeScope(int total, int shown) => total == shown
      ? '$total ${total == 1 ? 'bazaar' : 'bazaars'}'
      : '$shown of $total shown';

  test('everything is listed by default', () {
    // Including ended ones — this screen reads history, so hiding them would
    // remove most of what it is for.
    expect(visible(), hasLength(4));
  });

  test('the status filter narrows to one kind', () {
    expect(visible(status: 'ENDED').map((e) => e.name), [
      'August Fair',
      'Midweek Office Bazaar',
    ]);
    expect(visible(status: 'ONGOING').map((e) => e.name), ['TechVibe Expo']);
  });

  test('search matches part of a name', () {
    expect(visible(search: 'bazaar'), hasLength(1));
    expect(visible(search: 'tech'), hasLength(1));
  });

  test('search ignores case and padding', () {
    expect(visible(search: '  AUGUST '), hasLength(1));
  });

  test('search and filter both apply', () {
    // August Fair has ended, so filtering to ongoing should find nothing.
    expect(visible(status: 'ONGOING', search: 'august'), isEmpty);
  });

  test('the scope line admits when it is showing a subset', () {
    expect(describeScope(4, 4), '4 bazaars');
    expect(describeScope(4, 2), '2 of 4 shown');
    expect(describeScope(1, 1), '1 bazaar');
  });
}

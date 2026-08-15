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

  String shortDate(DateTime value) =>
      '${value.month}/${value.day}/${value.year}';

  /// The screen's own matching: the status cycle plus a query tested against
  /// the name, the status word, and either date.
  List<BazaarEvent> visible({BazaarStatus? status, String search = ''}) {
    final query = search.trim().toLowerCase();
    return events.where((e) {
      if (status != null && e.status != status) return false;
      if (query.isEmpty) return true;
      return e.name.toLowerCase().contains(query) ||
          e.status.name.toLowerCase().contains(query) ||
          shortDate(e.startDate).contains(query) ||
          shortDate(e.endDate).contains(query);
    }).toList();
  }

  /// All -> Upcoming -> Ongoing -> Ended -> All.
  BazaarStatus? next(BazaarStatus? current) => switch (current) {
    null => BazaarStatus.upcoming,
    BazaarStatus.upcoming => BazaarStatus.ongoing,
    BazaarStatus.ongoing => BazaarStatus.ended,
    BazaarStatus.ended => null,
  };

  test('everything is listed by default', () {
    // Including ended ones — this screen reads history, so hiding them would
    // remove most of what it is for.
    expect(visible(), hasLength(4));
  });

  test('the status filter narrows to one kind', () {
    expect(visible(status: BazaarStatus.ended).map((e) => e.name), [
      'August Fair',
      'Midweek Office Bazaar',
    ]);
    expect(visible(status: BazaarStatus.ongoing).map((e) => e.name), [
      'TechVibe Expo',
    ]);
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
    expect(visible(status: BazaarStatus.ongoing, search: 'august'), isEmpty);
  });

  test('searching a status word finds those bazaars', () {
    // "ended" is a thing somebody types when they mean the finished ones.
    expect(visible(search: 'ended'), hasLength(2));
  });

  test('searching a date finds the bazaar running then', () {
    expect(visible(search: '8/3/2026').map((e) => e.name), ['August Fair']);
  });

  test('the filter cycles back round to all', () {
    expect(next(null), BazaarStatus.upcoming);
    expect(next(BazaarStatus.upcoming), BazaarStatus.ongoing);
    expect(next(BazaarStatus.ongoing), BazaarStatus.ended);
    // Four taps return to where it started, so the filter is never stuck.
    expect(next(BazaarStatus.ended), isNull);
  });
}

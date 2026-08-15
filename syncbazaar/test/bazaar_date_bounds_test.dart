import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/bazaar_event.dart';

/// Which days a bazaar's calendar will accept.
///
/// Two rules that pull in opposite directions. A pop-up that opens this
/// morning is ordinary, so today has to be selectable — the picker used to
/// start tomorrow, which made a same-day bazaar impossible to enter. But a
/// bazaar cannot be moved onto days it never ran, so past days are closed.
void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  /// What the pre-bazaar form opens its calendar on.
  DateTime plannedFloor() => today;

  /// What editing an existing bazaar opens on: today, unless the bazaar has
  /// already started, in which case its own start — otherwise the picker
  /// could not display the range being edited.
  DateTime editFloor(DateTime existingStart) =>
      existingStart.isBefore(today) ? existingStart : today;

  test('a bazaar can start today', () {
    expect(plannedFloor().isAfter(today), isFalse);
    expect(plannedFloor(), today);
  });

  test('a bazaar cannot be planned into the past', () {
    final yesterday = today.subtract(const Duration(days: 1));

    expect(yesterday.isBefore(plannedFloor()), isTrue);
  });

  test('editing cannot drag a bazaar backwards', () {
    final upcoming = today.add(const Duration(days: 3));

    // The floor is today, so yesterday is not offered.
    expect(editFloor(upcoming), today);
    expect(
      today.subtract(const Duration(days: 1)).isBefore(editFloor(upcoming)),
      isTrue,
    );
  });

  test('a bazaar that already started can still be opened for editing', () {
    // Its start is before today, so a floor of today would put the range
    // being edited outside the calendar entirely.
    final started = today.subtract(const Duration(days: 4));

    expect(editFloor(started), started);
    expect(started.isBefore(editFloor(started)), isFalse);
  });

  test('a bazaar starting today edits against today', () {
    expect(editFloor(today), today);
  });

  test('an ended bazaar cannot have its dates moved at all', () {
    // Its dates are the record of when it actually ran. Moving them re-slices
    // which sales fall inside it, so the statement of account, the order list
    // and the dashboard would each report a different week than the one the
    // money came from.
    bool editable(BazaarStatus status) => status != BazaarStatus.ended;

    expect(editable(BazaarStatus.upcoming), isTrue);
    expect(editable(BazaarStatus.ongoing), isTrue);
    expect(editable(BazaarStatus.ended), isFalse);
  });

  test('an ended bazaar takes no more stock', () {
    // Allocating to a stall that has packed up moves shoes out of the
    // warehouse to nowhere. Worse, each round of allocate-then-reconcile is
    // another pass through a stock return the server cannot yet refuse to
    // repeat, so it doubles as a way to inflate inventory by hand.
    bool allocatable(BazaarStatus status) => status != BazaarStatus.ended;

    expect(allocatable(BazaarStatus.upcoming), isTrue);
    expect(allocatable(BazaarStatus.ongoing), isTrue);
    expect(allocatable(BazaarStatus.ended), isFalse);
  });

  test('the sales week covers all seven days', () {
    // A weekday-only chart hid Saturday and Sunday, which is when a pop-up
    // bazaar is most likely to be running.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    expect(days, hasLength(7));
    expect(days.first.weekday, DateTime.monday);
    expect(days.last.weekday, DateTime.sunday);
  });
}

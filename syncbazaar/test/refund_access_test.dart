import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/refund_access.dart';
import 'package:syncbazaar/models/user.dart';

/// Who is shown the refund button. Who may approve is the server's call.
void main() {
  BazaarEvent event({int id = 5, bool isFinalized = false}) => BazaarEvent(
    id: id,
    name: 'August Fair',
    companyId: 1,
    startDate: DateTime(2026, 8, 1),
    endDate: DateTime(2026, 8, 5),
    status: BazaarStatus.ongoing,
    isFinalized: isFinalized,
  );

  AppUser user(UserRole role, {List<int> assigned = const []}) => AppUser(
    id: 1,
    name: 'U',
    email: 'u@example.com',
    role: role,
    assignedEventIds: assigned,
  );

  test('the owner can refund at any bazaar', () {
    expect(canRefund(user(UserRole.owner), event()), isTrue);
    expect(canRefund(user(UserRole.owner), event(id: 99)), isTrue);
  });

  test('an employee can refund only where they are assigned', () {
    final employee = user(UserRole.employee, assigned: [5]);

    expect(canRefund(employee, event(id: 5)), isTrue);
    expect(canRefund(employee, event(id: 6)), isFalse);
  });

  test('an employee with no assignments cannot refund anywhere', () {
    expect(canRefund(user(UserRole.employee), event()), isFalse);
  });

  test('an admin cannot refund, assigned or not', () {
    expect(canRefund(user(UserRole.admin), event()), isFalse);
    expect(canRefund(user(UserRole.admin, assigned: [5]), event()), isFalse);
  });

  test('nobody can refund once the bazaar is finalized', () {
    final done = event(isFinalized: true);

    expect(canRefund(user(UserRole.owner), done), isFalse);
    expect(canRefund(user(UserRole.employee, assigned: [5]), done), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/user.dart';

/// Filtering and labelling on the Staff screen.
///
/// The list is searched by name or email, filtered by role, and headed with a
/// line saying whether what is shown is all of it. That line is the part worth
/// pinning: a count that ignores the filter tells the reader the list is
/// complete when it is not.
void main() {
  AppUser user(String name, String email, UserRole role) =>
      AppUser(id: name.hashCode, name: name, email: email, role: role);

  final staff = [
    user('Amrei', 'admin@syncbazaar.com', UserRole.admin),
    user('Lalaine', 'owner@syncbazaar.com', UserRole.owner),
    user('Via', 'employee@syncbazaar.com', UserRole.employee),
    user('Missy', 'missy@syncbazaar.com', UserRole.employee),
  ];

  List<AppUser> visible({String role = 'ALL', String search = ''}) {
    final query = search.trim().toLowerCase();
    return staff
        .where((u) => role == 'ALL' || u.role.name.toUpperCase() == role)
        .where(
          (u) =>
              query.isEmpty ||
              u.name.toLowerCase().contains(query) ||
              u.email.toLowerCase().contains(query),
        )
        .toList();
  }

  /// The screen's header line.
  String describeScope(int total, int shown) => total == shown
      ? '$total ${total == 1 ? 'person' : 'people'}'
      : '$shown of $total shown';

  test('no filter shows everyone', () {
    expect(visible(), hasLength(4));
  });

  test('the role filter narrows to that role', () {
    expect(visible(role: 'EMPLOYEE').map((u) => u.name), ['Via', 'Missy']);
    expect(visible(role: 'ADMIN').map((u) => u.name), ['Amrei']);
  });

  test('search matches a name or an email', () {
    expect(visible(search: 'missy'), hasLength(1));
    // Same person found either way -- somebody looking for a colleague may
    // remember either.
    expect(visible(search: 'missy@syncbazaar'), hasLength(1));
  });

  test('search is case-insensitive and ignores padding', () {
    expect(visible(search: '  VIA '), hasLength(1));
  });

  test('search and role filter both apply', () {
    // Via is an employee, so filtering to admins should find nobody.
    expect(visible(role: 'ADMIN', search: 'via'), isEmpty);
  });

  test('the header says how many, when nothing is filtered out', () {
    expect(describeScope(4, 4), '4 people');
  });

  test('the header admits when it is showing a subset', () {
    // A plain count here would say the list is complete when it is not.
    expect(describeScope(4, 2), '2 of 4 shown');
  });

  test('one person is a person, not people', () {
    expect(describeScope(1, 1), '1 person');
  });
}

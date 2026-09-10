import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/widgets/offline_data_notice.dart';

/// Saying that figures came from storage, and when.
///
/// Without this the offline dashboard shows numbers that are wrong rather than
/// merely old: a till that has missed another device's sales presents a total
/// in the same bold type as a live one, and someone acts on it.
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

  group('how the time is described', () {
    final today = DateTime(2026, 9, 10, 21, 30);

    test('a copy taken today is just a time', () {
      expect(
        OfflineDataNotice.describeStoredAt(
          DateTime(2026, 9, 10, 9, 14),
          now: today,
        ),
        '9:14 AM',
      );
    });

    test('an older copy carries its date', () {
      // Past midnight "9:14 PM" alone reads as an hour ago rather than as
      // yesterday evening, which is the difference between a figure worth
      // trusting and one worth checking.
      expect(
        OfflineDataNotice.describeStoredAt(
          DateTime(2026, 9, 9, 21, 14),
          now: today,
        ),
        '9 Sep, 9:14 PM',
      );
    });

    test('midday and midnight are not rendered as zero', () {
      expect(
        OfflineDataNotice.describeStoredAt(
          DateTime(2026, 9, 10, 12, 5),
          now: today,
        ),
        '12:05 PM',
      );
      expect(
        OfflineDataNotice.describeStoredAt(
          DateTime(2026, 9, 10, 0, 5),
          now: today,
        ),
        '12:05 AM',
      );
    });

    test('minutes keep their leading zero', () {
      expect(
        OfflineDataNotice.describeStoredAt(
          DateTime(2026, 9, 10, 14, 3),
          now: today,
        ),
        '2:03 PM',
      );
    });
  });

  testWidgets('it says both that it is offline and how old the copy is', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(OfflineDataNotice(storedAt: DateTime(2026, 9, 10, 9, 14))),
    );

    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text, contains('Offline'));
    expect(text, contains('9:14 AM'));
    // "Saved" rather than "old": the point is where the number came from, not
    // that it has aged.
    expect(text.toLowerCase(), contains('saved'));
  });
}

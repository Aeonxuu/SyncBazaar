import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/ui/widgets/date_range_picker_dialog.dart';

/// The calendar's selection rules are easy to get subtly wrong and invisible
/// in a screenshot, so they're pinned here.
void main() {
  // A month that starts mid-week, so the leading-blank maths is exercised.
  final firstDate = DateTime(2026, 9, 1);
  final lastDate = DateTime(2026, 9, 30);

  Future<DateTimeRange?> open(
    WidgetTester tester, {
    DateTimeRange? initial,
  }) async {
    DateTimeRange? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showAppDateRangePicker(
                  context: context,
                  firstDate: firstDate,
                  lastDate: lastDate,
                  initialRange: initial,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder day(String label) => find.widgetWithText(AnimatedContainer, label);

  testWidgets('two taps produce an inclusive range', (tester) async {
    await open(tester);
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(day('4'));
    await tester.pumpAndSettle();
    // The header narrates progress rather than leaving the user guessing.
    expect(find.textContaining('now pick the end date'), findsOneWidget);

    await tester.tap(day('9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 days'), findsOneWidget);
  });

  testWidgets('Apply is blocked until both ends are chosen', (tester) async {
    await open(tester);

    final apply = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Apply'),
    );
    expect(apply.onPressed, isNull, reason: 'Apply enabled with no selection');

    await tester.tap(day('4'));
    await tester.pumpAndSettle();
    final halfway = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Apply'),
    );
    expect(
      halfway.onPressed,
      isNull,
      reason: 'Apply enabled with only a start date',
    );

    await tester.tap(day('9'));
    await tester.pumpAndSettle();
    final complete = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Apply'),
    );
    expect(complete.onPressed, isNotNull);
  });

  testWidgets('tapping before the start moves the start, not the end', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(day('15'));
    await tester.pumpAndSettle();
    // Correcting yourself shouldn't require clearing first.
    await tester.tap(day('3'));
    await tester.pumpAndSettle();

    expect(find.textContaining('now pick the end date'), findsOneWidget);
    expect(find.textContaining('Sep 3'), findsOneWidget);
  });

  testWidgets('a third tap starts a fresh range', (tester) async {
    await open(tester);

    await tester.tap(day('4'));
    await tester.pumpAndSettle();
    await tester.tap(day('9'));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 days'), findsOneWidget);

    await tester.tap(day('20'));
    await tester.pumpAndSettle();
    expect(find.textContaining('now pick the end date'), findsOneWidget);
    expect(find.textContaining('Sep 20'), findsOneWidget);
  });

  testWidgets('Apply returns the chosen range', (tester) async {
    DateTimeRange? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                captured = await showAppDateRangePicker(
                  context: context,
                  firstDate: firstDate,
                  lastDate: lastDate,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(day('4'));
    await tester.pumpAndSettle();
    await tester.tap(day('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(captured?.start, DateTime(2026, 9, 4));
    expect(captured?.end, DateTime(2026, 9, 9));
  });
}

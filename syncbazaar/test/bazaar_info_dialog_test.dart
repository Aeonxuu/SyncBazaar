import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/constants/colors.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/ui/screens/pos/pos_screen.dart';

/// The bazaar details modal, reached from the ⓘ on a bazaar card.
///
/// It replaced a kebab menu, which promised a menu and said nothing about
/// what was in it. Edit and Delete now sit beside the facts they act on, and
/// each returns a result rather than acting in place — so the modal is closed
/// before the next one opens, instead of stacking on top of it.
void main() {
  BazaarEvent event({
    BazaarStatus status = BazaarStatus.ongoing,
    List<String> methods = const ['CASH', 'GCASH'],
  }) => BazaarEvent(
    id: 1,
    name: 'August Fair',
    companyId: 1,
    startDate: DateTime(2026, 8, 13),
    endDate: DateTime(2026, 8, 17),
    status: status,
    acceptedPaymentMethods: methods,
  );

  Future<String?> open(
    WidgetTester tester, {
    required List<String> staff,
    BazaarStatus status = BazaarStatus.ongoing,
    int remaining = 152,
  }) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => BazaarInfoDialog(
                    event: event(status: status),
                    venue: 'SM City Lucena',
                    staff: staff,
                    remainingUnits: remaining,
                    formatDate: (d) => '${d.month}/${d.day}',
                  ),
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

  testWidgets('shows the facts somebody opened it for', (tester) async {
    await open(tester, staff: ['Via', 'Missy']);

    expect(find.text('August Fair'), findsOneWidget);
    expect(find.text('SM City Lucena'), findsOneWidget);
    expect(find.text('ONGOING'), findsOneWidget);
    expect(find.text('Via, Missy'), findsOneWidget);
    expect(find.text('CASH · GCASH'), findsOneWidget);
    expect(find.text('152 units'), findsOneWidget);
  });

  testWidgets('an unstaffed bazaar says so, in red', (tester) async {
    // A blank would read as "nothing to report". This is a problem, and the
    // point is to notice it here rather than on the morning it opens.
    await open(tester, staff: const []);

    final text = tester.widget<Text>(find.text('Nobody assigned'));
    expect(text.style?.color, AppColors.error);
  });

  testWidgets('an ended bazaar calls its leftovers unreturned', (
    tester,
  ) async {
    // "Stock left" is a fact about a live bazaar; on a finished one the same
    // number is a job nobody has done yet.
    await open(tester, staff: const ['Via'], status: BazaarStatus.ended);

    // Rendered uppercased by the row's label style.
    expect(find.text('UNRETURNED STOCK'), findsOneWidget);
    expect(find.text('STOCK LEFT'), findsNothing);
  });

  testWidgets('choosing Edit closes and reports the choice', (tester) async {
    // Returned rather than acted on in place, so the edit dialog opens after
    // this one is gone instead of stacking on top of it.
    final result = await open(tester, staff: const ['Via']);
    expect(result, isNull);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('August Fair'), findsNothing);
  });

  testWidgets('both actions are offered, neither stretched', (tester) async {
    await open(tester, staff: const ['Via']);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Two occasional actions, not a pair of calls to action: a full-width
    // button here would make a reference card look like a decision.
    final dialog = tester.getRect(find.byType(Dialog));
    final edit = tester.getRect(find.widgetWithText(ElevatedButton, 'Edit'));
    expect(edit.width, lessThan(dialog.width / 2));
  });

  testWidgets('the close button dismisses without choosing', (tester) async {
    await open(tester, staff: const ['Via']);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('August Fair'), findsNothing);
  });
}

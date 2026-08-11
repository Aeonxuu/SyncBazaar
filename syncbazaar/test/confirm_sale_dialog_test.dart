import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/constants/colors.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/confirm_sale_dialog.dart';

/// The one dialog in the app that takes money and decrements stock. Its
/// colour assignment was inverted for a long time — Cancel red, Confirm green
/// — so the alarming colour sat on the safe choice. These pin the corrected
/// behaviour and the summary it now reads back.
void main() {
  Future<bool?> open(
    WidgetTester tester, {
    double total = 12495,
    int itemCount = 3,
    int unitCount = 5,
    String paymentMethod = 'COOP',
    String? extraFieldLabel,
    String? extraFieldValue,
    String? customerName,
    double? cashTendered,
    double? changeDue,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showConfirmSaleDialog(
                  context: context,
                  total: total,
                  itemCount: itemCount,
                  unitCount: unitCount,
                  paymentMethod: paymentMethod,
                  paymentIcon: Icons.payments_outlined,
                  extraFieldLabel: extraFieldLabel,
                  extraFieldValue: extraFieldValue,
                  customerName: customerName,
                  cashTendered: cashTendered,
                  changeDue: changeDue,
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

  testWidgets('reads back the amount, formatted', (tester) async {
    await open(tester);

    expect(find.text('Confirm sale'), findsWidgets);
    expect(find.text('Amount due'), findsOneWidget);
    // Separators, not `PHP 12495.00`.
    expect(find.text('PHP 12,495.00'), findsOneWidget);
    expect(find.text('3 items · 5 units'), findsOneWidget);
  });

  testWidgets('singular wording for a one-item, one-unit sale', (tester) async {
    await open(tester, itemCount: 1, unitCount: 1);
    expect(find.text('1 item · 1 unit'), findsOneWidget);
  });

  testWidgets('shows the payment method — the thing most likely to be wrong', (
    tester,
  ) async {
    await open(tester, paymentMethod: 'GCash');

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
  });

  group('optional rows', () {
    testWidgets('reference is absent when the method needs none', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Reference no.'), findsNothing);
    });

    testWidgets('reference shows when the method requires one', (tester) async {
      await open(
        tester,
        extraFieldLabel: 'Reference no.',
        extraFieldValue: '0917-555-0000',
      );
      expect(find.text('Reference no.'), findsOneWidget);
      expect(find.text('0917-555-0000'), findsOneWidget);
    });

    testWidgets('an empty reference reads as a dash, not a blank', (
      tester,
    ) async {
      await open(tester, extraFieldLabel: 'Reference no.', extraFieldValue: '');
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('customer row is omitted when nobody was named', (
      tester,
    ) async {
      await open(tester, customerName: '   ');
      expect(find.text('Customer'), findsNothing);
    });

    testWidgets('customer row shows when one was named', (tester) async {
      await open(tester, customerName: 'Juan Dela Cruz');
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
    });
  });

  group('the colour inversion that used to be here', () {
    testWidgets('Cancel is a quiet text button, not a red outlined one', (
      tester,
    ) async {
      await open(tester);

      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
      // Icons on a two-word decision were noise.
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('the primary is purple, not green', (tester) async {
      await open(tester);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm sale'),
      );
      final background = button.style?.backgroundColor?.resolve({});
      expect(background, AppColors.primary);
      expect(background, isNot(const Color(0xFF2E7D32)));
    });
  });

  group('return value', () {
    /// [target] is null to dismiss via the barrier.
    Future<bool?> openAndTap(WidgetTester tester, Finder? target) async {
      bool? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  captured = await showConfirmSaleDialog(
                    context: context,
                    total: 100,
                    itemCount: 1,
                    unitCount: 1,
                    paymentMethod: 'Cash',
                    paymentIcon: Icons.payments_outlined,
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
      if (target == null) {
        await tester.tapAt(const Offset(10, 10));
      } else {
        // By button type, not by text: "Confirm sale" is also the dialog
        // title, and `ButtonStyleButton` is abstract so it matches nothing.
        await tester.tap(target);
      }
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('Confirm commits', (tester) async {
      expect(
        await openAndTap(
          tester,
          find.widgetWithText(ElevatedButton, 'Confirm sale'),
        ),
        isTrue,
      );
    });

    testWidgets('Cancel backs out', (tester) async {
      expect(
        await openAndTap(tester, find.widgetWithText(TextButton, 'Cancel')),
        isFalse,
      );
    });

    testWidgets('dismissing the barrier is never a silent sale', (
      tester,
    ) async {
      expect(await openAndTap(tester, null), isFalse);
    });
  });

  group('summary row alignment', () {
    /// Right edge of the value in each `label ....... value` row.
    List<double> valueRightEdges(WidgetTester tester, List<String> values) {
      return values
          .map((value) => tester.getBottomRight(find.text(value)).dx)
          .toList();
    }

    testWidgets('every value ends on the same right edge', (tester) async {
      // Regression: the row had a `Spacer` *and* a bare `Flexible`, both of
      // which are flex: 1. The leftover space split in half, so each value
      // began at the midpoint and ran on by its own width — the shorter the
      // value, the further left it stopped, leaving a ragged right edge down
      // a column of amounts a cashier is supposed to scan in one glance.
      await open(
        tester,
        paymentMethod: 'CASH',
        cashTendered: 2900,
        changeDue: 600,
      );

      final edges = valueRightEdges(tester, [
        'CASH',
        'PHP 2,900.00',
        'PHP 600.00',
      ]);

      for (final edge in edges) {
        expect(edge, closeTo(edges.first, 0.5));
      }
    });

    testWidgets('alignment holds with a long label and a short value', (
      tester,
    ) async {
      await open(
        tester,
        paymentMethod: 'CASH',
        extraFieldLabel: 'Reference no.',
        extraFieldValue: '1',
        customerName: 'Juan Dela Cruz',
        cashTendered: 2900,
        changeDue: 600,
      );

      final edges = valueRightEdges(tester, [
        'CASH',
        '1',
        'Juan Dela Cruz',
        'PHP 2,900.00',
        'PHP 600.00',
      ]);

      for (final edge in edges) {
        expect(edge, closeTo(edges.first, 0.5));
      }
    });
  });

  group('cash rows', () {
    testWidgets('are omitted for a method that hands back no change', (
      tester,
    ) async {
      await open(tester, paymentMethod: 'GCash');
      expect(find.text('Cash received'), findsNothing);
      expect(find.text('Change'), findsNothing);
    });

    testWidgets('read back what was taken and what is owed', (tester) async {
      await open(
        tester,
        total: 2300,
        paymentMethod: 'CASH',
        cashTendered: 2900,
        changeDue: 600,
      );

      expect(find.text('Cash received'), findsOneWidget);
      expect(find.text('PHP 2,900.00'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('PHP 600.00'), findsOneWidget);
    });
  });

  testWidgets('the footer fits, with every optional row showing', (
    tester,
  ) async {
    // "Confirm sale" is a wider label than the "Confirm" this replaced, and
    // Material's button defaults are wider than their padding implies — the
    // pair overflowed the body by 2px at the 400px width a plain confirm uses.
    await open(
      tester,
      extraFieldLabel: 'Reference no.',
      extraFieldValue: '0917-555-0000',
      customerName: 'Juan Dela Cruz',
    );

    expect(tester.takeException(), isNull);

    final cancel = tester
        .getSize(find.widgetWithText(TextButton, 'Cancel'))
        .width;
    final confirm = tester
        .getSize(find.widgetWithText(ElevatedButton, 'Confirm sale'))
        .width;
    final footer = tester.getSize(
      find
          .ancestor(
            of: find.widgetWithText(ElevatedButton, 'Confirm sale'),
            matching: find.byType(Row),
          )
          .first,
    );

    expect(cancel + 12 + confirm, lessThanOrEqualTo(footer.width));
  });
}

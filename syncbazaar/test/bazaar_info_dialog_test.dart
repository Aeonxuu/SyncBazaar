import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/constants/colors.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/ui/screens/pos/pos_screen.dart';
import 'package:syncbazaar/ui/widgets/detail_rows.dart';
import 'package:syncbazaar/ui/widgets/info_hint.dart';
import 'package:syncbazaar/ui/widgets/refund_handler_field.dart';

import 'support/load_app_fonts.dart';

/// The bazaar details modal, reached from the ⓘ on a bazaar card.
///
/// It replaced a kebab menu, which promised a menu and said nothing about
/// what was in it. Edit and Delete now sit beside the facts they act on, and
/// each returns a result rather than acting in place -- so the modal is closed
/// before the next one opens, instead of stacking on top of it.
void main() {
  // The app's own font, so heights and wraps are the real ones.
  setUpAll(loadAppFonts);

  BazaarEvent event({
    BazaarStatus status = BazaarStatus.ongoing,
    List<String> methods = const ['GCash', 'Cash', 'QR Ph'],
    DateTime? start,
    DateTime? end,
  }) => BazaarEvent(
    id: 1,
    name: 'August Fair',
    companyId: 1,
    startDate: start ?? DateTime(2026, 10, 12),
    endDate: end ?? DateTime(2026, 10, 16),
    status: status,
    acceptedPaymentMethods: methods,
  );

  Future<void> open(
    WidgetTester tester, {
    List<String> staff = const ['Via', 'Missy'],
    BazaarStatus status = BazaarStatus.ongoing,
    int remaining = 18,
    String? blockedReason,
    RefundHandlerSetup? handler,
    List<String> methods = const ['GCash', 'Cash', 'QR Ph'],
    DateTime? start,
    DateTime? end,
    Size size = const Size(1280, 800),
    void Function(String?)? onResult,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => BazaarInfoDialog(
                    event: event(
                      status: status,
                      methods: methods,
                      start: start,
                      end: end,
                    ),
                    venue: 'SM City Lucena',
                    staff: staff,
                    remainingUnits: remaining,
                    deleteBlockedReason: blockedReason,
                    refundHandler: handler,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  RefundHandlerSetup setup({int? currentId = 10}) => RefundHandlerSetup(
    candidates: const [MapEntry(10, 'Via'), MapEntry(11, 'Missy')],
    currentId: currentId,
    onChange: (_) async {},
  );

  group('the header', () {
    testWidgets('names the bazaar, its venue and its status', (tester) async {
      await open(tester);

      expect(find.text('August Fair'), findsOneWidget);
      expect(find.text('SM City Lucena'), findsOneWidget);
      expect(find.text('ONGOING'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('puts the status next to the title, not across from it', (
      tester,
    ) async {
      await open(tester);

      final name = tester.getRect(find.text('August Fair'));
      final status = tester.getRect(find.text('ONGOING'));
      final close = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(status.left - name.right, lessThan(24));
      expect(status.center.dy, closeTo(name.center.dy, 4));
      expect(close.center.dy, closeTo(name.center.dy, 6));
    });

    testWidgets('the venue sits under the title, level with it on the left', (
      tester,
    ) async {
      await open(tester);

      final name = tester.getTopLeft(find.text('August Fair'));
      final venue = tester.getTopLeft(find.text('SM City Lucena'));
      expect(venue.dy, greaterThan(name.dy));
      // The venue's icon starts where the title does.
      expect(
        tester.getTopLeft(find.byIcon(Icons.storefront_outlined)).dx,
        closeTo(name.dx, 3),
      );
    });

    testWidgets('the close button dismisses without choosing', (tester) async {
      String? result = 'untouched';
      await open(tester, onResult: (r) => result = r);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('August Fair'), findsNothing);
      expect(result, isNull);
    });
  });

  group('the details', () {
    testWidgets('are label and value rows, labels in one style', (
      tester,
    ) async {
      await open(tester);

      for (final label in ['DATES', 'STOCK LEFT', 'PAYMENT', 'STAFF']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(DetailRow), findsNWidgets(4));
      // One label style: every label is the shared one.
      expect(find.byType(DetailLabel), findsNWidgets(4));
    });

    testWidgets('show the dates as one phrase', (tester) async {
      await open(tester);
      expect(find.text('Oct 12 – 16, 2026'), findsOneWidget);
    });

    testWidgets('show dates that cross a month', (tester) async {
      await open(
        tester,
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 11, 2),
      );
      expect(find.text('Oct 30 – Nov 2, 2026'), findsOneWidget);
    });

    testWidgets('show stock, payment and staff as plain text', (tester) async {
      await open(tester);

      expect(find.text('18 units'), findsOneWidget);
      expect(find.text('GCash, Cash, QR Ph'), findsOneWidget);
      expect(find.text('Via, Missy'), findsOneWidget);
    });

    testWidgets('say "1 unit" for one', (tester) async {
      await open(tester, remaining: 1);
      expect(find.text('1 unit'), findsOneWidget);
    });

    testWidgets('have nothing that looks pressable but is not', (tester) async {
      await open(tester);

      // No chips, no boxed tags: the facts are text. The only things that can
      // be pressed are the close, the footer actions, and (owner) the dropdown.
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(InkWell), findsWidgets);
      final pressable = find.byType(InkWell).evaluate().length;
      // Close, Delete and Edit, plus nothing for the facts.
      expect(pressable, lessThanOrEqualTo(4));
    });

    testWidgets('start at one left edge, and values at one x', (tester) async {
      await open(tester, handler: setup());

      final lefts = [
        for (final label in ['DATES', 'STOCK LEFT', 'PAYMENT', 'STAFF'])
          tester.getTopLeft(find.text(label)).dx,
        tester.getTopLeft(find.text('REFUND HANDLER')).dx,
      ];
      expect(lefts.toSet(), hasLength(1), reason: 'labels share one edge');

      final values = [
        tester.getTopLeft(find.text('Oct 12 – 16, 2026')).dx,
        tester.getTopLeft(find.text('18 units')).dx,
        tester.getTopLeft(find.text('GCash, Cash, QR Ph')).dx,
        tester.getTopLeft(find.text('Via, Missy')).dx,
      ];
      expect(values.toSet(), hasLength(1), reason: 'values share one x');
      // The handler control starts at the same x as the values.
      final dropdown = tester.getTopLeft(find.byType(RefundHandlerDropdown)).dx;
      expect(dropdown, closeTo(values.first, 0.5));
    });

    testWidgets('are divided by hairlines, with no boxes inside the dialog', (
      tester,
    ) async {
      await open(tester);

      // Three rules between four rows, plus the header's and the footer's.
      expect(find.byType(Divider), findsNWidgets(5));
      // One surface level: nothing inside the dialog draws its own filled or
      // bordered box around the facts.
      final boxes = find.descendant(
        of: find.byType(DetailRow),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color != null,
        ),
      );
      expect(boxes, findsNothing);
    });

    testWidgets('keep a steady rhythm: one gap between every row', (
      tester,
    ) async {
      await open(tester);

      final tops = [
        for (final label in ['DATES', 'STOCK LEFT', 'PAYMENT', 'STAFF'])
          tester.getTopLeft(find.text(label)).dy,
      ];
      final gaps = [
        for (var i = 1; i < tops.length; i++) tops[i] - tops[i - 1],
      ];
      expect(gaps.toSet(), hasLength(1), reason: 'rows are evenly spaced');
      // A row is 16 + a 24px line + 16 on the 8pt step, plus its 1px rule.
      expect(gaps.first - 1, 56);
      expect((gaps.first - 1) % 8, 0, reason: 'a multiple of the 8pt step');
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
      await open(tester, status: BazaarStatus.ended);

      expect(find.text('UNRETURNED STOCK'), findsOneWidget);
      expect(find.text('STOCK LEFT'), findsNothing);
    });

    testWidgets('a bazaar with no listed methods takes cash', (tester) async {
      await open(tester, methods: const []);

      expect(find.text('CASH'), findsOneWidget);
    });
  });

  group('the refund handler row', () {
    testWidgets('is one row, with the dropdown across the value column', (
      tester,
    ) async {
      await open(tester, handler: setup());

      expect(find.byType(DetailRow), findsNWidgets(5));
      expect(find.byType(RefundHandlerDropdown), findsOneWidget);

      final surface = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      final dropdown = tester.getRect(find.byType(RefundHandlerDropdown));
      // Full remaining width: out to the dialog's right padding.
      expect(dropdown.right, closeTo(surface.right - 24, 0.5));
    });

    testWidgets('is shown once: no second marker on the staff', (tester) async {
      await open(tester, handler: setup(currentId: 11));

      // The dropdown's own icon, and nothing beside a name.
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RefundHandlerDropdown),
          matching: find.text('Missy'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('explains itself behind an "i", not in printed text', (
      tester,
    ) async {
      await open(tester, handler: setup());

      const help = 'Besides the owner, this person can approve refunds here.';
      expect(find.text(help), findsNothing, reason: 'not printed on the row');

      final hint = find.descendant(
        of: find.byType(DetailRow),
        matching: find.byIcon(Icons.info_outline_rounded),
      );
      expect(hint, findsOneWidget);

      await tester.tap(hint);
      await tester.pumpAndSettle();
      expect(find.text(help), findsOneWidget);
    });

    testWidgets('explains itself on hover as well', (tester) async {
      await open(tester, handler: setup());

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byIcon(Icons.info_outline_rounded)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Besides the owner, this person can approve refunds here.'),
        findsOneWidget,
      );
    });

    testWidgets('an employee is not shown it', (tester) async {
      await open(tester);

      expect(find.byType(RefundHandlerDropdown), findsNothing);
      expect(find.text('REFUND HANDLER'), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });

    testWidgets('a handler that cannot be read is said so in the row', (
      tester,
    ) async {
      await open(
        tester,
        handler: RefundHandlerSetup(
          candidates: const [],
          currentId: null,
          onChange: (_) async {},
          loadError: 'Needs a connection to load.',
        ),
      );

      expect(find.byType(RefundHandlerDropdown), findsNothing);
      expect(find.text('Needs a connection to load.'), findsOneWidget);
      expect(find.text('REFUND HANDLER'), findsOneWidget);
    });
  });

  group('the footer', () {
    testWidgets('has Edit on the right and Delete on the left', (tester) async {
      await open(tester);

      final dialog = tester.getRect(find.byType(Dialog));
      final edit = tester.getRect(find.text('Edit bazaar'));
      final delete = tester.getRect(find.text('Delete bazaar'));
      expect(edit.center.dx, greaterThan(dialog.center.dx));
      expect(delete.center.dx, lessThan(dialog.center.dx));
      expect(delete.right, lessThan(edit.left - 100));
    });

    testWidgets('choosing Edit closes and reports the choice', (tester) async {
      // Returned rather than acted on in place, so the edit dialog opens after
      // this one is gone instead of stacking on top of it.
      String? result;
      await open(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Edit bazaar'));
      await tester.pumpAndSettle();

      expect(result, 'edit');
      expect(find.text('August Fair'), findsNothing);
    });

    testWidgets('choosing Delete closes and reports the choice', (
      tester,
    ) async {
      String? result;
      await open(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Delete bazaar'));
      await tester.pumpAndSettle();

      expect(result, 'delete');
    });

    testWidgets('Edit does not stretch', (tester) async {
      await open(tester);

      final dialog = tester.getRect(find.byType(Dialog));
      final edit = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Edit bazaar'),
      );
      expect(edit.width, lessThan(dialog.width / 2));
    });
  });

  group('a bazaar that cannot be deleted', () {
    const reason = 'This bazaar has recorded sales, so it cannot be deleted.';

    testWidgets('has no Delete button, disabled or otherwise', (tester) async {
      await open(tester, blockedReason: reason);

      expect(find.text('Delete bazaar'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Edit bazaar'), findsOneWidget);
    });

    testWidgets('shows a padlock beside the name instead', (tester) async {
      await open(tester, blockedReason: reason);

      final lock = find.byIcon(Icons.lock_outline_rounded);
      expect(lock, findsOneWidget);
      final name = tester.getRect(find.text('August Fair'));
      final padlock = tester.getRect(lock);
      expect(padlock.left, greaterThan(name.right));
      expect(padlock.center.dy, closeTo(name.center.dy, 6));
      expect(find.text('ONGOING'), findsOneWidget);
    });

    testWidgets('says why when tapped, and not before', (tester) async {
      await open(tester, blockedReason: reason);
      expect(find.text(reason), findsNothing, reason: 'not printed anywhere');

      await tester.tap(find.byIcon(Icons.lock_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text(reason), findsOneWidget);
    });

    testWidgets('says why on hover too', (tester) async {
      await open(tester, blockedReason: reason);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byIcon(Icons.lock_outline_rounded)),
      );
      await tester.pumpAndSettle();

      expect(find.text(reason), findsOneWidget);
    });

    testWidgets('the padlock is announced with its reason', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, blockedReason: reason);

      // Spoken with the name it belongs to, in the one node a screen reader
      // reaches.
      final spoken = tester
          .getSemantics(find.byIcon(Icons.lock_outline_rounded))
          .label;
      expect(spoken, contains('Cannot be deleted. $reason'));
      semantics.dispose();
    });

    testWidgets('a bazaar that can be deleted has no padlock', (tester) async {
      await open(tester);

      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.byType(InfoHint), findsNothing);
    });
  });

  testWidgets('fits a 1280x800 tablet without scrolling, fully loaded', (
    tester,
  ) async {
    // The fullest case: a long roster and the refund handler.
    await open(
      tester,
      staff: const ['Via Cruz', 'Missy Santos', 'Tessa Lim', 'Gwen Reyes'],
      blockedReason: 'This bazaar has recorded sales, so it cannot be deleted.',
      handler: setup(),
    );

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.bottom, lessThanOrEqualTo(800));
  });
}

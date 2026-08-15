import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/approvals/approvals_cubit.dart';
import 'package:syncbazaar/data/repositories/approvals_repository.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/models/approval_request.dart';
import 'package:syncbazaar/ui/screens/approvals/approvals_screen.dart';

/// Opening a stock request.
///
/// An owner could never reach this before: requests lived in memory on the
/// employee's tablet, so the one person who can approve one never had a row to
/// tap. The moment they did, tapping did nothing at all.
void main() {
  /// Exactly what the pre-bazaar form writes, taken from a real request.
  String detailsWith(List<Object?> items) => jsonEncode({
    'eventName': 'Tech Quest',
    'locationName': 'SM City Lucena',
    'companyId': 1,
    'dateStart': '2026-09-01T00:00:00.000',
    'dateEnd': '2026-09-03T00:00:00.000',
    'acceptedPaymentMethods': ['CASH'],
    'customOtherMethods': [
      {'name': 'CASH', 'extraFieldLabel': null},
    ],
    'allocationsByAllocationKey': {'1-2-3': 4},
    'items': items,
  });

  Future<void> pumpWith(WidgetTester tester, String detailsJson) async {
    final auth = AuthRepository();
    final products = ProductRepository();
    final events = EventRepository(auth: auth, products: products);
    final approvals = ApprovalsRepository();

    await approvals.add(
      ApprovalRequest(
        id: 1,
        type: ApprovalType.stock,
        eventId: 14,
        requesterId: 3,
        status: ApprovalStatus.pending,
        detailsJson: detailsJson,
        synced: true,
      ),
    );

    final cubit = ApprovalsCubit(approvals, events, products, auth);
    await cubit.loadPending();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: ApprovalsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a request opens when tapped', (tester) async {
    await pumpWith(
      tester,
      detailsWith([
        {
          'name': 'Nike Air Max SC',
          'variant': 'Triple White, 36',
          'price': 1900.0,
          'qty': 4,
        },
      ]),
    );

    expect(find.text('STOCK REQUEST for Tech Quest'), findsOneWidget);

    await tester.tap(find.text('STOCK REQUEST for Tech Quest'));
    await tester.pumpAndSettle();

    expect(find.text('Approval Details'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('the whole card is tappable, not only its text', (tester) async {
    await pumpWith(
      tester,
      detailsWith([
        {
          'name': 'Nike Air Max SC',
          'variant': 'Triple White, 36',
          'price': 1900.0,
          'qty': 4,
        },
      ]),
    );

    // The card's own InkWell, not the tab bar's -- `.first` finds a tab.
    final card = find.ancestor(
      of: find.text('STOCK REQUEST for Tech Quest'),
      matching: find.byType(InkWell),
    );
    final box = tester.getRect(card);
    // Empty space on the right of the row, well away from any text: the part
    // someone actually aims at when they mean "open this".
    final blank = Offset(box.right - 90, box.center.dy);

    await tester.tapAt(blank);
    await tester.pumpAndSettle();

    expect(find.text('Approval Details'), findsOneWidget);
  });

  testWidgets('no dead zone anywhere on the card', (tester) async {
    await pumpWith(
      tester,
      detailsWith([
        {
          'name': 'Nike Air Max SC',
          'variant': 'Triple White, 36',
          'price': 1900.0,
          'qty': 4,
        },
      ]),
    );

    final card = find.ancestor(
      of: find.text('STOCK REQUEST for Tech Quest'),
      matching: find.byType(InkWell),
    );
    final box = tester.getRect(card);

    // Nine points across the card: corners, edges, middle. Somebody aiming at
    // a row aims at the row, not at the one word inside it that happens to
    // carry the gesture.
    final dead = <String>[];
    for (final fx in [0.02, 0.5, 0.98]) {
      for (final fy in [0.15, 0.5, 0.85]) {
        final at = Offset(box.left + box.width * fx, box.top + box.height * fy);
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        if (find.text('Approval Details').evaluate().isEmpty) {
          dead.add('(${fx.toStringAsFixed(2)}, ${fy.toStringAsFixed(2)})');
        } else {
          await tester.tapAt(const Offset(5, 5)); // dismiss the barrier
          await tester.pumpAndSettle();
        }
      }
    }

    expect(dead, isEmpty, reason: 'these points did not open the request');
  });

  testWidgets('an unreadable item does not take the whole modal down', (
    tester,
  ) async {
    // The table's other rows have four cells. A row built with a different
    // number throws "Table contains irregular row lengths" while the dialog
    // is building, and the tap silently does nothing.
    await pumpWith(tester, detailsWith(['not a map at all']));

    await tester.tap(find.text('STOCK REQUEST for Tech Quest'));
    await tester.pumpAndSettle();

    expect(find.text('Approval Details'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });
}

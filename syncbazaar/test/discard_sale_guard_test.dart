import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/pos/pos_cubit.dart';
import 'package:syncbazaar/models/product.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/discard_sale_guard.dart';

/// A cart is unsaved work, and every way out of the POS throws it away.
///
/// The failure this guards against is silent: the cashier taps the rail, the
/// cart is gone, and nothing said so. Worth pinning because the guard is easy
/// to leave off a *new* exit later — the point of having one function is that
/// there is only one thing to call.
class _FakePosCubit extends Cubit<PosState> implements PosCubit {
  _FakePosCubit(super.initialState);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  CartItem itemWithQuantity(int quantity) => CartItem(
    product: const Product(id: 1, name: 'Nike Air Max SC', basePrice: 1900),
    quantity: quantity,
  );

  Future<bool?> runGuard(WidgetTester tester, PosState state) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PosCubit>.value(
          value: _FakePosCubit(state),
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  answer = await confirmLeavingSale(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('an empty cart leaves without asking', (tester) async {
    final answer = await runGuard(tester, const PosState());

    // Nothing to lose, so a dialog here would be a tax on the common case.
    expect(find.text('Discard this sale?'), findsNothing);
    expect(answer, isTrue);
  });

  testWidgets('a cart in progress asks before leaving', (tester) async {
    await runGuard(tester, PosState(cart: [itemWithQuantity(3)]));

    expect(find.text('Discard this sale?'), findsOneWidget);
    // The count is what makes the warning checkable against the counter.
    expect(find.textContaining('3 items'), findsOneWidget);
    expect(find.text('Keep selling'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('counts pieces, not cart lines', (tester) async {
    await runGuard(tester, PosState(cart: [itemWithQuantity(1)]));

    // Singular, because "1 items" in front of a customer is sloppy.
    expect(find.textContaining('1 item '), findsOneWidget);
  });

  testWidgets('keeping the sale is the emphasised choice', (tester) async {
    await runGuard(tester, PosState(cart: [itemWithQuantity(2)]));

    // Nobody opens this dialog wanting to lose a cart -- they tapped a nav
    // item and the discard is the side effect. So the safe option is the
    // filled button, and Enter cannot destroy the sale.
    final keep = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Keep selling'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(keep.autofocus, isTrue);

    // Discard stays reachable, but as a quiet text button.
    expect(
      find.ancestor(
        of: find.text('Discard'),
        matching: find.byType(TextButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Discard'),
        matching: find.byType(ElevatedButton),
      ),
      findsNothing,
    );
  });

  testWidgets('choosing to keep selling refuses the exit', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PosCubit>.value(
          value: _FakePosCubit(PosState(cart: [itemWithQuantity(2)])),
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  answer = await confirmLeavingSale(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep selling'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('choosing discard allows the exit', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PosCubit>.value(
          value: _FakePosCubit(PosState(cart: [itemWithQuantity(2)])),
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  answer = await confirmLeavingSale(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });
}

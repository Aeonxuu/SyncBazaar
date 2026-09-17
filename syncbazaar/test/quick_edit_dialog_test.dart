import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/inventory/inventory_cubit.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/core/utils/formatters.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/ui/screens/inventory/widgets/quick_edit_dialog.dart';

/// Correcting a price or a stock count over the wire, from one small dialog.
///
/// The two fields reach different distances, so the labels have to say which
/// before anything is typed. A product-wide price over variants that differ
/// erases something, so the dialog says so and asks twice. And nothing on the
/// tablet changes until the server has confirmed it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  List<Map<String, dynamic>> catalogue({bool samePrice = false}) => [
    {
      'id': 16,
      'name': 'Nike Air Max SC',
      'vendor': 1,
      'category': null,
      'variants': [
        {
          'id': 208,
          'stock_quantity': 20,
          'price': '1900.00',
          'product': 16,
          'attribute_values': [7, 10],
        },
        {
          'id': 209,
          'stock_quantity': 14,
          'price': '1900.00',
          'product': 16,
          'attribute_values': [11, 7],
        },
        {
          'id': 210,
          'stock_quantity': 5,
          'price': samePrice ? '1900.00' : '2400.00',
          'product': 16,
          'attribute_values': [8, 10],
        },
      ],
      'attributes': [
        {
          'id': 1,
          'name': 'Size',
          'values': [
            {'id': 10, 'value': '36', 'attribute': 1},
            {'id': 11, 'value': '38', 'attribute': 1},
          ],
        },
        {
          'id': 2,
          'name': 'Color',
          'values': [
            {'id': 7, 'value': 'Triple White', 'attribute': 2},
            {'id': 8, 'value': 'Triple Black', 'attribute': 2},
          ],
        },
      ],
    },
  ];

  ({
    InventoryCubit cubit,
    List<http.Request> requests,
    void Function() goOffline,
  })
  harness({bool samePrice = false}) {
    final requests = <http.Request>[];
    var online = true;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (!online) {
          throw const SocketException('no route to host');
        }
        if (request.method == 'PATCH') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 208,
              'stock_quantity': sent['stock_quantity'] ?? 20,
              'price': sent['price'] ?? '1900.00',
              'product': 16,
              'attribute_values': [7, 10],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(catalogue(samePrice: samePrice)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    final cubit = InventoryCubit(
      ProductRepository(auth: auth),
      SalesRepository(),
    );
    return (cubit: cubit, requests: requests, goOffline: () => online = false);
  }

  String? result;

  /// Opens the dialog for the Triple White / 36 row of the loaded product.
  Future<void> open(WidgetTester tester, InventoryCubit cubit) async {
    await cubit.load();
    final product = cubit.state.rows.first.product;
    result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showQuickEditDialog(
                  context: context,
                  cubit: cubit,
                  product: product,
                  allocationKey: '16:10:7',
                  variantLabel: 'Triple White · 36',
                  currentStock: 20,
                  variantPrices: cubit.variantPricesForProduct(product.id),
                );
              },
              child: const Text('edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
  }

  Finder saveButton() => find.widgetWithText(ElevatedButton, 'Save');

  group('what the labels say', () {
    testWidgets('price is the product\'s, stock is the variant\'s', (
      tester,
    ) async {
      await open(tester, harness().cubit);

      // The title covers both fields and only one is variant-scoped, so it
      // names the product; each field says how far it reaches.
      expect(find.text('Nike Air Max SC'), findsOneWidget);
      expect(find.text('Price · all 3 variants'), findsOneWidget);
      expect(find.text('Stock · Triple White · 36'), findsOneWidget);
    });
  });

  group('when nothing has changed', () {
    testWidgets('Save is disabled', (tester) async {
      await open(tester, harness().cubit);

      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNull);
    });

    testWidgets('Cancel closes with nothing', (tester) async {
      await open(tester, harness().cubit);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('validation', () {
    testWidgets('a blank stock count is refused beside the field', (
      tester,
    ) async {
      final h = harness();
      await open(tester, h.cubit);

      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();

      // Nothing valid to save, so the button never lights up, and no request
      // goes out.
      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNull);
      expect(h.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    testWidgets('a zero price is refused', (tester) async {
      await open(tester, harness().cubit);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();

      expect(tester.widget<ElevatedButton>(saveButton()).onPressed, isNull);
    });
  });

  group('stock', () {
    testWidgets('is saved and the dialog closes saying so', (tester) async {
      final h = harness();
      await open(tester, h.cubit);

      await tester.enterText(find.byType(TextField).last, '12');
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(result, 'Stock updated.');
      final patch = h.requests.singleWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), {'stock_quantity': 12});
    });

    testWidgets('offline keeps the dialog open with the typed value', (
      tester,
    ) async {
      final h = harness();
      await open(tester, h.cubit);
      h.goOffline();

      await tester.enterText(find.byType(TextField).last, '12');
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      // Said here, beside the fields, not in a SnackBar under the dialog.
      expect(
        find.text('Cannot reach the server, so nothing was changed.'),
        findsOneWidget,
      );
      expect(result, 'unset', reason: 'the dialog must not have closed');
      // Nothing typed is lost to the failure.
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '12',
      );
    });
  });

  group('price over variants that differ', () {
    testWidgets('warns with the range before doing anything', (tester) async {
      await open(tester, harness().cubit);

      expect(
        find.textContaining(
          'Prices differ across this product\'s 3 variants, from '
          '${formatPeso(1900)} to ${formatPeso(2400)}.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the first Save asks, the second writes', (tester) async {
      final h = harness();
      await open(tester, h.cubit);

      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pump();

      // Nothing has gone out; the button now says exactly what it will do.
      expect(h.requests.where((r) => r.method == 'PATCH'), isEmpty);
      final confirm = find.widgetWithText(
        ElevatedButton,
        'Set all 3 to ${formatPeso(2000)}',
      );
      expect(confirm, findsOneWidget);

      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(result, 'Price set for all 3 variants.');
      expect(h.requests.where((r) => r.method == 'PATCH').length, 3);
    });
  });

  group('price over variants that agree', () {
    testWidgets('no warning, and one Save is enough', (tester) async {
      // Every product on the hosted backend today. The common case must not
      // pay for the rare one with an extra tap.
      final h = harness(samePrice: true);
      await open(tester, h.cubit);

      expect(find.textContaining('Prices differ'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '2000');
      await tester.pump();
      await tester.tap(saveButton());
      await tester.pumpAndSettle();

      expect(result, 'Price set for all 3 variants.');
    });
  });
}

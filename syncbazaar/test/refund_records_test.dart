import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/dashboard/dashboard_cubit.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/core/constants/colors.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/core/utils/formatters.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';
import 'package:syncbazaar/services/dashboard_analytics_service.dart';
import 'package:syncbazaar/services/orders_workbook.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/customer_history_card.dart';
import 'package:syncbazaar/ui/screens/orders/orders_screen.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_slot.dart';

/// A refund is a row in the records, and never a number in a total.
///
/// Money came in at the sale and went out at the refund. The sale keeps its
/// positive total and shows as returned; the refund sits beside it as a
/// negative row. Revenue leaves a returned sale out, which already removes the
/// refunded money -- subtracting the refund as well would take it off twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var next = 0;
  Sale sale({
    int eventId = 1,
    double total = 1000,
    int qty = 1,
    OrderStatus status = OrderStatus.completed,
    DateTime? at,
    int soldBy = 3,
    int? serverId,
    String method = 'CASH',
    int productId = 10,
    String customer = 'Aaron',
    bool synced = true,
  }) {
    final id = ++next;
    return Sale(
      id: id,
      clientUuid: 'uuid-$id',
      eventId: eventId,
      productId: productId,
      customerName: customer,
      soldById: soldBy,
      employeeId: '',
      paymentMethod: method,
      qty: qty,
      total: total,
      timestamp: at ?? DateTime.now(),
      orderStatus: status,
      synced: synced,
      serverId: serverId ?? id,
    );
  }

  Refund refund({
    required int saleId,
    int eventId = 1,
    double amount = 1000,
    String method = 'CASH',
    String reference = '',
    String approvedBy = 'Lalaine',
    DateTime? at,
    int id = 1,
  }) => Refund(
    id: id,
    saleId: saleId,
    eventId: eventId,
    amount: amount,
    methodId: 1,
    methodName: method,
    reason: 'Wrong size',
    reference: reference,
    issuedById: 3,
    issuedByName: 'Via',
    authorizedById: 1,
    authorizedByName: approvedBy,
    customerName: 'Aaron',
    createdAt: at ?? DateTime.now(),
  );

  group('formatting', () {
    test('a refund total leads with the sign', () {
      expect(formatPesoSigned(-1900), '-PHP 1,900.00');
      expect(formatPesoSigned(1900), 'PHP 1,900.00');
      expect(formatPesoSigned(0), 'PHP 0.00');
    });

    test('a refund sub-line says who approved it', () {
      expect(
        refundSubLine(time: '2:32 PM', method: 'GCASH', approvedBy: 'Lalaine'),
        '2:32 PM · GCASH · Approved by Lalaine',
      );
      expect(refundSubLine(time: '2:32 PM', method: 'CASH'), '2:32 PM · CASH');
    });
  });

  group('Orders', () {
    Future<List<TransactionRecord>> load(
      List<Sale> sales,
      List<Refund> refunds,
    ) async {
      final repo = SalesRepository();
      for (final s in sales) {
        await repo.addSale(s);
      }
      repo.debugSetRefunds(refunds);
      final cubit = OrdersCubit(repo, ProductRepository());
      await cubit.load();
      return cubit.state.records;
    }

    test(
      'a refund is its own row, negative, beside the sale it undoes',
      () async {
        final bought = sale(
          total: 1900,
          status: OrderStatus.returned,
          at: DateTime(2026, 10, 2, 10),
          serverId: 2302,
        );
        final records = await load(
          [bought],
          [refund(saleId: 2302, amount: 1900, at: DateTime(2026, 10, 2, 14))],
        );

        expect(records, hasLength(2));
        final refundRow = records.firstWhere((r) => r.isRefund);
        final saleRow = records.firstWhere((r) => !r.isRefund);

        expect(
          saleRow.total,
          1900,
          reason: 'the sale keeps its positive total',
        );
        expect(saleRow.status, OrderStatus.returned);
        expect(refundRow.total, -1900);
        expect(refundRow.unitPrice, -1900);
        expect(refundRow.quantity, 1, reason: 'a count never goes negative');
        expect(refundRow.timestamp, DateTime(2026, 10, 2, 14));
        expect(refundRow.approvedByName, 'Lalaine');
      },
    );

    test('a column of totals adds up to the cash on hand', () async {
      final records = await load(
        [
          sale(total: 1900, status: OrderStatus.returned, serverId: 1),
          sale(total: 500, serverId: 2),
        ],
        [refund(saleId: 1, amount: 1900)],
      );

      expect(records.fold<double>(0, (sum, r) => sum + r.total), 500);
    });

    test('refund rows sort by time with the rest, newest first', () async {
      final records = await load(
        [
          sale(at: DateTime(2026, 10, 2, 9), serverId: 1),
          sale(at: DateTime(2026, 10, 2, 16), serverId: 2),
        ],
        [refund(saleId: 1, at: DateTime(2026, 10, 2, 12))],
      );

      expect(records.map((r) => r.isRefund), [false, true, false]);
    });

    test('the refund row carries the method it went back by', () async {
      final records = await load(
        [sale(method: 'GCASH', serverId: 1)],
        [refund(saleId: 1, method: 'GCASH')],
      );

      expect(records.firstWhere((r) => r.isRefund).paymentMethod, 'GCASH');
    });

    test('the refund row belongs to whoever sold the sale', () async {
      // Not whoever tapped refund: an employee sees refunds of sales at their
      // bazaars the same way they see the sales.
      final records = await load(
        [sale(soldBy: 11, serverId: 1)],
        [refund(saleId: 1)],
      );

      expect(records.firstWhere((r) => r.isRefund).userId, 11);
    });

    test('a refund of a sale that is not loaded is still shown', () async {
      final records = await load([], [refund(saleId: 999, amount: 700)]);

      expect(records.single.isRefund, isTrue);
      expect(records.single.total, -700);
      expect(records.single.productLabel, 'Unknown product');
    });

    test('a refund row cannot itself be refunded', () async {
      final records = await load([sale(serverId: 1)], [refund(saleId: 1)]);

      expect(records.firstWhere((r) => r.isRefund).isRefundable, isFalse);
    });

    test(
      'an employee sees refunds at their bazaars and not elsewhere',
      () async {
        final records = await load(
          [sale(eventId: 1, serverId: 1), sale(eventId: 2, serverId: 2)],
          [
            refund(saleId: 1, eventId: 1, id: 1),
            refund(saleId: 2, eventId: 2, id: 2),
          ],
        );
        const employee = AppUser(
          id: 3,
          name: 'Via',
          email: 'v@example.com',
          role: UserRole.employee,
          assignedEventIds: [1],
        );

        final seen = OrdersState(records: records).visibleRecords(employee);

        expect(seen.where((r) => r.isRefund).map((r) => r.eventId), [1]);
      },
    );

    test('the caption counts orders and refunds apart', () async {
      final records = await load(
        [sale(serverId: 1), sale(serverId: 2)],
        [refund(saleId: 1)],
      );

      expect(ordersFoundCaption(records), '2 orders found · 1 refund');
      expect(
        ordersFoundCaption(records.where((r) => !r.isRefund).toList()),
        '2 orders found',
      );
    });

    group('keeping up with the data', () {
      Future<OrdersCubit> opened(SalesRepository repo) async {
        final cubit = OrdersCubit(repo, ProductRepository());
        await cubit.load();
        return cubit;
      }

      test('a sale rung up appears without reopening the screen', () async {
        final repo = SalesRepository();
        final cubit = await opened(repo);
        expect(cubit.state.records, isEmpty);

        await repo.addSale(sale(synced: false, serverId: null));
        await pumpEventQueue();

        expect(cubit.state.records, hasLength(1));
      });

      test('an upload finishing gives the row its refund button', () async {
        final repo = SalesRepository();
        final unsent = Sale(
          id: 1760000000016,
          clientUuid: 'uuid-x',
          eventId: 1,
          productId: 10,
          customerName: 'Aaron',
          employeeId: '',
          paymentMethod: 'CASH',
          qty: 1,
          total: 1900,
          timestamp: DateTime.now(),
          orderStatus: OrderStatus.completed,
          synced: false,
        );
        await repo.addSale(unsent);
        final cubit = await opened(repo);
        expect(cubit.state.records.single.isRefundable, isFalse);

        // What the till's quiet upload does when the server answers.
        await repo.markSynced({'uuid-x'}, serverIds: {'uuid-x': 2302});
        await pumpEventQueue();

        final row = cubit.state.records.single;
        expect(row.serverSaleId, 2302);
        expect(row.isRefundable, isTrue);
      });

      test('changes that pile up are folded into one rebuild', () async {
        final repo = SalesRepository();
        final cubit = await opened(repo);

        for (var i = 0; i < 5; i++) {
          await repo.addSale(sale(synced: false, serverId: null));
        }
        await pumpEventQueue();

        expect(cubit.state.records, hasLength(5));
      });

      test('a closed cubit stops listening', () async {
        final repo = SalesRepository();
        final cubit = await opened(repo);
        await cubit.close();

        await repo.addSale(sale(synced: false, serverId: null));
        await pumpEventQueue();

        expect(cubit.state.records, isEmpty);
      });
    });
  });

  group('the dashboard', () {
    late EventRepository events;
    late SalesRepository sales;
    late DashboardCubit cubit;

    const owner = AppUser(
      id: 1,
      name: 'Lalaine',
      email: 'l@example.com',
      role: UserRole.owner,
    );

    setUp(() {
      events = EventRepository();
      sales = SalesRepository();
      cubit = DashboardCubit(
        events,
        sales,
        productRepository: ProductRepository(),
      );
    });

    Future<int> liveBazaar() async {
      final today = DateTime.now();
      final event = await events.createEvent(
        name: 'August Fair',
        companyId: 1,
        startDate: today.subtract(const Duration(days: 1)),
        endDate: today.add(const Duration(days: 1)),
      );
      return event.id;
    }

    String kpi(String title) =>
        cubit.state.kpis.firstWhere((k) => k.title.startsWith(title)).value;

    test(
      'a refunded sale is not revenue, and the refund is not taken off again',
      () async {
        final eventId = await liveBazaar();
        await sales.addSale(sale(eventId: eventId, total: 1000, serverId: 1));
        await sales.addSale(sale(eventId: eventId, total: 2000, serverId: 2));
        final refunded = sale(
          eventId: eventId,
          total: 500,
          status: OrderStatus.returned,
          serverId: 3,
        );
        await sales.addSale(refunded);
        sales.debugSetRefunds([
          refund(saleId: 3, eventId: eventId, amount: 500),
        ]);

        await cubit.load(owner);

        // 1,000 + 2,000. The refunded 500 is left out because the sale is
        // returned; taking the refund off as well would make this 2,500.
        expect(kpi('Total Sale'), 'PHP 3,000.00');
        expect(kpi("Today's Sale"), 'PHP 3,000.00');
        expect(cubit.state.dailySales.fold<double>(0, (a, b) => a + b), 3000);
        expect(
          kpi('Total Orders'),
          '3',
          reason: 'the returned sale still counts',
        );
      },
    );

    test('a refund shows in Recent Orders as money out', () async {
      final eventId = await liveBazaar();
      await sales.addSale(
        sale(
          eventId: eventId,
          total: 500,
          status: OrderStatus.returned,
          serverId: 1,
        ),
      );
      sales.debugSetRefunds([
        refund(saleId: 1, eventId: eventId, amount: 500, method: 'GCASH'),
      ]);

      await cubit.load(owner);

      final rows = cubit.state.recentOrders;
      expect(rows, hasLength(2));
      final row = rows.firstWhere((r) => r.status == 'Refunded');
      expect(row.amount, -500);
      expect(row.paymentMethod, 'GCASH');
      expect(row.bazaarName, 'August Fair');
      expect(
        rows.firstWhere((r) => r.status != 'Refunded').amount,
        500,
        reason: 'the sale keeps its positive amount',
      );
    });

    test(
      'refund rows are left out for a bazaar the dashboard does not cover',
      () async {
        await liveBazaar();
        sales.debugSetRefunds([refund(saleId: 1, eventId: 999)]);

        await cubit.load(owner);

        expect(cubit.state.recentOrders, isEmpty);
      },
    );

    test('a bazaar with no refunds is unchanged', () async {
      final eventId = await liveBazaar();
      await sales.addSale(sale(eventId: eventId, total: 1200, serverId: 1));

      await cubit.load(owner);

      expect(kpi('Total Sale'), 'PHP 1,200.00');
      expect(cubit.state.recentOrders, hasLength(1));
    });
  });

  group('the Analyze card', () {
    const service = DashboardAnalyticsService();
    const eventNames = {1: 'Amkor', 2: 'Company B'};
    const productNames = {10: 'Air Force 1', 11: 'Samba OG'};

    DashboardAnalytics compute(List<Sale> sales) => service.compute(
      selectedFilter: DashboardAnalyticsService.allBazaarsFilter,
      sales: sales,
      eventNameById: eventNames,
      productNameById: productNames,
      variantLabelByOptionId: const {},
    );

    AnalyticsMetric? metric(DashboardAnalytics a, AnalyticsMetricKind kind) =>
        a.metrics.where((m) => m.kind == kind).firstOrNull;

    test(
      'a returned sale adds no revenue, so the average is of what was kept',
      () {
        final result = compute([
          sale(total: 1000),
          sale(total: 3000),
          sale(total: 9000, status: OrderStatus.returned),
        ]);

        expect(result.averageOrderValue, 2000);
      },
    );

    test(
      'returned sales still count as transactions and against completion',
      () {
        final result = compute([sale(), sale(status: OrderStatus.returned)]);

        expect(result.transactionCount, 2);
        expect(result.completedOrders, 1);
        expect(result.completionRate, 0.5);
      },
    );

    test('units sold leave a returned sale out', () {
      final result = compute([
        sale(qty: 2),
        sale(qty: 5, status: OrderStatus.returned),
      ]);

      expect(metric(result, AnalyticsMetricKind.unitsSold)?.value, '2');
    });

    test('best seller is measured on units kept', () {
      // Eight Samba came back; the Air Force 1 is what actually sold.
      final result = compute([
        sale(productId: 10, qty: 2),
        sale(productId: 11, qty: 8, status: OrderStatus.returned),
      ]);

      expect(
        metric(result, AnalyticsMetricKind.topProduct)?.value,
        'Air Force 1',
      );
    });

    test('the top bazaar is by money kept', () {
      final result = compute([
        sale(eventId: 1, total: 2000),
        sale(eventId: 2, total: 9000, status: OrderStatus.returned),
        sale(eventId: 2, total: 100),
      ]);

      expect(metric(result, AnalyticsMetricKind.topBazaar)?.value, 'Amkor');
    });

    test('the busiest day is by money kept', () {
      final monday = DateTime(2026, 10, 12);
      final tuesday = DateTime(2026, 10, 13);
      final result = compute([
        sale(total: 500, at: monday),
        sale(total: 8000, at: tuesday, status: OrderStatus.returned),
        sale(total: 300, at: tuesday),
      ]);

      expect(metric(result, AnalyticsMetricKind.busiestDay)?.value, 'Monday');
    });

    test('a scope where everything was returned does not divide by zero', () {
      final result = compute([
        sale(status: OrderStatus.returned),
        sale(status: OrderStatus.returned),
      ]);

      expect(result.averageOrderValue, 0);
      expect(result.completionRate, 0);
      expect(result.transactionCount, 2);
    });
  });

  group('the orders workbook', () {
    OrderLine line({
      String method = 'CASH',
      double total = 1900,
      bool returned = false,
      bool refunded = false,
      String reference = '',
      DateTime? date,
      int quantity = 1,
    }) => OrderLine(
      date: date ?? DateTime(2026, 10, 2, 14, 32),
      customerName: 'Aaron',
      product: 'Tote Bag',
      paymentMethod: method,
      reference: reference,
      quantity: quantity,
      total: total,
      returned: returned,
      refunded: refunded,
    );

    Excel build(
      List<OrderLine> lines, {
      Map<String, String?> labels = const {},
    }) => Excel.decodeBytes(
      const OrdersWorkbook().build(
        lines: lines,
        extraFieldLabelByMethod: labels,
      ),
    );

    List<String> row(Excel book, String sheet, int index) => book
        .tables[sheet]!
        .rows[index]
        .map((c) => c?.value?.toString() ?? '')
        .toList();

    test(
      'a refund line is negative, on the sheet of the method it went back by',
      () {
        final book = build([
          line(returned: true, date: DateTime(2026, 10, 2, 10)),
          line(total: -1900, refunded: true, date: DateTime(2026, 10, 2, 14)),
        ]);

        final sale = row(book, 'CASH', 1);
        final refund = row(book, 'CASH', 2);
        // Date, Customer, Product, Unit Price, Quantity, Total, Status
        expect(sale[3], '1900');
        expect(sale[5], '1900');
        expect(sale[6], 'Returned');
        expect(refund[3], '-1900', reason: 'unit price is negative');
        expect(refund[4], '1', reason: 'the quantity is not');
        expect(refund[5], '-1900');
        expect(refund[6], 'Refunded');
      },
    );

    test('a GCash refund lands on the GCash sheet with its reference', () {
      final book = build(
        [
          line(method: 'GCASH', reference: 'SALE-1', returned: true),
          line(
            method: 'GCASH',
            total: -1900,
            refunded: true,
            reference: 'SENT-BACK-9',
          ),
        ],
        labels: {'GCASH': 'Reference Number'},
      );

      final refund = row(book, 'GCASH', 2);
      // Date, Customer, Product, Reference Number, Reference From, Unit Price,
      // Quantity, Total, Status
      expect(refund[3], 'SENT-BACK-9');
      expect(refund[7], '-1900');
      expect(refund[8], 'Refunded');
      expect(book.tables.containsKey('CASH'), isTrue);
      expect(book.tables['CASH']!.rows.length, 1, reason: 'only its header');
    });

    test('a sheet\'s total column nets out to what is in the box', () {
      final book = build([
        line(total: 1900, returned: true),
        line(total: -1900, refunded: true),
        line(total: 700),
      ]);

      var sum = 0.0;
      for (var i = 1; i < book.tables['CASH']!.rows.length; i++) {
        sum += double.parse(row(book, 'CASH', i)[5]);
      }
      expect(sum, 700);
    });

    test('a refund line says Refunded even though its sale is Returned', () {
      expect(line(returned: true).status, 'Returned');
      expect(line(refunded: true).status, 'Refunded');
      expect(line().status, 'Completed');
    });

    test('a refund line\'s unit price is negative from its negative total', () {
      expect(line(total: -1900, refunded: true).unitPrice, -1900);
      expect(line(total: -3800, quantity: 2, refunded: true).unitPrice, -1900);
    });
  });

  group('on screen', () {
    testWidgets('a refund row has nothing in the refund slot', (tester) async {
      final refundRow = TransactionRecord(
        kind: TransactionKind.refund,
        orderId: -1,
        serverSaleId: 7,
        customerName: 'Aaron',
        timestamp: DateTime(2026, 10, 2),
        productLabel: 'Tote Bag',
        unitPrice: -1900,
        quantity: 1,
        total: -1900,
        eventId: 1,
        paymentMethod: 'CASH',
        userId: 3,
        status: OrderStatus.returned,
        refund: refund(saleId: 7),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefundSlot(
              record: refundRow,
              event: BazaarEvent(
                id: 1,
                name: 'Fair',
                companyId: 1,
                startDate: DateTime(2026, 10, 1),
                endDate: DateTime(2026, 10, 30),
                status: BazaarStatus.ongoing,
              ),
              user: const AppUser(
                id: 1,
                name: 'O',
                email: 'o@x.com',
                role: UserRole.owner,
              ),
              refunds: RefundRepository(
                auth: AuthRepository(apiClient: ApiClient())..vendorId = 1,
              ),
              onRefund: () {},
            ),
          ),
        ),
      );

      expect(find.byType(RefundButton), findsNothing);
      expect(find.byType(RefundedTag), findsNothing);
    });

    testWidgets('Recent Orders prints a refund as -PHP in the error colour', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerHistoryCard(
                rows: [
                  CustomerHistoryData(
                    timestamp: DateTime(2026, 10, 2, 14),
                    customerName: 'Aaron',
                    bazaarName: 'Fair',
                    paymentMethod: 'GCASH',
                    amount: -500,
                    status: 'Refunded',
                  ),
                  CustomerHistoryData(
                    timestamp: DateTime(2026, 10, 2, 10),
                    customerName: 'Aaron',
                    bazaarName: 'Fair',
                    paymentMethod: 'GCASH',
                    amount: 500,
                    status: 'Returned',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final refund = tester.widget<Text>(find.text('-PHP 500.00'));
      expect(refund.style?.color, AppColors.error);
      final sale = tester.widget<Text>(find.text('PHP 500.00'));
      expect(sale.style?.color, isNot(AppColors.error));
      expect(find.text('Refunded'), findsOneWidget);
    });
  });
}

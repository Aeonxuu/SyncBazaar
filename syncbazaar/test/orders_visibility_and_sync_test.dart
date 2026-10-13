import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';
import 'package:syncbazaar/services/sale_upload_service.dart';
import 'package:syncbazaar/ui/screens/orders/orders_screen.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_slot.dart';

/// Who sees which sales, and what happens to a sale that never got sent.
///
/// Found while testing refunds with an owner and two employees sharing one
/// tablet: an employee could not refund, and the owner saw a refund button on
/// one employee's sale but not the other's. A sale only gets a refund button
/// once the server has confirmed it and given it an id, and a sale could sit
/// unsent -- through a logout, into the next person's session -- with nothing
/// retrying it and nothing on the row saying why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Sale sale({
    required int id,
    int eventId = 5,
    int soldBy = 0,
    bool synced = false,
    int? serverId,
    String uuid = '',
  }) => Sale(
    id: id,
    clientUuid: uuid.isEmpty ? 'uuid-$id' : uuid,
    eventId: eventId,
    productId: 16,
    variantOptionIdA: 10,
    variantOptionIdB: 7,
    customerName: 'Aaron',
    soldById: soldBy,
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: 1900,
    timestamp: DateTime(2026, 10, 2),
    orderStatus: OrderStatus.completed,
    synced: synced,
    serverId: serverId,
  );

  AppUser employee(int id, {List<int> assigned = const [5]}) => AppUser(
    id: id,
    name: 'E$id',
    email: 'e$id@example.com',
    role: UserRole.employee,
    assignedEventIds: assigned,
  );

  const owner = AppUser(
    id: 1,
    name: 'Owner',
    email: 'o@example.com',
    role: UserRole.owner,
  );

  TransactionRecord record({
    required int orderId,
    int userId = 0,
    int eventId = 5,
  }) => TransactionRecord(
    orderId: orderId,
    customerName: 'Aaron',
    timestamp: DateTime(2026, 10, 2),
    productLabel: 'Tote Bag',
    unitPrice: 1900,
    quantity: 1,
    total: 1900,
    eventId: eventId,
    paymentMethod: 'CASH',
    userId: userId,
  );

  group('who sees which sales', () {
    final records = [
      record(orderId: 1, userId: 10), // A's sale, bazaar 5
      record(orderId: 2, userId: 11), // B's sale, bazaar 5
      record(orderId: 3, userId: 11, eventId: 9), // B's sale, another bazaar
    ];

    test('an employee sees every sale at the bazaars they are assigned to', () {
      final state = OrdersState(records: records);

      final seen = state.visibleRecords(employee(10)).map((r) => r.orderId);

      expect(seen, [1, 2], reason: "B's sale too, but not another bazaar's");
    });

    test('an employee no longer sees only their own', () {
      final state = OrdersState(records: records);

      expect(
        state.visibleRecords(employee(11, assigned: [5])).map((r) => r.userId),
        containsAll([10, 11]),
      );
    });

    test('the owner sees everything', () {
      expect(OrdersState(records: records).visibleRecords(owner), hasLength(3));
    });

    test('the server\'s assignments beat the ones from sign-in', () {
      // Assigned to bazaar 9 after signing in: the stale ids say only 5.
      final state = OrdersState(
        records: records,
        assignedEventIds: const [5, 9],
      );

      final seen = state.visibleRecords(employee(10, assigned: [5]));

      expect(seen.map((r) => r.orderId), [1, 2, 3]);
    });

    test('with nothing from the server the sign-in ids are used', () {
      final state = OrdersState(records: records);

      expect(state.assignedFor(employee(10, assigned: [9])), [9]);
    });

    test(
      'fresh assignments are carried onto the user for asking permission',
      () {
        const state = OrdersState(assignedEventIds: [5, 9]);

        final user = state.withFreshAssignments(employee(10, assigned: [5]));

        expect(user.assignedEventIdsEffective, [5, 9]);
        expect(state.withFreshAssignments(owner), same(owner));
      },
    );
  });

  group('the sub-line', () {
    test('says who sold it', () {
      expect(
        orderSubLine(time: '2:32 PM', method: 'GCASH', soldBy: 'Missy'),
        '2:32 PM · GCASH · Sold by Missy',
      );
    });

    test('leaves it out for a sale that does not say', () {
      expect(orderSubLine(time: '2:32 PM', method: 'CASH'), '2:32 PM · CASH');
    });
  });

  group('the Orders cubit with a server', () {
    ({
      OrdersCubit cubit,
      SalesRepository sales,
      List<http.Request> requests,
      void Function(bool) setUp_,
    })
    harness({
      List<Map<String, dynamic>> events = const [
        {'id': 5, 'is_approved': true},
        {'id': 9, 'is_approved': true},
        {'id': 12, 'is_approved': false},
      ],
      List<int> batchSaleIds = const [],
      bool reachable = true,
    }) {
      var up = reachable;
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (!up) throw http.ClientException('down');
          final path = request.url.path;
          if (path == '/api/bazaar/event/') {
            return http.Response(jsonEncode(events), 200);
          }
          if (path.contains('mode-of-payment')) {
            return http.Response(
              jsonEncode([
                {'id': 1, 'name': 'Cash'},
              ]),
              200,
            );
          }
          if (path.endsWith('/batch-sale/')) {
            return http.Response(
              jsonEncode({
                'batch_results': [
                  for (final id in batchSaleIds)
                    {'status': 'created', 'sale_id': id},
                ],
              }),
              201,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final auth = AuthRepository(apiClient: client)..vendorId = 1;
      final sales = SalesRepository(auth: null);
      final eventRepo = _Stocky(auth: auth);
      final uploader = SaleUploadService(
        auth: auth,
        events: eventRepo,
        products: ProductRepository(),
        sales: sales,
      );
      return (
        cubit: OrdersCubit(
          sales,
          ProductRepository(),
          events: eventRepo,
          uploader: uploader,
        ),
        sales: sales,
        requests: requests,
        setUp_: (value) => up = value,
      );
    }

    test('learns the bazaars the server has the employee on', () async {
      final h = harness();

      await h.cubit.load();

      expect(h.cubit.state.assignedEventIds, [
        5,
        9,
      ], reason: 'a proposal is not a bazaar yet');
    });

    test('keeps what it knew when the server cannot be reached', () async {
      final h = harness();
      await h.cubit.load();
      h.setUp_(false);

      await h.cubit.load();

      expect(h.cubit.state.assignedEventIds, [5, 9]);
    });

    test('opening Orders sends a sale that never got sent', () async {
      final h = harness(batchSaleIds: [2302]);
      await h.sales.addSale(sale(id: 1760000000016, soldBy: 11));

      await h.cubit.load();
      // The send runs behind the load.
      await pumpEventQueue();

      expect((await h.sales.listUnsyncedSales()), isEmpty);
      final shown = h.cubit.state.records.single;
      expect(shown.serverSaleId, 2302, reason: 'now it can be refunded');
      expect(shown.userId, 11, reason: 'still credited to who sold it');
      expect(
        h.requests.where((r) => r.url.path.endsWith('/batch-sale/')),
        hasLength(1),
      );
    });

    test('does not try to send before anyone has signed in', () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('[]', 200);
        }),
      );
      final auth = AuthRepository(apiClient: client); // no vendor: signed out
      final sales = SalesRepository();
      final events = _Stocky(auth: auth);
      await sales.addSale(sale(id: 1));
      final cubit = OrdersCubit(
        sales,
        ProductRepository(),
        events: events,
        uploader: SaleUploadService(
          auth: auth,
          events: events,
          products: ProductRepository(),
          sales: sales,
        ),
      );

      await cubit.load();
      await pumpEventQueue();

      expect(requests, isEmpty);
    });

    test('reset forgets the rows, the filter and the assignments', () async {
      final h = harness();
      await h.cubit.load();
      h.cubit.filterByEvent(5);

      h.cubit.reset();

      expect(h.cubit.state.selectedEventId, isNull);
      expect(h.cubit.state.assignedEventIds, isNull);
      expect(h.cubit.state.records, isEmpty);
    });
  });

  group('a sale cut off by signing out', () {
    ({
      SaleUploadService uploader,
      SalesRepository sales,
      ApiClient api,
      List<http.Request> posts,
    })
    harness({required Completer<void> gate}) {
      final posts = <http.Request>[];
      late ApiClient client;
      client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.contains('mode-of-payment')) {
            await gate.future;
            return http.Response(
              jsonEncode([
                {'id': 1, 'name': 'Cash'},
              ]),
              200,
            );
          }
          if (path.endsWith('/batch-sale/')) {
            posts.add(request);
            // What the server does with no token.
            if (!(request.headers['Authorization'] ?? '').startsWith(
              'Token ',
            )) {
              return http.Response(
                '{"detail": "Authentication required."}',
                401,
              );
            }
            return http.Response(
              jsonEncode({
                'batch_results': [
                  {'status': 'created', 'sale_id': 2302},
                ],
              }),
              201,
            );
          }
          return http.Response('[]', 200);
        }),
      )..token = 'employee-b';
      final auth = AuthRepository(apiClient: client)..vendorId = 1;
      final sales = SalesRepository();
      return (
        uploader: SaleUploadService(
          auth: auth,
          events: _Stocky(auth: auth),
          products: ProductRepository(),
          sales: sales,
        ),
        sales: sales,
        api: client,
        posts: posts,
      );
    }

    test(
      'stays unsent, is not lost, and goes up under the next account',
      () async {
        final gate = Completer<void>();
        final h = harness(gate: gate);
        await h.sales.addSale(sale(id: 1760000000016, soldBy: 11));

        // B's sale starts uploading, then B signs out before it reaches the wire.
        final firstTry = h.uploader.uploadPending();
        await pumpEventQueue();
        h.api.token = null;
        gate.complete();
        final result = await firstTry;

        expect(result.uploaded, 0);
        expect(
          await h.sales.listUnsyncedSales(),
          hasLength(1),
          reason: 'the money is not lost',
        );

        // The owner signs in on the same tablet; the sale is still B's.
        h.api.token = 'owner';
        final retry = await h.uploader.uploadPending();

        expect(retry.uploaded, 1);
        final sent = jsonDecode(h.posts.last.body)['sales'] as List;
        expect(
          sent.single['sold_by'],
          11,
          reason: 'credited to B, not the owner',
        );
        expect((await h.sales.listSales()).single.serverId, 2302);
      },
    );

    test('two triggers at once send the sale once', () async {
      final gate = Completer<void>()..complete();
      final h = harness(gate: gate);
      await h.sales.addSale(sale(id: 1, soldBy: 11));

      await Future.wait([
        h.uploader.uploadPending(),
        h.uploader.uploadPending(),
      ]);

      expect(h.posts, hasLength(1));
    });
  });

  group('signing out', () {
    test('forgets what the server said but keeps the unsent sales', () async {
      final repo = SalesRepository();
      await repo.addSale(sale(id: 1, synced: true, serverId: 100));
      await repo.addSale(sale(id: 2));
      repo.debugSetRefunds([_refund()]);

      repo.clearSession();

      final left = await repo.listSales();
      expect(left.map((s) => s.id), [2], reason: 'only the unsent one stays');
      expect(await repo.listRefunds(), isEmpty);
    });

    test('the next account loads its own sales and refunds', () async {
      var gets = 0;
      final client = ApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/bazaar/event/') {
            return http.Response(jsonEncode([_event()]), 200);
          }
          if (request.url.path.endsWith('/sale/') ||
              request.url.path.endsWith('/refund/')) {
            gets++;
          }
          return http.Response('[]', 200);
        }),
      );
      final auth = AuthRepository(apiClient: client)..vendorId = 1;
      final products = ProductRepository(auth: auth);
      final events = EventRepository(auth: auth, products: products);
      final sales = SalesRepository(auth: auth, events: events);

      await sales.listSales();
      final firstLoad = gets;
      await sales.listSales();
      expect(gets, firstLoad, reason: 'already loaded for this vendor');

      sales.clearSession();
      events.invalidate();
      await sales.listSales();

      expect(
        gets,
        greaterThan(firstLoad),
        reason: 'fetched again after logout',
      );
    });

    test('bazaar assignments can be read without loading anything', () async {
      final h = _eventsHarness([
        {'id': 5, 'is_approved': true},
        {'id': 12, 'is_approved': false},
      ]);

      expect(await h.fetchAssignedEventIds(), [5]);
      expect(await EventRepository().fetchAssignedEventIds(), isNull);
    });
  });

  group('the slot for a sale that is not on the server', () {
    BazaarEvent event() => BazaarEvent(
      id: 5,
      name: 'Fair',
      companyId: 1,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 30),
      status: BazaarStatus.ongoing,
    );

    RefundRepository remote() => RefundRepository(
      auth: AuthRepository(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        ),
      )..vendorId = 1,
    );

    Future<void> pump(
      WidgetTester tester,
      TransactionRecord record,
      AppUser user,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefundSlot(
            record: record,
            event: event(),
            user: user,
            refunds: remote(),
            onRefund: () {},
          ),
        ),
      ),
    );

    testWidgets('says "Unsent" instead of silently having no button', (
      tester,
    ) async {
      await pump(tester, record(orderId: 1), employee(10));

      expect(find.byType(UnsentTag), findsOneWidget);
      expect(find.byType(RefundButton), findsNothing);
      expect(find.text('Unsent'), findsOneWidget);
    });

    testWidgets('is not shown to someone who could not refund it anyway', (
      tester,
    ) async {
      await pump(
        tester,
        record(orderId: 1),
        const AppUser(
          id: 3,
          name: 'Admin',
          email: 'a@x.com',
          role: UserRole.admin,
        ),
      );

      expect(find.byType(UnsentTag), findsNothing);
    });

    testWidgets('gives way to the button once the server has it', (
      tester,
    ) async {
      await pump(
        tester,
        TransactionRecord(
          orderId: 1,
          serverSaleId: 2302,
          customerName: 'Aaron',
          timestamp: DateTime(2026, 10, 2),
          productLabel: 'Tote Bag',
          unitPrice: 1900,
          quantity: 1,
          total: 1900,
          eventId: 5,
          paymentMethod: 'CASH',
          userId: 11,
        ),
        employee(10),
      );

      expect(find.byType(UnsentTag), findsNothing);
      expect(find.byType(RefundButton), findsOneWidget);
    });
  });
}

Map<String, dynamic> _event() => {
  'id': 5,
  'name': 'August Fair',
  'establishment': 1,
  'start_date': '2026-10-01T00:00:00Z',
  'end_date': '2026-10-30T00:00:00Z',
  'is_approved': true,
};

Refund _refund() => Refund(
  id: 1,
  saleId: 100,
  eventId: 5,
  amount: 1900,
  methodId: 1,
  methodName: 'CASH',
  reason: 'Wrong size',
  reference: '',
  issuedById: 3,
  issuedByName: 'Via',
  authorizedById: 1,
  authorizedByName: 'Lalaine',
  customerName: 'Aaron',
  createdAt: DateTime(2026, 10, 2),
);

EventRepository _eventsHarness(List<Map<String, dynamic>> events) {
  final client = ApiClient(
    baseUrl: 'https://example.test',
    httpClient: MockClient((_) async => http.Response(jsonEncode(events), 200)),
  );
  return EventRepository(auth: AuthRepository(apiClient: client)..vendorId = 1);
}

/// An event repository that always has a stock row, so uploads get past it.
class _Stocky extends EventRepository {
  _Stocky({super.auth});

  @override
  int? stockIdFor({required int eventId, required String allocationKey}) => 1;
}

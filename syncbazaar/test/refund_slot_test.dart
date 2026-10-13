import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/orders/orders_cubit.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/bazaar_event.dart';
import 'package:syncbazaar/models/refund.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/models/user.dart';
import 'package:syncbazaar/ui/screens/orders/widgets/refund_slot.dart';

/// Who sees a refund button on an Orders row, and when it is a tag instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BazaarEvent event({int id = 5, bool isFinalized = false}) => BazaarEvent(
    id: id,
    name: 'August Fair',
    companyId: 1,
    startDate: DateTime(2026, 10, 1),
    endDate: DateTime(2026, 10, 30),
    status: BazaarStatus.ongoing,
    isFinalized: isFinalized,
  );

  AppUser user(UserRole role, {List<int> assigned = const []}) => AppUser(
    id: 1,
    name: 'U',
    email: 'u@example.com',
    role: role,
    assignedEventIds: assigned,
  );

  Refund refund() => Refund(
    id: 1,
    saleId: 2302,
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

  TransactionRecord record({
    OrderStatus status = OrderStatus.completed,
    Refund? refund,
    bool onServer = true,
  }) => TransactionRecord(
    orderId: 2302,
    customerName: 'Aaron',
    timestamp: DateTime(2026, 10, 2),
    productLabel: 'Tote Bag',
    unitPrice: 1900,
    quantity: 1,
    total: 1900,
    eventId: 5,
    paymentMethod: 'CASH',
    userId: 3,
    status: status,
    refund: refund,
    serverSaleId: onServer ? 2302 : null,
  );

  RefundRepository remote({bool offline = false}) {
    SharedPreferences.setMockInitialValues({});
    var up = true;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (!up) throw http.ClientException('down');
        return http.Response(jsonEncode([]), 200);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    if (offline) {
      // One good answer is saved, then the connection goes: the next read is
      // served from the saved copy, which is the app's only offline signal.
      return _Offline(auth, () => up = false);
    }
    return RefundRepository(auth: auth);
  }

  Future<void> pump(
    WidgetTester tester, {
    required TransactionRecord record,
    required AppUser user,
    BazaarEvent? event,
    RefundRepository? refunds,
    VoidCallback? onRefund,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RefundSlot(
              record: record,
              event: event,
              user: user,
              refunds: refunds ?? remote(),
              onRefund: onRefund ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  final button = find.byType(RefundButton);

  testWidgets('the owner gets a button on a sale that can still be refunded', (
    tester,
  ) async {
    await pump(
      tester,
      record: record(),
      user: user(UserRole.owner),
      event: event(),
    );

    expect(button, findsOneWidget);
    expect(find.byTooltip('Refund'), findsOneWidget);
    expect(find.bySemanticsLabel('Refund'), findsOneWidget);
  });

  testWidgets('an assigned employee gets one, an unassigned one does not', (
    tester,
  ) async {
    await pump(
      tester,
      record: record(),
      user: user(UserRole.employee, assigned: [5]),
      event: event(),
    );
    expect(button, findsOneWidget);

    await pump(
      tester,
      record: record(),
      user: user(UserRole.employee, assigned: [9]),
      event: event(),
    );
    expect(button, findsNothing);
  });

  testWidgets('an admin never gets one', (tester) async {
    await pump(
      tester,
      record: record(),
      user: user(UserRole.admin),
      event: event(),
    );

    expect(button, findsNothing);
  });

  testWidgets('no button on a finalized bazaar, an unknown one, or a sale '
      'that is returned or not on the server', (tester) async {
    final owner = user(UserRole.owner);

    await pump(
      tester,
      record: record(),
      user: owner,
      event: event(isFinalized: true),
    );
    expect(button, findsNothing, reason: 'finalized');

    await pump(tester, record: record(), user: owner, event: null);
    expect(button, findsNothing, reason: 'bazaar not loaded');

    await pump(
      tester,
      record: record(status: OrderStatus.returned),
      user: owner,
      event: event(),
    );
    expect(button, findsNothing, reason: 'already returned');

    await pump(
      tester,
      record: record(onServer: false),
      user: owner,
      event: event(),
    );
    expect(button, findsNothing, reason: 'the server has not heard of it');
  });

  testWidgets('a refunded sale shows a tag, to everyone', (tester) async {
    for (final role in UserRole.values) {
      await pump(
        tester,
        record: record(status: OrderStatus.returned, refund: refund()),
        user: user(role, assigned: [5]),
        event: event(),
      );
      expect(find.text('Refunded'), findsOneWidget, reason: '$role');
      expect(button, findsNothing);
    }
  });

  testWidgets('the demo build has no server, so no button', (tester) async {
    await pump(
      tester,
      record: record(),
      user: user(UserRole.owner),
      event: event(),
      refunds: RefundRepository(),
    );

    expect(button, findsNothing);
  });

  testWidgets('tapping the button asks to refund this sale', (tester) async {
    var taps = 0;
    await pump(
      tester,
      record: record(),
      user: user(UserRole.owner),
      event: event(),
      onRefund: () => taps++,
    );

    await tester.tap(button);

    expect(taps, 1);
  });

  testWidgets('offline the button stays but is disabled, and says why', (
    tester,
  ) async {
    var taps = 0;
    final refunds = remote(offline: true);
    await (refunds as _Offline).goOffline();

    await pump(
      tester,
      record: record(),
      user: user(UserRole.owner),
      event: event(),
      refunds: refunds,
      onRefund: () => taps++,
    );

    expect(button, findsOneWidget);
    expect(find.byTooltip('Refunds need a connection'), findsOneWidget);
    await tester.tap(button, warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('the tag and the button both fit the fixed slot', (tester) async {
    // Measured in the app's own font: the test default is far wider than Inter
    // and would call the tag too big when it is not.
    Future<Size> sizeOf(Finder finder, TransactionRecord r) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: kRefundColumnWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: RefundSlot(
                    record: r,
                    event: event(),
                    user: user(UserRole.owner),
                    refunds: remote(),
                    onRefund: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(finder);
    }

    final tag = await sizeOf(
      find.byType(RefundedTag),
      record(status: OrderStatus.returned, refund: refund()),
    );
    final square = await sizeOf(find.byType(RefundButton), record());

    expect(tag.width, lessThanOrEqualTo(kRefundColumnWidth));
    expect(square.width, square.height, reason: 'the button is 1:1');
    expect(square.width, lessThanOrEqualTo(kRefundColumnWidth));
    expect(tester.takeException(), isNull);
  });

  group('orders cubit', () {
    Sale sale({int id = 2302, bool synced = true, int? serverId}) => Sale(
      id: id,
      serverId: serverId,
      clientUuid: 'uuid-$id',
      eventId: 5,
      productId: 1,
      customerName: 'Aaron',
      employeeId: '',
      paymentMethod: 'CASH',
      qty: 1,
      total: 1900,
      timestamp: DateTime(2026, 10, 2),
      orderStatus: OrderStatus.completed,
      synced: synced,
    );

    /// Just the sales: a refund for a sale not loaded still gets its own row.
    Iterable<TransactionRecord> sales(List<TransactionRecord> records) =>
        records.where((r) => !r.isRefund);

    Future<List<TransactionRecord>> load(
      List<Sale> sales,
      List<Refund> refunds,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final repo = SalesRepository();
      for (final s in sales) {
        await repo.addSale(s);
      }
      repo.debugSetRefunds(refunds);
      final cubit = OrdersCubit(repo, ProductRepository());
      await cubit.load();
      return cubit.state.records;
    }

    test('a refund is attached to its sale', () async {
      final records = await load(
        [sale(serverId: 2302), sale(id: 2303, serverId: 2303)],
        [refund()],
      );

      final byId = {for (final r in records) r.orderId: r};
      expect(byId[2302]?.refund?.authorizedByName, 'Lalaine');
      expect(byId[2303]?.refund, isNull);
      expect(byId[2302]?.isRefundable, isFalse);
      expect(byId[2303]?.isRefundable, isTrue);
    });

    test('a sale that never reached the server is not refundable', () async {
      final records = await load([sale(synced: false)], [refund()]);

      expect(sales(records).single.onServer, isFalse);
      expect(
        sales(records).single.refund,
        isNull,
        reason: 'its id is only local',
      );
      expect(sales(records).single.isRefundable, isFalse);
    });

    test(
      'a synced sale whose server id is unknown is not refundable',
      () async {
        // Marked synced by an older build that threw the reply away. Better no
        // button than one that addresses a sale by a number the server has
        // never seen.
        final records = await load([sale(synced: true)], [refund()]);

        expect(sales(records).single.serverSaleId, isNull);
        expect(sales(records).single.isRefundable, isFalse);
      },
    );

    test('the record carries the server id, not the local one', () async {
      final records = await load([sale(id: 1760000000123, serverId: 2302)], []);

      expect(sales(records).single.orderId, 1760000000123);
      expect(sales(records).single.serverSaleId, 2302);
    });
  });
}

/// A repository whose connection can be cut after one good answer.
class _Offline extends RefundRepository {
  _Offline(this._auth, this._cut) : super(auth: _auth);

  final AuthRepository _auth;
  final void Function() _cut;

  Future<void> goOffline() async {
    await _auth.api.get('/api/anything/');
    _cut();
    await _auth.api.get('/api/anything/');
  }
}

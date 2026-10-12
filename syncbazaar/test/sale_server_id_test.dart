import 'dart:convert';

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
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/services/sale_upload_service.dart';

/// A sale rung up on this device is known by a number made up from the clock.
/// The server has never heard of it, and a refund addressed with it asks for a
/// sale that does not exist ("No Sale matches the given query"). The id that
/// counts is the one in the reply to the sale's upload.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// What the till makes up: milliseconds since the epoch plus the product id.
  const localId = 1760000000016;

  Sale tillSale({String uuid = 'uuid-1', int id = localId}) => Sale(
    id: id,
    clientUuid: uuid,
    eventId: 5,
    productId: 16,
    variantOptionIdA: 10,
    variantOptionIdB: 7,
    customerName: 'Aaron',
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 1,
    total: 1900,
    timestamp: DateTime(2026, 10, 2),
    orderStatus: OrderStatus.completed,
    synced: false,
  );

  ({
    SaleUploadService uploader,
    RefundRepository refunds,
    SalesRepository sales,
    List<http.Request> requests,
  })
  harness({required List<Map<String, dynamic>> batchResults}) {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
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
            jsonEncode({'batch_results': batchResults}),
            201,
          );
        }
        if (path.endsWith('/refund/') && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'id': 9,
              'sale': 2302,
              'amount': '1900.00',
              'method': 1,
              'method_name': 'Cash',
              'reason': 'Wrong size',
              'authorized_by': 1,
              'authorized_by_name': 'Lalaine',
              'created_at': '2026-10-02T06:30:00Z',
            }),
            201,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    final auth = AuthRepository(apiClient: client);
    final sales = SalesRepository();
    return (
      uploader: SaleUploadService(
        auth: auth,
        events: _StockyEvents(),
        products: ProductRepository(),
        sales: sales,
      ),
      refunds: RefundRepository(auth: auth..vendorId = 1, sales: sales),
      sales: sales,
      requests: requests,
    );
  }

  test(
    'a sale made and uploaded this session is refunded by its server id',
    () async {
      final h = harness(
        batchResults: [
          {'status': 'created', 'sale_id': 2302, 'sold_by_id': 1},
        ],
      );
      await h.sales.addSale(tillSale());
      await h.uploader.uploadPending();

      final cubit = OrdersCubit(h.sales, ProductRepository());
      await cubit.load();
      final record = cubit.state.records.single;

      expect(
        record.orderId,
        localId,
        reason: 'the row keeps its local identity',
      );
      expect(record.serverSaleId, 2302);
      expect(record.isRefundable, isTrue);

      await h.refunds.approveRefund(
        eventId: record.eventId,
        saleId: record.serverSaleId!,
        amount: record.total,
        methodId: 1,
        reason: 'Wrong size',
        clientUuid: 'u',
        password: 'secret',
      );

      final post = h.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/refund/'),
      );
      expect(post.url.path, '/api/bazaar/event/5/sale/2302/refund/');
      expect(post.url.path, isNot(contains('$localId')));
    },
  );

  test('every sale in a batch gets its own id, in the order sent', () async {
    final h = harness(
      batchResults: [
        {'status': 'created', 'sale_id': 2302},
        {'status': 'created', 'sale_id': 2303},
      ],
    );
    await h.sales.addSale(tillSale(uuid: 'a', id: localId));
    await h.sales.addSale(tillSale(uuid: 'b', id: localId + 1));
    await h.uploader.uploadPending();

    final sales = await h.sales.listSales();
    expect(
      {for (final s in sales) s.clientUuid: s.serverId},
      {'a': 2302, 'b': 2303},
    );
  });

  test(
    'a repeated upload learns the id of the sale the server already holds',
    () async {
      // The first reply was lost; the retry is answered with "duplicate".
      final h = harness(
        batchResults: [
          {'status': 'duplicate', 'sale_id': 2302},
        ],
      );
      await h.sales.addSale(tillSale());
      await h.uploader.uploadPending();

      expect((await h.sales.listSales()).single.serverId, 2302);
    },
  );

  test(
    'a reply that does not line up gives no ids rather than wrong ones',
    () async {
      final h = harness(batchResults: []);
      await h.sales.addSale(tillSale(uuid: 'a'));
      await h.sales.addSale(tillSale(uuid: 'b', id: localId + 1));
      await h.uploader.uploadPending();

      final sales = await h.sales.listSales();
      expect(sales.every((s) => s.synced), isTrue);
      expect(sales.every((s) => s.serverId == null), isTrue);
    },
  );

  test('a sale read back from the server is known by the server id', () {
    final sale = Sale.fromJson({...tillSale().toJson(), 'server_id': 2302});

    expect(sale.serverId, 2302);
    expect(tillSale().serverId, isNull);
    expect(tillSale().toJson()['server_id'], isNull);
  });

  test('copying a sale keeps the id it learned', () {
    final known = tillSale().copyWith(serverId: 2302);

    expect(known.copyWith(synced: true).serverId, 2302);
  });
}

class _StockyEvents extends EventRepository {
  @override
  int? stockIdFor({required int eventId, required String allocationKey}) => 1;
}

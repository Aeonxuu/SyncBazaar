import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/services/sale_upload_service.dart';

/// A sale is recorded locally first and pushed afterwards, so the till keeps
/// working when the wifi does not. These cover what happens on the way back.
void main() {
  // Sales are written to local storage as they are recorded, so these
  // need a binding and a fake store even when they never read one back.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Sale saleWith({
    String uuid = 'uuid-1',
    int eventId = 1,
    int productId = 16,
    int? optionA = 10,
    int? optionB = 7,
    String payment = 'CASH',
    bool synced = false,
    String? origin,
  }) => Sale(
    id: 1,
    clientUuid: uuid,
    eventId: eventId,
    productId: productId,
    variantOptionIdA: optionA,
    variantOptionIdB: optionB,
    customerName: 'Walk-in',
    employeeId: '',
    originServer: origin,
    paymentMethod: payment,
    qty: 2,
    total: 3800,
    timestamp: DateTime(2026, 8, 12),
    orderStatus: OrderStatus.completed,
    synced: synced,
  );

  /// Stands in for a loaded event whose allocation knows its stock row ids.
  Future<EventRepository> eventsWithStockRow() async {
    final repository = EventRepository();
    await repository.createEvent(
      name: 'August Fair',
      companyId: 1,
      startDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 7),
      allocationsByAllocationKey: {'16:10:7': 5},
    );
    return repository;
  }

  test('sends nothing when there is nothing unsynced', () async {
    var calls = 0;
    final uploader = SaleUploadService(
      auth: AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('[]', 200);
          }),
        ),
      ),
      events: await eventsWithStockRow(),
      products: ProductRepository(),
      sales: SalesRepository(),
    );

    final result = await uploader.uploadPending();

    expect(result.uploaded, 0);
    expect(calls, 0, reason: 'an empty queue must not touch the network');
  });

  test('leaves a sale unsynced when the server cannot be reached', () async {
    final sales = SalesRepository();
    await sales.addSale(saleWith());

    final uploader = SaleUploadService(
      auth: AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
      ),
      events: await eventsWithStockRow(),
      products: ProductRepository(),
      sales: sales,
    );

    final result = await uploader.uploadPending();

    // The sale happened; only the upload failed. Losing it here would lose
    // money that is already in the till.
    expect(result.uploaded, 0);
    expect(result.isComplete, isFalse);
    expect((await sales.listUnsyncedSales()), hasLength(1));
  });

  test('a rejected batch leaves everything unsynced, not half of it', () async {
    final sales = SalesRepository();
    await sales.addSale(saleWith(uuid: 'a'));
    await sales.addSale(saleWith(uuid: 'b'));

    final uploader = SaleUploadService(
      auth: AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient(
            (request) async => request.url.path.contains('mode-of-payment')
                ? http.Response(
                    jsonEncode([
                      {'id': 1, 'name': 'Cash'},
                    ]),
                    200,
                    headers: {'content-type': 'application/json'},
                  )
                : http.Response('{"detail":"Batch failed to sync."}', 400),
          ),
        ),
      ),
      events: await eventsWithStockRow(),
      products: ProductRepository(),
      sales: sales,
    );

    final result = await uploader.uploadPending();

    // The endpoint is atomic, so a 400 means none of them landed.
    expect(result.uploaded, 0);
    expect((await sales.listUnsyncedSales()), hasLength(2));
  });

  test('holds back a sale with no stock row rather than guessing', () async {
    final sales = SalesRepository();
    // A combination this bazaar was never allocated.
    await sales.addSale(saleWith(optionA: 99, optionB: 99));

    final uploader = SaleUploadService(
      auth: AuthRepository(
        apiClient: ApiClient(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode([
                {'id': 1, 'name': 'Cash'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
      events: await eventsWithStockRow(),
      products: ProductRepository(),
      sales: sales,
    );

    final result = await uploader.uploadPending();

    // The server records a sale against a stock row; without one there is
    // nothing to attach it to, and inventing a row would put the sale against
    // stock the bazaar never had.
    expect(result.uploaded, 0);
    expect(result.skipped, 1);
    expect((await sales.listUnsyncedSales()), hasLength(1));
  });

  group('sales belonging to another server', () {
    test('are never offered to this one', () async {
      // The ids on such a sale were issued by a different database. At best
      // this server rejects them; at worst it accepts them against whatever
      // rows happen to share those numbers, which is a real sale recorded
      // against the wrong product at the wrong bazaar.
      final sales = SalesRepository();
      await sales.addSale(saleWith(origin: 'http://127.0.0.1:8000'));

      var calls = 0;
      final uploader = SaleUploadService(
        auth: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'https://elsewhere.test',
            httpClient: MockClient((_) async {
              calls++;
              return http.Response('[]', 200);
            }),
          ),
        ),
        events: await eventsWithStockRow(),
        products: ProductRepository(),
        sales: sales,
      );

      final result = await uploader.uploadPending();

      expect(calls, 0, reason: 'it must not even ask the wrong server');
      expect(result.uploaded, 0);
      expect(result.elsewhere, 1);
    });

    test('are not counted as waiting for this one', () async {
      // Counting them as pending leaves a "still waiting" figure that no
      // amount of syncing can ever clear, which teaches a cashier to ignore
      // the one message that tells them whether their takings got through.
      final sales = SalesRepository();
      await sales.addSale(saleWith(origin: 'http://127.0.0.1:8000'));

      final uploader = SaleUploadService(
        auth: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'https://elsewhere.test',
            httpClient: MockClient((_) async => http.Response('[]', 200)),
          ),
        ),
        events: await eventsWithStockRow(),
        products: ProductRepository(),
        sales: sales,
      );

      expect((await uploader.uploadPending()).skipped, 0);
    });

    test('are kept, not discarded', () async {
      // Point the app back at the server they came from and they upload as
      // normal. This is not the code that decides somebody's records are
      // worthless.
      final sales = SalesRepository();
      await sales.addSale(saleWith(origin: 'http://127.0.0.1:8000'));

      final uploader = SaleUploadService(
        auth: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'https://elsewhere.test',
            httpClient: MockClient((_) async => http.Response('[]', 200)),
          ),
        ),
        events: await eventsWithStockRow(),
        products: ProductRepository(),
        sales: sales,
      );
      await uploader.uploadPending();

      expect(await sales.listUnsyncedSales(), hasLength(1));
    });

    test('a sale with no origin recorded is not treated as foreign', () async {
      // Backward compatibility, and it is the careful direction. A real sale
      // queued offline before this existed is the only copy of that money;
      // refusing to upload it would be worse than the problem being fixed.
      //
      // It is counted as waiting rather than held back, which is what says it
      // went through the origin check and came out the other side. (It gets no
      // further here because this harness has no server-issued stock ids, which
      // is why every test in this file expects nothing uploaded.)
      final sales = SalesRepository();
      await sales.addSale(saleWith());

      final uploader = SaleUploadService(
        auth: AuthRepository(
          apiClient: ApiClient(
            baseUrl: 'https://elsewhere.test',
            httpClient: MockClient(
              (_) async => http.Response('[{"id": 1, "name": "CASH"}]', 200),
            ),
          ),
        ),
        events: await eventsWithStockRow(),
        products: ProductRepository(),
        sales: sales,
      );

      final result = await uploader.uploadPending();

      expect(result.elsewhere, 0, reason: 'unknown origin is not foreign');
      expect(result.skipped, 1);
    });
  });
}

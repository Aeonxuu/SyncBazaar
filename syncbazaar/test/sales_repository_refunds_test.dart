import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';

/// Refunds load beside the sales, and a retry of a refund whose answer was lost
/// is recognised as the refund it was rather than reported as a failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uuid = '6f1c2f0e-6a0a-4b1e-8d54-0d1a3c8f9a11';

  Map<String, dynamic> refundJson({
    String clientUuid = uuid,
    int sale = 2302,
  }) => {
    'id': 12,
    'sale': sale,
    'amount': '1900.00',
    'method': 1,
    'method_name': 'Cash',
    'reason': 'Wrong size',
    'issued_by': 3,
    'issued_by_name': 'Via',
    'authorized_by': 1,
    'authorized_by_name': 'Lalaine',
    'customer_name': 'Aaron',
    'created_at': '2026-10-02T06:30:00Z',
    'client_uuid': clientUuid,
  };

  Map<String, dynamic> eventJson() => {
    'id': 5,
    'name': 'August Fair',
    'establishment': 1,
    'start_date': '2026-10-01T00:00:00Z',
    'end_date': '2026-10-30T00:00:00Z',
    'is_approved': true,
  };

  ({
    SalesRepository sales,
    RefundRepository refunds,
    List<http.Request> requests,
  })
  harness({
    required List<Map<String, dynamic>> Function() serverRefunds,
    int refundListStatus = 200,
    http.Response? Function(http.Request)? onPost,
  }) {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'POST') {
          final custom = onPost?.call(request);
          if (custom != null) {
            return custom;
          }
        }
        if (path == '/api/bazaar/event/') {
          return http.Response(jsonEncode([eventJson()]), 200);
        }
        if (path.endsWith('/refund/') && request.method == 'GET') {
          return refundListStatus == 200
              ? http.Response(jsonEncode(serverRefunds()), 200)
              : http.Response('{"detail": "nope"}', refundListStatus);
        }
        return http.Response('[]', 200);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    final products = ProductRepository(auth: auth);
    final events = EventRepository(auth: auth, products: products);
    final sales = SalesRepository(auth: auth, events: events);
    return (
      sales: sales,
      refunds: RefundRepository(auth: auth, sales: sales),
      requests: requests,
    );
  }

  test('refunds are fetched for each loaded bazaar', () async {
    final h = harness(serverRefunds: () => [refundJson()]);

    final refunds = await h.sales.listRefunds();

    expect(refunds.single.saleId, 2302);
    expect(refunds.single.eventId, 5);
    expect(
      h.requests.map((r) => r.url.path),
      contains('/api/bazaar/event/5/refund/'),
    );
  });

  test(
    'a server that refuses the refund list still delivers the sales',
    () async {
      final h = harness(serverRefunds: () => [], refundListStatus: 404);

      expect(await h.sales.listRefunds(), isEmpty);
      expect(await h.sales.listSales(), isEmpty);
    },
  );

  test('a refresh replaces the refunds rather than adding to them', () async {
    var rows = [refundJson()];
    final h = harness(serverRefunds: () => rows);
    await h.sales.listRefunds();

    rows = [refundJson(sale: 2303), refundJson(sale: 2304)];
    await h.sales.refresh();

    expect((await h.sales.listRefunds()).map((r) => r.saleId), [2303, 2304]);
  });

  test('a successful refund reloads the list', () async {
    var rows = <Map<String, dynamic>>[];
    final h = harness(
      serverRefunds: () => rows,
      onPost: (r) {
        rows = [refundJson()];
        return http.Response(jsonEncode(refundJson()), 201);
      },
    );
    await h.sales.listRefunds();
    expect(await h.sales.listRefunds(), isEmpty);

    await h.refunds.approveRefund(
      eventId: 5,
      saleId: 2302,
      amount: 1900,
      methodId: 1,
      reason: 'Wrong size',
      clientUuid: uuid,
      password: 'secret',
    );

    expect((await h.sales.listRefunds()).single.saleId, 2302);
  });

  group('a retry after a lost answer', () {
    http.Response alreadyRefunded(http.Request r) =>
        http.Response('{"error": "This sale has already been refunded."}', 400);

    Future<void> retry(RefundRepository repo, String clientUuid) =>
        repo.approveRefund(
          eventId: 5,
          saleId: 2302,
          amount: 1900,
          methodId: 1,
          reason: 'Wrong size',
          clientUuid: clientUuid,
          password: 'secret',
        );

    test('finds its own refund and counts as success', () async {
      final h = harness(
        serverRefunds: () => [refundJson()],
        onPost: alreadyRefunded,
      );

      await retry(h.refunds, uuid);
    });

    test("somebody else's refund is still an error", () async {
      final h = harness(
        serverRefunds: () => [refundJson(clientUuid: 'someone-elses')],
        onPost: alreadyRefunded,
      );

      await expectLater(
        retry(h.refunds, uuid),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('already been refunded'),
          ),
        ),
      );
    });

    test('a refund that cannot be checked is not called a success', () async {
      final h = harness(
        serverRefunds: () => [refundJson()],
        refundListStatus: 404,
        onPost: alreadyRefunded,
      );

      await expectLater(retry(h.refunds, uuid), throwsA(isA<ApiException>()));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';

/// The first write the product repository has ever made.
///
/// Everything else in it is in-memory, so the rules here matter more than
/// usual: nothing changes locally until the server confirms it, a failure is
/// left to surface rather than swallowed, and a product-wide price change
/// says how far it got when it stops halfway. The URL and body are pinned
/// because the endpoint drops unknown keys without complaint, so a wrong key
/// returns 200 and changes nothing.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Three variants, two of one price and one of another, so a product-wide
  /// change has something real to flatten.
  List<Map<String, dynamic>> catalogue({
    Map<int, int>? stock,
    Map<int, String>? price,
  }) => [
    {
      'id': 16,
      'name': 'Nike Air Max SC',
      'vendor': 1,
      'category': null,
      'variants': [
        {
          'id': 208,
          'stock_quantity': stock?[208] ?? 20,
          'price': price?[208] ?? '1900.00',
          'product': 16,
          'attribute_values': [7, 10],
        },
        {
          'id': 209,
          'stock_quantity': stock?[209] ?? 14,
          'price': price?[209] ?? '1900.00',
          'product': 16,
          'attribute_values': [11, 7],
        },
        {
          'id': 210,
          'stock_quantity': stock?[210] ?? 5,
          'price': price?[210] ?? '2400.00',
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

  /// A repository signed in to a fake server that records every request.
  ({
    ProductRepository repo,
    List<http.Request> requests,
    void Function() goOffline,
    void Function(int) failAfterPatches,
  })
  harness({int echoedStock = 12}) {
    final requests = <http.Request>[];
    var online = true;
    int? failAfter;
    var patches = 0;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (!online) {
          throw const SocketException('no route to host');
        }
        if (request.method == 'PATCH') {
          patches++;
          if (failAfter != null && patches > failAfter!) {
            return http.Response('{"detail": "nope"}', 500);
          }
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 208,
              'stock_quantity': sent.containsKey('stock_quantity')
                  ? echoedStock
                  : 20,
              'price': sent['price'] ?? '1900.00',
              'product': 16,
              'attribute_values': [7, 10],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(catalogue()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    return (
      repo: ProductRepository(auth: auth),
      requests: requests,
      goOffline: () => online = false,
      failAfterPatches: (n) => failAfter = n,
    );
  }

  group('whether the control exists', () {
    test('not without a session', () async {
      final repo = ProductRepository();
      await repo.ensureLoaded();

      expect(repo.canQuickEdit('16:10:7'), isFalse);
    });

    test('only for rows the server issued a variant id for', () async {
      final h = harness();
      await h.repo.ensureLoaded();

      expect(h.repo.canQuickEdit('16:10:7'), isTrue);
      expect(h.repo.canQuickEdit('16:99:99'), isFalse);
    });
  });

  test(
    'every variant price of a product is available for the warning',
    () async {
      final h = harness();
      await h.repo.ensureLoaded();

      expect(h.repo.variantPricesForProduct(16), {
        '16:10:7': 1900,
        '16:11:7': 1900,
        '16:10:8': 2400,
      });
    },
  );

  group('stock', () {
    test('is written to the right variant with an absolute value', () async {
      final h = harness();
      await h.repo.ensureLoaded();

      await h.repo.updateVariantStock(allocationKey: '16:10:8', stock: 9);

      final patch = h.requests.singleWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, '/api/core/vendor/1/product/16/variant/210/');
      expect(jsonDecode(patch.body), {'stock_quantity': 9});
    });

    test(
      'the row takes the value the server echoed, not the value sent',
      () async {
        final h = harness(echoedStock: 12);
        await h.repo.ensureLoaded();

        await h.repo.updateVariantStock(allocationKey: '16:10:7', stock: 9);

        // The server is the record. If it clamped or corrected the number, the
        // table has to show what it kept, not what was asked for.
        expect(h.repo.stockFor('16:10:7'), 12);
      },
    );

    test('offline leaves the row untouched and lets the error out', () async {
      final h = harness();
      await h.repo.ensureLoaded();
      h.goOffline();

      await expectLater(
        h.repo.updateVariantStock(allocationKey: '16:10:7', stock: 9),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
      // Nothing on this tablet may show a number the server never confirmed.
      expect(h.repo.stockFor('16:10:7'), 20);
    });
  });

  group('price', () {
    test('is sent to every variant as a decimal string', () async {
      final h = harness();
      await h.repo.ensureLoaded();

      final outcome = await h.repo.updateProductPrice(
        productId: 16,
        price: 2000,
      );

      final patches = h.requests.where((r) => r.method == 'PATCH').toList();
      expect(patches.map((p) => p.url.path).toSet(), {
        '/api/core/vendor/1/product/16/variant/208/',
        '/api/core/vendor/1/product/16/variant/209/',
        '/api/core/vendor/1/product/16/variant/210/',
      });
      // "2000.00", never 2000.0 or 2e3: money, and the column is a decimal.
      for (final patch in patches) {
        expect(jsonDecode(patch.body), {'price': '2000.00'});
      }
      expect(outcome.isComplete, isTrue);
      expect(outcome.updated, 3);
    });

    test('re-fetches the catalogue afterwards rather than guessing', () async {
      final h = harness();
      await h.repo.ensureLoaded();
      final getsBefore = h.requests.where((r) => r.method == 'GET').length;

      await h.repo.updateProductPrice(productId: 16, price: 2000);

      // lowestPrice is the lowest across variants. After a write nothing here
      // can compute that honestly; the server can.
      expect(h.requests.where((r) => r.method == 'GET').length, getsBefore + 1);
    });

    test('stops at the first failure and says how far it got', () async {
      final h = harness();
      await h.repo.ensureLoaded();
      h.failAfterPatches(1);

      final outcome = await h.repo.updateProductPrice(
        productId: 16,
        price: 2000,
      );

      expect(outcome.updated, 1);
      expect(outcome.total, 3);
      expect(outcome.failure, isNotNull);
      expect(outcome.isComplete, isFalse);
      // Only two PATCHes went out: the one that worked and the one that failed.
      expect(h.requests.where((r) => r.method == 'PATCH').length, 2);
      // And the catalogue was still re-fetched, so the table shows the mix.
      expect(h.requests.last.method, 'GET');
    });

    test('a failure before anything was written skips the re-fetch', () async {
      final h = harness();
      await h.repo.ensureLoaded();
      h.goOffline();

      final outcome = await h.repo.updateProductPrice(
        productId: 16,
        price: 2000,
      );

      expect(outcome.updated, 0);
      expect(outcome.failure?.isOffline, isTrue);
    });
  });
}

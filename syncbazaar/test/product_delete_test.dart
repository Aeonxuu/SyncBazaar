import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/inventory/inventory_cubit.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';

/// Deleting a product, for real.
///
/// The local copy goes only after the server has answered, because a product
/// that vanished from the table but still exists on the server comes straight
/// back on the next refresh, which reads as the delete not working when it
/// never happened. A refusal names the product and carries the server's
/// reason. A bulk run stops at the first refusal and says how far it got.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<Map<String, dynamic>> catalogue() => [
    for (final (id, name) in [(16, 'Nike Air Max SC'), (17, 'Adidas Samba')])
      {
        'id': id,
        'name': name,
        'vendor': 1,
        'category': null,
        'variants': [
          {
            'id': id * 10,
            'stock_quantity': 5,
            'price': '1900.00',
            'product': id,
            'attribute_values': [7],
          },
        ],
        'attributes': [
          {
            'id': 2,
            'name': 'Color',
            'values': [
              {'id': 7, 'value': 'Triple White', 'attribute': 2},
            ],
          },
        ],
      },
  ];

  /// Signed in to a fake server. [refuse] names product ids answered with the
  /// 409 the real server sends for a product with recorded sales.
  ({
    ProductRepository repo,
    List<http.Request> requests,
    void Function() goOffline,
  })
  harness({Set<int> refuse = const {}}) {
    final requests = <http.Request>[];
    var online = true;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (!online) {
          throw const SocketException('no route to host');
        }
        if (request.method == 'DELETE') {
          final id = int.parse(request.url.pathSegments[5]);
          if (refuse.contains(id)) {
            return http.Response(
              jsonEncode({
                'detail':
                    'Cannot delete product because one of its variants has '
                    'recorded sales.',
              }),
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 204);
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
    );
  }

  Future<List<int>> productIds(ProductRepository repo) async =>
      (await repo.listProducts()).map((p) => p.id).toList();

  test('without a session the catalogue is not the server\'s', () async {
    expect(ProductRepository().isRemote, isFalse);
    expect(harness().repo.isRemote, isTrue);
  });

  group('one product', () {
    test('is deleted on the server first, then locally', () async {
      final h = harness();
      await h.repo.ensureLoaded();

      await h.repo.deleteProduct(16);

      final call = h.requests.singleWhere((r) => r.method == 'DELETE');
      expect(call.url.path, '/api/core/vendor/1/product/16/');
      expect(await productIds(h.repo), [17]);
    });

    test('a refusal leaves it exactly where it was', () async {
      final h = harness(refuse: {16});
      await h.repo.ensureLoaded();

      await expectLater(
        h.repo.deleteProduct(16),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('recorded sales'),
          ),
        ),
      );
      // Still there. Removing it locally would have it reappear on the next
      // refresh, which is worse than an honest refusal.
      expect(await productIds(h.repo), [16, 17]);
    });

    test('offline changes nothing and says so', () async {
      final h = harness();
      await h.repo.ensureLoaded();
      h.goOffline();

      await expectLater(
        h.repo.deleteProduct(16),
        throwsA(
          isA<ApiException>().having((e) => e.isOffline, 'offline', true),
        ),
      );
      expect(await productIds(h.repo), [16, 17]);
    });
  });

  group('several products', () {
    test('stop at the first refusal and say how far they got', () async {
      final h = harness(refuse: {17});
      final cubit = InventoryCubit(h.repo, SalesRepository());
      await cubit.load();

      final outcome = await cubit.deleteMany({
        16: 'Nike Air Max SC',
        17: 'Adidas Samba',
      });

      expect(outcome.deleted, 1);
      expect(outcome.total, 2);
      expect(outcome.stoppedAt, 'Adidas Samba');
      expect(outcome.isComplete, isFalse);
      expect(outcome.failure?.message, contains('recorded sales'));
      // The table shows what is actually gone.
      expect(cubit.state.rows.map((r) => r.product.id).toSet(), {17});
    });

    test('a clean run reports every one', () async {
      final h = harness();
      final cubit = InventoryCubit(h.repo, SalesRepository());
      await cubit.load();

      final outcome = await cubit.deleteMany({16: 'A', 17: 'B'});

      expect(outcome.isComplete, isTrue);
      expect(outcome.deleted, 2);
      expect(cubit.state.rows, isEmpty);
    });
  });
}

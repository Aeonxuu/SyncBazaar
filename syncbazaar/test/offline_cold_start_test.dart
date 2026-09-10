import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';

/// Opening the app with no connection.
///
/// This is the scenario the whole feature exists for: a stall loses signal, the
/// cashier force-closes the app or it is killed by the system, and reopening it
/// must give them something to sell from. Before caching it gave them an empty
/// catalogue, an empty bazaar list and an empty dashboard, with no way to tell
/// that from having lost the day's work.
///
/// Deliberately tested through a repository rather than the HTTP client. The
/// repositories were not changed to make this work, and that is the claim worth
/// pinning: caching at the one place every GET passes through means every one
/// of them gained this at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const products = [
    {
      'id': 4,
      'name': 'Nike Air Force 1',
      'base_price': '3500.00',
      'category': null,
      'variants': [],
    },
  ];

  /// A client that answers normally until [offline] is flipped.
  ({ApiClient client, void Function() goOffline}) connection() {
    var online = true;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (!online) {
          throw const SocketException('no route to host');
        }
        if (request.url.path.endsWith('/login/')) {
          return http.Response(
            jsonEncode({
              'token': 'tok',
              'user_id': 2,
              'role': 'OW',
              'name': 'Lalaine',
              'vendor_id': 1,
              'vendor_name': 'SV KICKz',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(products),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (client: client, goOffline: () => online = false);
  }

  test('the catalogue is still there after the network goes', () async {
    final conn = connection();
    final auth = AuthRepository(apiClient: conn.client);
    await auth.login(
      email: 'owner@syncbazaar.com',
      password: '123456',
      rememberMe: true,
    );

    // Once online, which is what fills the cache.
    final warmed = await ProductRepository(auth: auth).listProducts();
    expect(warmed, isNotEmpty);

    conn.goOffline();

    // A brand new repository, as after a force close and reopen.
    final reopened = await ProductRepository(auth: auth).listProducts();

    expect(
      reopened.map((p) => p.name),
      contains('Nike Air Force 1'),
      reason: 'an offline cold start must still have something to sell',
    );
  });

  test('the app can say the figures came from storage', () async {
    final conn = connection();
    final auth = AuthRepository(apiClient: conn.client);
    await auth.login(
      email: 'owner@syncbazaar.com',
      password: '123456',
      rememberMe: true,
    );
    await ProductRepository(auth: auth).listProducts();

    conn.goOffline();
    await ProductRepository(auth: auth).listProducts();

    expect(conn.client.servingCacheFrom, isNotNull);
  });

  test('with nothing cached, an offline start has nothing to show', () async {
    final conn = connection();
    final auth = AuthRepository(apiClient: conn.client);
    await auth.login(
      email: 'owner@syncbazaar.com',
      password: '123456',
      rememberMe: true,
    );

    conn.goOffline();

    // Never fetched, so there is nothing to fall back on. The repository keeps
    // its existing behaviour rather than inventing data.
    await expectLater(
      ProductRepository(auth: auth).listProducts(),
      throwsA(isA<ApiException>()),
    );
  });
}

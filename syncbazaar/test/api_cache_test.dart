import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/remote/api_client.dart';

/// Serving the last good answer when the server cannot be reached.
///
/// This is what lets a till open at a bazaar with no signal. Without it the
/// catalogue, the bazaars and the venues are all simply absent, which is what
/// tablet testing ran into: force-close the app offline, reopen, and the
/// dashboard has nothing on it.
///
/// The rule that keeps it honest is narrow: a cached answer stands in only when
/// the server could not be reached at all. A 403 or a 500 is the server
/// speaking, and covering that with yesterday's data would hide a real problem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ApiClient clientThat({
    required Future<http.Response> Function(http.Request request) reply,
  }) => ApiClient(
    httpClient: MockClient((request) => reply(request)),
    baseUrl: 'https://example.test',
  );

  http.Response ok(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  const venues = [
    {'id': 1, 'name': 'SM City Lucena'},
    {'id': 2, 'name': 'MSEUF Campus'},
  ];

  group('when the server cannot be reached', () {
    test('the last good answer is served instead', () async {
      var online = true;
      final client = clientThat(
        reply: (_) async {
          if (!online) throw const SocketException('offline');
          return ok(venues);
        },
      );

      await client.get('/api/core/establishment/');
      online = false;
      final result = await client.get('/api/core/establishment/');

      expect(result, hasLength(2));
      expect((result as List).first['name'], 'SM City Lucena');
    });

    test('it says the answer came from storage, and when', () async {
      var online = true;
      final client = clientThat(
        reply: (_) async {
          if (!online) throw const SocketException('offline');
          return ok(venues);
        },
      );

      await client.get('/api/core/establishment/');
      expect(client.servingCacheFrom, isNull, reason: 'that one was live');

      online = false;
      await client.get('/api/core/establishment/');

      expect(client.servingCacheFrom, isNotNull);
    });

    test('a path never fetched still fails', () async {
      final client = clientThat(
        reply: (_) async => throw const SocketException('offline'),
      );

      // Nothing stored means nothing to fall back on, and pretending otherwise
      // would be worse than the error.
      expect(
        () => client.get('/api/core/establishment/'),
        throwsA(isA<ApiException>()),
      );
    });

    test('going back online serves live data again', () async {
      var online = true;
      var served = venues;
      final client = clientThat(
        reply: (_) async {
          if (!online) throw const SocketException('offline');
          return ok(served);
        },
      );

      await client.get('/api/core/establishment/');
      online = false;
      await client.get('/api/core/establishment/');

      online = true;
      served = const [
        {'id': 1, 'name': 'SM City Lucena'},
        {'id': 2, 'name': 'MSEUF Campus'},
        {'id': 3, 'name': 'Amkor Technology'},
      ];
      final fresh = await client.get('/api/core/establishment/');

      expect(fresh, hasLength(3));
      expect(client.servingCacheFrom, isNull);
    });
  });

  group('what is never covered up', () {
    test('a refusal is not replaced by stored data', () async {
      var status = 200;
      final client = clientThat(
        reply: (_) async => status == 200
            ? ok(venues)
            : http.Response(
                jsonEncode({'error': 'Not allowed'}),
                403,
                headers: {'content-type': 'application/json'},
              ),
      );

      await client.get('/api/core/establishment/');
      status = 403;

      // The server answered. Serving yesterday's venues over a permission
      // problem would hide it until someone noticed the data was old.
      await expectLater(
        client.get('/api/core/establishment/'),
        throwsA(
          isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden),
        ),
      );
    });

    test('a server error is not replaced either', () async {
      var status = 200;
      final client = clientThat(
        reply: (_) async => status == 200
            ? ok(venues)
            : http.Response('boom', 500),
      );

      await client.get('/api/core/establishment/');
      status = 500;

      await expectLater(
        client.get('/api/core/establishment/'),
        throwsA(isA<ApiException>()),
      );
    });

    test('a failed response is never stored', () async {
      final client = clientThat(
        reply: (_) async => http.Response('boom', 500),
      );

      await expectLater(
        client.get('/api/core/establishment/'),
        throwsA(isA<ApiException>()),
      );

      // Nothing was cached, so going offline has nothing to serve.
      final offline = clientThat(
        reply: (_) async => throw const SocketException('offline'),
      );
      await expectLater(
        offline.get('/api/core/establishment/'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('keeping sessions apart', () {
    test('signing out forgets what was stored', () async {
      var online = true;
      final client = clientThat(
        reply: (_) async {
          if (!online) throw const SocketException('offline');
          return ok(venues);
        },
      );

      await client.get('/api/core/establishment/');
      await client.clearCache();
      online = false;

      await expectLater(
        client.get('/api/core/establishment/'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('each path is cached separately', () async {
    var online = true;
    final client = clientThat(
      reply: (request) async {
        if (!online) throw const SocketException('offline');
        return ok(
          request.url.path.contains('establishment')
              ? venues
              : [
                  {'id': 9, 'name': 'Cyberlympics'},
                ],
        );
      },
    );

    await client.get('/api/core/establishment/');
    await client.get('/api/bazaar/event/');
    online = false;

    expect((await client.get('/api/core/establishment/') as List).length, 2);
    expect(
      ((await client.get('/api/bazaar/event/')) as List).first['name'],
      'Cyberlympics',
    );
  });
}

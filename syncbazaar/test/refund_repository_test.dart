import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/refund_repository.dart';

/// Issuing a refund, and choosing the bazaar's refund handler.
///
/// The server is faked at the HTTP edge, so these pin what is actually sent and
/// in what order -- the grant is two calls and the change is two more, and a
/// reordering is exactly the kind of mistake that leaves a bazaar with no
/// handler or a stray request on the server.
void main() {
  const uuid = '6f1c2f0e-6a0a-4b1e-8d54-0d1a3c8f9a11';

  Map<String, dynamic> refundJson({String clientUuid = uuid}) => {
    'id': 12,
    'sale': 2302,
    'sale_return': 40,
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

  ({RefundRepository repo, List<http.Request> requests}) harness(
    http.Response Function(http.Request request) respond,
  ) {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    return (repo: RefundRepository(auth: auth), requests: requests);
  }

  Future<void> approve(RefundRepository repo, {String clientUuid = uuid}) =>
      repo.approveRefund(
        eventId: 5,
        saleId: 2302,
        amount: 1900,
        methodId: 1,
        reason: 'Wrong size',
        clientUuid: clientUuid,
        password: 'secret',
      );

  test('without a session there is no server to refund through', () async {
    final repo = RefundRepository();

    expect(repo.isRemote, isFalse);
    expect(await repo.currentHandler(5), isNull);
    expect(() => approve(repo), throwsStateError);
  });

  group('approving a refund', () {
    test('posts to the sale with the body the server expects', () async {
      final h = harness((r) => http.Response(jsonEncode(refundJson()), 201));

      final refund = await h.repo.approveRefund(
        eventId: 5,
        saleId: 2302,
        amount: 1900,
        methodId: 1,
        reason: 'Wrong size',
        reference: 'GC-1',
        clientUuid: uuid,
        password: 'secret',
      );

      final post = h.requests.singleWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/bazaar/event/5/sale/2302/refund/');
      expect(jsonDecode(post.body), {
        'amount': '1900.00',
        'method': 1,
        'reason': 'Wrong size',
        'reference': 'GC-1',
        'return_item': true,
        'authorizer_password': 'secret',
        'client_uuid': uuid,
      });
      expect(refund.authorizedByName, 'Lalaine');
      expect(refund.eventId, 5);
    });

    test('a wrong password surfaces as forbidden, not as a success', () async {
      final h = harness(
        (r) => http.Response(
          '{"error": "No refund authorization available for this event."}',
          403,
        ),
      );

      await expectLater(
        approve(h.repo),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.forbidden,
          ),
        ),
      );
    });

    test(
      'an unreachable server is an offline error, and nothing is queued',
      () async {
        final client = ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient(
            (_) async => throw http.ClientException('down'),
          ),
        );
        final repo = RefundRepository(
          auth: AuthRepository(apiClient: client)..vendorId = 1,
        );

        await expectLater(
          approve(repo),
          throwsA(
            isA<ApiException>().having((e) => e.isOffline, 'offline', true),
          ),
        );
      },
    );
  });

  group('choosing the handler', () {
    Map<String, dynamic> authRow(int id, int user, {String? revokedAt}) => {
      'id': id,
      'user': user,
      'user_name': 'Employee $user',
      'event': 5,
      'granted_at': '2026-10-01T01:00:00Z',
      'revoked_at': revokedAt,
    };

    String label(http.Request r) => '${r.method} ${r.url.path}';

    test('current handler is the active row', () async {
      final h = harness(
        (r) => http.Response(
          jsonEncode([
            authRow(1, 10, revokedAt: '2026-10-01T02:00:00Z'),
            authRow(2, 11),
          ]),
          200,
        ),
      );

      final handler = await h.repo.currentHandler(5);

      expect(handler?.userId, 11);
      expect(handler?.authorizationId, 2);
    });

    test('granting raises the request, then approves it', () async {
      final h = harness((r) {
        if (r.method == 'POST') {
          return http.Response(jsonEncode({'id': 77}), 201);
        }
        return http.Response('{}', 200);
      });

      await h.repo.grantRefundHandler(5, 11);

      expect(h.requests.map(label), [
        'POST /api/bazaar/event/5/approval/',
        'PATCH /api/bazaar/event/5/approval/77/',
      ]);
      expect(jsonDecode(h.requests[0].body), {
        'request_type': 'RA',
        'details_json': {'user_id': 11},
      });
      expect(jsonDecode(h.requests[1].body), {'status': 'AP'});
    });

    test('a refused grant deletes the request it raised and says why', () async {
      final h = harness((r) {
        if (r.method == 'POST') {
          return http.Response(jsonEncode({'id': 77}), 201);
        }
        if (r.method == 'PATCH') {
          return http.Response(
            '{"details_json": ["An employee is already authorized for this event."]}',
            400,
          );
        }
        return http.Response('', 204);
      });

      await expectLater(
        h.repo.grantRefundHandler(5, 11),
        throwsA(isA<ApiException>()),
      );

      expect(h.requests.map(label), [
        'POST /api/bazaar/event/5/approval/',
        'PATCH /api/bazaar/event/5/approval/77/',
        'DELETE /api/bazaar/event/5/approval/77/',
      ]);
    });

    test('a delete that also fails does not hide the real error', () async {
      final h = harness((r) {
        if (r.method == 'POST') {
          return http.Response(jsonEncode({'id': 77}), 201);
        }
        if (r.method == 'PATCH') {
          return http.Response('{"error": "already authorized"}', 400);
        }
        return http.Response('{"detail": "gone"}', 500);
      });

      await expectLater(
        h.repo.grantRefundHandler(5, 11),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'already authorized',
          ),
        ),
      );
    });

    test('revoking posts to the authorization row', () async {
      final h = harness((r) => http.Response('{}', 200));

      await h.repo.revokeRefundHandler(5, 2);

      expect(h.requests.single.method, 'POST');
      expect(
        h.requests.single.url.path,
        '/api/bazaar/event/5/refund-authorization/2/revoke/',
      );
    });

    test('changing the handler revokes the current one, then grants', () async {
      final h = harness((r) {
        if (r.method == 'GET') {
          return http.Response(jsonEncode([authRow(2, 10)]), 200);
        }
        if (r.url.path.endsWith('/approval/')) {
          return http.Response(jsonEncode({'id': 77}), 201);
        }
        return http.Response('{}', 200);
      });

      await h.repo.changeHandler(5, userId: 11);

      expect(h.requests.map(label), [
        'GET /api/bazaar/event/5/refund-authorization/',
        'POST /api/bazaar/event/5/refund-authorization/2/revoke/',
        'POST /api/bazaar/event/5/approval/',
        'PATCH /api/bazaar/event/5/approval/77/',
      ]);
    });

    test('choosing nobody revokes and grants nothing', () async {
      final h = harness((r) {
        if (r.method == 'GET') {
          return http.Response(jsonEncode([authRow(2, 10)]), 200);
        }
        return http.Response('{}', 200);
      });

      await h.repo.changeHandler(5, userId: null);

      expect(h.requests.map(label), [
        'GET /api/bazaar/event/5/refund-authorization/',
        'POST /api/bazaar/event/5/refund-authorization/2/revoke/',
      ]);
    });

    test(
      'picking the person who already is the handler changes nothing',
      () async {
        final h = harness(
          (r) => http.Response(jsonEncode([authRow(2, 10)]), 200),
        );

        await h.repo.changeHandler(5, userId: 10);

        expect(h.requests.map(label), [
          'GET /api/bazaar/event/5/refund-authorization/',
        ]);
      },
    );

    test('a failed grant puts the previous handler back', () async {
      var approvalPosts = 0;
      final h = harness((r) {
        if (r.method == 'GET') {
          return http.Response(jsonEncode([authRow(2, 10)]), 200);
        }
        if (r.method == 'POST' && r.url.path.endsWith('/approval/')) {
          approvalPosts++;
          return http.Response(jsonEncode({'id': 70 + approvalPosts}), 201);
        }
        if (r.method == 'PATCH' && r.url.path.endsWith('/approval/71/')) {
          return http.Response('{"error": "not assigned"}', 400);
        }
        return http.Response('{}', 200);
      });

      await expectLater(
        h.repo.changeHandler(5, userId: 11),
        throwsA(isA<ApiException>()),
      );

      final grants = h.requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/approval/'))
          .map((r) => jsonDecode(r.body)['details_json']['user_id']);
      expect(grants, [11, 10], reason: 'the old handler was restored');
    });
  });
}

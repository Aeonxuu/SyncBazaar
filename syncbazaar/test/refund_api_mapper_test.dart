import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/remote/refund_api_mapper.dart';

void main() {
  Map<String, dynamic> row({Map<String, dynamic>? extra}) => {
    'id': 12,
    'sale': 2302,
    'sale_return': 40,
    'amount': '1900.00',
    'method': 2,
    'method_name': 'gcash',
    'reason': 'Wrong size',
    'issued_by': 3,
    'issued_by_name': 'Via',
    'authorized_by': 1,
    'authorized_by_name': 'Lalaine',
    'customer_name': 'Aaron Domingo',
    'created_at': '2026-10-02T06:30:00Z',
    'client_uuid': '6f1c2f0e-6a0a-4b1e-8d54-0d1a3c8f9a11',
    ...?extra,
  };

  group('reading a refund', () {
    test('reads every field the Orders screen shows', () {
      final refund = RefundApiMapper.refundFromJson(row(), eventId: 111);

      expect(refund.id, 12);
      expect(refund.saleId, 2302);
      expect(refund.eventId, 111, reason: 'the list is per bazaar');
      expect(refund.amount, 1900);
      expect(refund.methodId, 2);
      expect(refund.methodName, 'GCASH', reason: 'sales upper-case theirs');
      expect(refund.reason, 'Wrong size');
      expect(refund.issuedByName, 'Via');
      expect(refund.authorizedById, 1);
      expect(refund.authorizedByName, 'Lalaine');
      expect(refund.customerName, 'Aaron Domingo');
      expect(refund.clientUuid, '6f1c2f0e-6a0a-4b1e-8d54-0d1a3c8f9a11');
      expect(refund.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 6, 30));
    });

    test('has no reference until the server starts sending one', () {
      expect(
        RefundApiMapper.refundFromJson(row(), eventId: 1).reference,
        isEmpty,
      );
    });

    test('reads the reference as soon as it is there', () {
      final refund = RefundApiMapper.refundFromJson(
        row(extra: {'reference': 'GC-99812'}),
        eventId: 1,
      );

      expect(refund.reference, 'GC-99812');
    });

    test('a list keeps every row and tags each with its bazaar', () {
      final refunds = RefundApiMapper.refundsFromPayload([
        row(),
        row(extra: {'id': 13, 'sale': 2303}),
      ], eventId: 7);

      expect(refunds.map((r) => r.saleId), [2302, 2303]);
      expect(refunds.every((r) => r.eventId == 7), isTrue);
    });
  });

  group('the request body', () {
    Map<String, dynamic> body({String? reference}) =>
        RefundApiMapper.createBody(
          amount: 1900,
          methodId: 2,
          reason: 'Wrong size',
          reference: reference,
          clientUuid: 'abc',
          authorizerPassword: 'secret',
        );

    test('always returns the item to stock', () {
      expect(body()['return_item'], isTrue);
    });

    test('sends the amount as a two-place decimal string', () {
      expect(body()['amount'], '1900.00');
      expect(RefundApiMapper.moneyString(1583.33), '1583.33');
      expect(RefundApiMapper.moneyString(1583.3333333), '1583.33');
    });

    test('carries the method, reason, uuid and password', () {
      final sent = body();

      expect(sent['method'], 2);
      expect(sent['reason'], 'Wrong size');
      expect(sent['client_uuid'], 'abc');
      expect(sent['authorizer_password'], 'secret');
    });

    test('leaves the reference out when there is none', () {
      expect(body().containsKey('reference'), isFalse);
      expect(body(reference: '  ').containsKey('reference'), isFalse);
    });

    test('sends a reference when there is one, trimmed', () {
      expect(body(reference: ' GC-1 ')['reference'], 'GC-1');
    });
  });

  group('the refund handler', () {
    Map<String, dynamic> auth(int id, int user, {String? revokedAt}) => {
      'id': id,
      'user': user,
      'user_name': 'Employee $user',
      'event': 5,
      'granted_at': '2026-10-01T01:00:00Z',
      'revoked_at': revokedAt,
    };

    test('is the one row that has not been revoked', () {
      final handler = RefundApiMapper.activeHandlerFromPayload([
        auth(1, 10, revokedAt: '2026-10-01T02:00:00Z'),
        auth(2, 11),
      ]);

      expect(handler?.authorizationId, 2);
      expect(handler?.userId, 11);
      expect(handler?.userName, 'Employee 11');
    });

    test('is nobody when every row was revoked, or there are none', () {
      expect(
        RefundApiMapper.activeHandlerFromPayload([
          auth(1, 10, revokedAt: '2026-10-01T02:00:00Z'),
        ]),
        isNull,
      );
      expect(RefundApiMapper.activeHandlerFromPayload([]), isNull);
    });

    test('asks for the grant with the refund-authorization request code', () {
      expect(RefundApiMapper.grantRequestBody(11), {
        'request_type': 'RA',
        'details_json': {'user_id': 11},
      });
    });
  });
}

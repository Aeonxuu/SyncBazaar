import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/services/sale_upload_service.dart';

/// The exact JSON a sale is uploaded as.
///
/// Worth pinning separately from the service, because the service's own tests
/// cannot reach a successful POST without a server handing out stock row ids.
/// That left the payload itself unchecked, and the payload is where a wrong
/// field name costs nothing visible: the batch endpoint builds a payment from
/// the keys it knows and drops the rest without complaint, so a mistake here
/// returns 201 and records nothing.
void main() {
  const methodIds = {'CASH': 1, 'GCASH': 2, 'QR PH': 3};

  Sale sale({
    String reference = '',
    ReferenceSource? source,
    String method = 'QR PH',
  }) => Sale(
    id: 1,
    clientUuid: 'uuid-1',
    eventId: 13,
    productId: 1003,
    customerName: 'Walk-in',
    employeeId: reference,
    referenceSource: source,
    paymentMethod: method,
    qty: 2,
    total: 3800,
    timestamp: DateTime(2026, 9, 12),
    orderStatus: OrderStatus.completed,
    synced: false,
  );

  Map<String, dynamic> payloadFor(Sale s) =>
      saleUploadPayload(sale: s, stockId: 42, methodIds: methodIds);

  group('how the reference arrived', () {
    test('a gateway reference is sent as AU', () {
      // Two letters, not the word. Payment.required_information_source is a
      // CharField(max_length=2) with AU/MA choices, so "automatic" would not
      // even fit the column.
      final body = payloadFor(
        sale(reference: 'pay_abc', source: ReferenceSource.automatic),
      );

      expect(body['required_information_source'], 'AU');
      expect(body['required_information'], 'pay_abc');
    });

    test('a typed reference is sent as MA', () {
      final body = payloadFor(
        sale(reference: '9988028350', source: ReferenceSource.manual),
      );

      expect(body['required_information_source'], 'MA');
    });

    test('an unrecorded source is left out entirely', () {
      // Every sale queued before the app tracked this. The column is nullable
      // so unknown can stay unknown; sending a default would invent the
      // evidence the field exists to provide.
      final body = payloadFor(sale(reference: 'pay_abc'));

      expect(body.containsKey('required_information_source'), isFalse);
      expect(body['required_information'], 'pay_abc');
    });

    test('a cash sale sends neither', () {
      final body = payloadFor(sale(method: 'CASH'));

      expect(body.containsKey('required_information'), isFalse);
      expect(body.containsKey('required_information_source'), isFalse);
    });

    test('a source with no reference to describe is left out', () {
      // Should not arise, but a source alone describes nothing, and a payment
      // row claiming a gateway confirmed a reference it does not hold is worse
      // than one that says nothing at all.
      final body = payloadFor(sale(source: ReferenceSource.automatic));

      expect(body.containsKey('required_information_source'), isFalse);
    });

    test('the codes are the backend\'s, not the export\'s wording', () {
      // These are separately owned. The export label can be reworded whenever
      // it reads better; this cannot, without uploads starting to fail.
      expect(ReferenceSource.automatic.wireCode, 'AU');
      expect(ReferenceSource.manual.wireCode, 'MA');
      expect(ReferenceSource.automatic.label, 'Automatic');
    });
  });

  group('the rest of the payload', () {
    test('is unchanged by any of this', () {
      // The fields the endpoint has always required. A refactor that quietly
      // dropped one of these would fail every upload.
      final body = payloadFor(
        sale(reference: 'pay_abc', source: ReferenceSource.automatic),
      );

      expect(body['client_uuid'], 'uuid-1');
      expect(body['event_stock'], 42);
      expect(body['customer_name'], 'Walk-in');
      expect(body['quantity'], 2);
      expect(body['order_status'], 'CM');
      expect(body['synced'], true);
      expect(body['payment_method'], 3);
    });

    test('a method the server does not know is left unnamed', () {
      // Rather than sending a name where the endpoint expects a foreign key.
      final body = payloadFor(sale(method: 'BARTER'));

      expect(body.containsKey('payment_method'), isFalse);
    });
  });
}

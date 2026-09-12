import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/sale.dart';

/// A queued sale belongs to the database that issued the ids it names.
///
/// The app is pointed at different backends by a launch flag, and the ids on a
/// sale mean nothing outside the one it was rung up against. Letting the queue
/// drain into whatever happens to be connected offers a server sales describing
/// rows it has never heard of, or worse, rows it has that hold something else.
/// The session already refused to travel between backends; the queue did not.
void main() {
  Sale sale({String? origin, bool synced = false}) => Sale(
    id: 1,
    clientUuid: 'abc-123',
    eventId: 13,
    productId: 1003,
    customerName: 'Walk-in',
    employeeId: 'pay_abc',
    referenceSource: ReferenceSource.automatic,
    originServer: origin,
    paymentMethod: 'QR PH',
    qty: 1,
    total: 1900,
    timestamp: DateTime(2026, 9, 12),
    orderStatus: OrderStatus.completed,
    synced: synced,
  );

  test('the origin survives the queue', () {
    // The queue outlives a force-close, so anything not written down is gone
    // by the time the sale is uploaded, which is the only moment it matters.
    final restored = Sale.fromJson(
      sale(origin: 'http://127.0.0.1:8000').toJson(),
    );

    expect(restored.originServer, 'http://127.0.0.1:8000');
  });

  test('a sale queued before this was recorded has no origin', () {
    final old = sale(origin: 'http://127.0.0.1:8000').toJson()
      ..remove('origin_server');

    expect(Sale.fromJson(old).originServer, isNull);
  });

  test('marking a sale synced does not move it to another server', () {
    expect(
      sale(origin: 'http://127.0.0.1:8000').copyWith(synced: true).originServer,
      'http://127.0.0.1:8000',
    );
  });

  test('copyWith can set an origin on a sale that has none', () {
    expect(
      sale().copyWith(originServer: 'https://example.test').originServer,
      'https://example.test',
    );
  });

  test('copyWith never relabels a sale that already has one', () {
    // The case that would quietly undo the whole protection: a sale restored
    // from the queue being stamped with whatever is connected now.
    final moved = sale(
      origin: 'http://127.0.0.1:8000',
    ).copyWith(originServer: 'https://syncbazaar-backend.onrender.com');

    expect(moved.originServer, 'http://127.0.0.1:8000');
  });
}

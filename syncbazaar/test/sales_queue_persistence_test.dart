import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/models/sale.dart';

/// A sale rung up without signal must survive the app closing.
///
/// The queue used to be a plain list in memory, and it is the only copy of a
/// sale until the server confirms it. A crash, a force-close, or Android
/// reclaiming memory took a day of takings with it and left no trace: the one
/// defect in this app that destroyed real money.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Sale sale({
    required String uuid,
    int id = 1,
    double total = 2500,
    bool synced = false,
  }) => Sale(
    id: id,
    clientUuid: uuid,
    eventId: 13,
    productId: 4,
    variantOptionIdA: 21,
    customerName: 'Walk-in',
    soldById: 2,
    employeeId: '',
    paymentMethod: 'CASH',
    qty: 2,
    total: total,
    timestamp: DateTime(2026, 9, 9, 14, 30),
    orderStatus: OrderStatus.completed,
    synced: synced,
  );

  /// A second repository over the same storage: what the next launch sees.
  SalesRepository reopened() => SalesRepository();

  group('surviving a relaunch', () {
    test('a queued sale is still there', () async {
      await SalesRepository().addSale(sale(uuid: 'a'));

      final pending = await reopened().listUnsyncedSales();

      expect(pending, hasLength(1));
      expect(pending.single.clientUuid, 'a');
    });

    test('every field comes back intact', () async {
      await SalesRepository().addSale(sale(uuid: 'a'));

      final restored = (await reopened().listUnsyncedSales()).single;

      expect(restored.clientUuid, 'a');
      expect(restored.eventId, 13);
      expect(restored.productId, 4);
      expect(restored.variantOptionIdA, 21);
      expect(restored.qty, 2);
      expect(restored.total, 2500);
      expect(restored.paymentMethod, 'CASH');
      expect(restored.soldById, 2);
      expect(restored.timestamp, DateTime(2026, 9, 9, 14, 30));
      expect(restored.orderStatus, OrderStatus.completed);
      // The two that matter most: without the uuid the server would record a
      // resent sale twice, and without the flag it would never be sent at all.
      expect(restored.synced, isFalse);
    });

    test('several sales keep their order', () async {
      final repository = SalesRepository();
      for (final id in ['a', 'b', 'c']) {
        await repository.addSale(sale(uuid: id));
      }

      final pending = await reopened().listUnsyncedSales();

      expect(pending.map((s) => s.clientUuid), ['a', 'b', 'c']);
    });
  });

  group('what is kept and what is dropped', () {
    test('a confirmed sale is not queued again', () async {
      final repository = SalesRepository();
      await repository.addSale(sale(uuid: 'a'));
      await repository.addSale(sale(uuid: 'b', id: 2));

      await repository.markSynced({'a'});

      final pending = await reopened().listUnsyncedSales();
      expect(pending.map((s) => s.clientUuid), ['b']);
    });

    test('confirming everything empties the queue', () async {
      final repository = SalesRepository();
      await repository.addSale(sale(uuid: 'a'));
      await repository.markSynced({'a'});

      expect(await reopened().listUnsyncedSales(), isEmpty);
    });

    test('a sale that was already sent is never stored', () async {
      await SalesRepository().addSale(sale(uuid: 'a', synced: true));

      expect(await reopened().listUnsyncedSales(), isEmpty);
    });
  });

  group('bad stored data', () {
    test('unreadable storage does not stop the till opening', () async {
      SharedPreferences.setMockInitialValues({
        'sales.pendingUpload': 'this is not json',
      });

      expect(await reopened().listUnsyncedSales(), isEmpty);
    });

    test('one corrupt row does not take the rest with it', () async {
      final good = sale(uuid: 'good').toJson();
      SharedPreferences.setMockInitialValues({
        'sales.pendingUpload':
            '[{"client_uuid":"broken"},${_encode(good)}]',
      });

      final pending = await reopened().listUnsyncedSales();

      expect(pending, hasLength(1));
      expect(pending.single.clientUuid, 'good');
    });
  });

  test('restoring twice does not duplicate the queue', () async {
    await SalesRepository().addSale(sale(uuid: 'a'));

    final repository = reopened();
    await repository.listUnsyncedSales();
    await repository.addSale(sale(uuid: 'b', id: 2));

    final pending = await repository.listUnsyncedSales();
    expect(pending.map((s) => s.clientUuid), ['a', 'b']);
  });
}

String _encode(Map<String, dynamic> row) {
  final parts = row.entries.map((e) {
    final v = e.value;
    if (v == null) return '"${e.key}":null';
    if (v is num || v is bool) return '"${e.key}":$v';
    return '"${e.key}":"$v"';
  });
  return '{${parts.join(',')}}';
}

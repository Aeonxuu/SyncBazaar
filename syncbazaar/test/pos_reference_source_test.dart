import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/pos/pos_cubit.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/orders_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/models/sale.dart';

/// Which payment methods the gateway handles, and how a reference is marked.
///
/// The first question decides where a customer's money lands, so it is not a
/// matter of taste: a stall's own saved GCash code pays the stall, while a
/// gateway code pays the gateway's account. The second is bookkeeping that only
/// matters months later, when a figure is questioned and nobody remembers
/// whether the reference was confirmed or typed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PosCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cubit = PosCubit(
      EventRepository(),
      ProductRepository(),
      SalesRepository(),
      OrdersRepository(),
      SettingsRepository(),
    );
  });

  group('which methods the gateway handles', () {
    bool automaticFor(String method) =>
        PosState(selectedPaymentMethod: method).supportsAutomaticQr;

    test('the gateway method is recognised however it is written', () {
      // A vendor types this into Venues & Terms by hand, so the spacing and
      // punctuation are whatever they felt like that day.
      expect(automaticFor('QR PH'), isTrue);
      expect(automaticFor('QRPH'), isTrue);
      expect(automaticFor('qr-ph'), isTrue);
      expect(automaticFor('  Qr Ph  '), isTrue);
      expect(automaticFor('PayMongo'), isTrue);
    });

    test('a stall\'s own wallet is left alone', () {
      // The important case. GCASH here is the stall's own code, paying the
      // stall directly; routing it through the gateway would send a customer's
      // money to a different account entirely, and in test mode nobody would
      // notice until it was real.
      expect(automaticFor('GCASH'), isFalse);
      expect(automaticFor('MAYA'), isFalse);
      expect(automaticFor('CASH'), isFalse);
      expect(automaticFor(''), isFalse);
    });

    test('a method that merely mentions the gateway is not one', () {
      // Matching loosely here would be the same mistake in a different shape.
      expect(automaticFor('GCASH VIA QR PH'), isFalse);
    });
  });

  group('marking how a reference arrived', () {
    test('anything typed is manual', () {
      cubit.updatePaymentExtraFieldValue('0917-typed-by-hand');

      expect(cubit.state.paymentExtraFieldValue, '0917-typed-by-hand');
      expect(cubit.state.referenceSource, ReferenceSource.manual);
    });

    test('what the gateway confirms is automatic', () {
      cubit.recordAutomaticReference('pay_abc123');

      expect(cubit.state.paymentExtraFieldValue, 'pay_abc123');
      expect(cubit.state.referenceSource, ReferenceSource.automatic);
    });

    test('nothing is claimed before a reference exists', () {
      expect(cubit.state.referenceSource, isNull);
    });

    test('switching payment method drops the mark with the reference', () {
      cubit.recordAutomaticReference('pay_abc123');

      cubit.updatePaymentMethod('CASH');

      // The reference is cleared here already; a source left behind would
      // describe a reference that is gone.
      expect(cubit.state.paymentExtraFieldValue, '');
      expect(cubit.state.referenceSource, isNull);
    });

    test('a typed reference after an automatic one is manual again', () {
      // The cashier switching to the fallback mid-sale. Leaving this automatic
      // would put the gateway's name to something nobody confirmed.
      cubit.recordAutomaticReference('pay_abc123');

      cubit.updatePaymentExtraFieldValue('typed-instead');

      expect(cubit.state.referenceSource, ReferenceSource.manual);
    });
  });

  group('carrying the mark with the sale', () {
    Sale saleWith(ReferenceSource? source) => Sale(
      id: 1,
      clientUuid: 'abc-123',
      eventId: 1,
      productId: 1,
      customerName: 'Walk-in',
      employeeId: 'pay_abc123',
      referenceSource: source,
      paymentMethod: 'QR PH',
      qty: 1,
      total: 100,
      timestamp: DateTime(2026, 9, 12),
      orderStatus: OrderStatus.completed,
      synced: false,
    );

    test('it survives sitting in the offline queue', () {
      // A sale waits here through a force-close and a flat battery, so
      // anything not written down is lost by the time it uploads.
      final restored = Sale.fromJson(
        saleWith(ReferenceSource.automatic).toJson(),
      );

      expect(restored.referenceSource, ReferenceSource.automatic);
    });

    test('a sale queued before this existed stays unmarked', () {
      final old = saleWith(ReferenceSource.manual).toJson()
        ..remove('reference_source');

      // Not defaulted to manual: calling an unknown reference "typed by hand"
      // invents the very evidence the field exists to record.
      expect(Sale.fromJson(old).referenceSource, isNull);
    });

    test('marking a sale synced keeps the mark', () {
      expect(
        saleWith(ReferenceSource.manual).copyWith(synced: true).referenceSource,
        ReferenceSource.manual,
      );
    });
  });
}

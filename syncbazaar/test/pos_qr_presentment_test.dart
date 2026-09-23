import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/pos/pos_cubit.dart';
import 'package:syncbazaar/data/remote/api_client.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/orders_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/data/repositories/vendor_payment_method_repository.dart';
import 'package:syncbazaar/models/user.dart';

/// Whether the till offers a QR, and where it comes from.
///
/// Used to ask a second, sharper question: *whose* QR, since a method was
/// chosen per venue and two venues could both have a "GCASH" with two
/// different codes -- taking one from a union list risked handing a stall
/// the other venue's code. That risk is gone by construction now: a method
/// belongs to the vendor, one list shared by every venue and bazaar, so
/// there is only ever one GCASH code to offer. What is left to check is
/// simpler -- that the vendor's own QR reaches the till at all, identically
/// everywhere, and that a method with none presents none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = AppUser(
    id: 1,
    name: 'Lalaine',
    email: 'l@example.com',
    role: UserRole.owner,
  );

  List<Map<String, dynamic>> vendorMethods({String? gcashQrUrl}) => [
    {
      'id': 1,
      'mode_of_payment_name': 'Cash',
      'qr_code_image_url': null,
      'vendor': 1,
      'mode_of_payment': 1,
    },
    {
      'id': 2,
      'mode_of_payment_name': 'GCash',
      'qr_code_image_url': gcashQrUrl,
      'vendor': 1,
      'mode_of_payment': 2,
    },
  ];

  const catalog = [
    {'id': 1, 'name': 'Cash', 'required_information_name': null},
    {'id': 2, 'name': 'GCash', 'required_information_name': 'GCash Ref No.'},
  ];

  ({PosCubit cubit, EventRepository events}) harness({String? gcashQrUrl}) {
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/mode-of-payment/')) {
          return http.Response(jsonEncode(catalog), 200);
        }
        if (path.endsWith('/payment-method/')) {
          return http.Response(
            jsonEncode(vendorMethods(gcashQrUrl: gcashQrUrl)),
            200,
          );
        }
        if (path.endsWith('/establishment/')) {
          return http.Response('[]', 200);
        }
        return http.Response('[]', 200);
      }),
    );
    final auth = AuthRepository(apiClient: client)..vendorId = 1;
    final events = EventRepository();
    final cubit = PosCubit(
      events,
      ProductRepository(),
      SalesRepository(),
      OrdersRepository(),
      SettingsRepository(auth: auth),
      VendorPaymentMethodRepository(auth: auth),
    );
    return (cubit: cubit, events: events);
  }

  Future<void> openBazaar(
    ({PosCubit cubit, EventRepository events}) h,
    String name,
  ) async {
    await h.cubit.load(owner);
    final event = h.cubit.state.events.firstWhere((e) => e.name == name);
    await h.cubit.selectEvent(event);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cash alone presents no QR', () async {
    final h = harness(gcashQrUrl: 'https://cdn.example/gcash.png');
    await h.events.createEvent(
      name: 'Lucena Bazaar',
      companyId: 1,
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
      acceptedPaymentMethods: const ['CASH', 'GCASH'],
    );
    await openBazaar(h, 'Lucena Bazaar');
    h.cubit.updatePaymentMethod('CASH');

    expect(h.cubit.state.requiresQrPresentment, isFalse);
    expect(h.cubit.state.selectedPaymentQr, isNull);
  });

  test('a method with a QR presents the vendor\'s own code', () async {
    final h = harness(gcashQrUrl: 'https://cdn.example/gcash.png');
    await h.events.createEvent(
      name: 'Lucena Bazaar',
      companyId: 1,
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
      acceptedPaymentMethods: const ['CASH', 'GCASH'],
    );
    await openBazaar(h, 'Lucena Bazaar');
    h.cubit.updatePaymentMethod('GCASH');

    expect(h.cubit.state.requiresQrPresentment, isTrue);
    expect(h.cubit.state.selectedPaymentQr, 'https://cdn.example/gcash.png');
  });

  test('every bazaar sees the identical code, by construction', () async {
    // The old risk was one venue's code leaking into another's bazaar. There
    // is only one code to offer now, so the assertion worth keeping is that
    // both bazaars agree, rather than that they differ correctly.
    final h = harness(gcashQrUrl: 'https://cdn.example/gcash.png');
    for (final name in ['Lucena Bazaar', 'Makati Bazaar']) {
      await h.events.createEvent(
        name: name,
        companyId: 1,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
        acceptedPaymentMethods: const ['CASH', 'GCASH'],
      );
    }

    await openBazaar(h, 'Lucena Bazaar');
    h.cubit.updatePaymentMethod('GCASH');
    final lucenaQr = h.cubit.state.selectedPaymentQr;

    await openBazaar(h, 'Makati Bazaar');
    h.cubit.updatePaymentMethod('GCASH');
    final makatiQr = h.cubit.state.selectedPaymentQr;

    expect(lucenaQr, isNotNull);
    expect(lucenaQr, makatiQr);
  });

  test('a method with no QR uploaded presents none', () async {
    final h = harness();
    await h.events.createEvent(
      name: 'Bare Bazaar',
      companyId: 1,
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
      acceptedPaymentMethods: const ['CASH', 'GCASH'],
    );
    await openBazaar(h, 'Bare Bazaar');
    h.cubit.updatePaymentMethod('GCASH');

    expect(h.cubit.state.requiresQrPresentment, isFalse);
    // The reference field still applies; only the QR step is absent.
    expect(h.cubit.state.requiresPaymentExtraField, isTrue);
  });
}

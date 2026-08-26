import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/pos/pos_cubit.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/orders_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/models/company.dart';
import 'package:syncbazaar/models/user.dart';

/// Whether the till offers a QR, and crucially *whose* QR it offers.
///
/// The second question is the dangerous one. The POS builds its payment menu
/// from a union of every venue's methods, matched by name, so two bazaars that
/// both accept GCASH look identical at that level. Taking the QR from that
/// union would hand a stall the other venue's code and send a customer's money
/// to the wrong account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = AppUser(
    id: 1,
    name: 'Lalaine',
    email: 'l@example.com',
    role: UserRole.owner,
  );

  /// Stand-ins for two different sellers' codes; contents never decoded here,
  /// only tracked to see which one comes back.
  final lucenaQr = Uint8List.fromList(List.filled(64, 11));
  final makatiQr = Uint8List.fromList(List.filled(64, 22));

  late EventRepository events;
  late SettingsRepository settings;
  late PosCubit cubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    events = EventRepository();
    settings = SettingsRepository();
    cubit = PosCubit(
      events,
      ProductRepository(),
      SalesRepository(),
      OrdersRepository(),
      settings,
    );
  });

  Company venue(int id, String name) => Company(
    id: id,
    name: name,
    address: '',
    contact: '',
    incentivePercent: 0,
    bufferPercent: 0,
  );

  /// Two venues that both take GCASH, each with its own code.
  Future<void> seedTwoVenues() async {
    await settings.upsertCompanyConfiguration(
      company: venue(1, 'SM City Lucena'),
      paymentMethods: [
        const PaymentMethodMeta(name: 'CASH'),
        PaymentMethodMeta(
          name: 'GCASH',
          extraFieldLabel: 'GCash Ref No.',
          qrImageBytes: lucenaQr,
        ),
      ],
    );
    await settings.upsertCompanyConfiguration(
      company: venue(2, 'Ayala Makati'),
      paymentMethods: [
        const PaymentMethodMeta(name: 'CASH'),
        PaymentMethodMeta(
          name: 'GCASH',
          extraFieldLabel: 'GCash Ref No.',
          qrImageBytes: makatiQr,
        ),
      ],
    );

    final now = DateTime.now();
    for (final (id, name) in [(1, 'Lucena Bazaar'), (2, 'Makati Bazaar')]) {
      await events.createEvent(
        name: name,
        companyId: id,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
        acceptedPaymentMethods: const ['CASH', 'GCASH'],
      );
    }
  }

  Future<void> openBazaar(String name) async {
    await cubit.load(owner);
    final event = cubit.state.events.firstWhere((e) => e.name == name);
    await cubit.selectEvent(event);
  }

  test('cash alone presents no QR', () async {
    await seedTwoVenues();
    await openBazaar('Lucena Bazaar');
    cubit.updatePaymentMethod('CASH');

    expect(cubit.state.requiresQrPresentment, isFalse);
    expect(cubit.state.selectedPaymentQr, isNull);
  });

  test('a method with a QR presents it', () async {
    await seedTwoVenues();
    await openBazaar('Lucena Bazaar');
    cubit.updatePaymentMethod('GCASH');

    expect(cubit.state.requiresQrPresentment, isTrue);
    expect(cubit.state.selectedPaymentQr, lucenaQr);
  });

  test('each bazaar gets its own venue QR, not the other one', () async {
    await seedTwoVenues();

    await openBazaar('Lucena Bazaar');
    cubit.updatePaymentMethod('GCASH');
    expect(cubit.state.selectedPaymentQr, lucenaQr);

    await openBazaar('Makati Bazaar');
    cubit.updatePaymentMethod('GCASH');
    expect(
      cubit.state.selectedPaymentQr,
      makatiQr,
      reason: 'the till must never show another venue\'s payment code',
    );
  });

  test('a venue with no QR uploaded presents none', () async {
    await settings.upsertCompanyConfiguration(
      company: venue(3, 'Bare Venue'),
      paymentMethods: [
        const PaymentMethodMeta(name: 'CASH'),
        const PaymentMethodMeta(name: 'GCASH', extraFieldLabel: 'Ref No.'),
      ],
    );
    final now = DateTime.now();
    await events.createEvent(
      name: 'Bare Bazaar',
      companyId: 3,
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now.add(const Duration(days: 1)),
      acceptedPaymentMethods: const ['CASH', 'GCASH'],
    );

    await openBazaar('Bare Bazaar');
    cubit.updatePaymentMethod('GCASH');

    expect(cubit.state.requiresQrPresentment, isFalse);
    // The reference field still applies; only the QR step is absent.
    expect(cubit.state.requiresPaymentExtraField, isTrue);
  });

  test('an uploaded QR re-attaches after a restart', () async {
    await seedTwoVenues();

    // A fresh repository over the same stored preferences, standing in for the
    // app reopening on the next trading day. Venues and their method lists are
    // *not* restored here: those come from the API (or are re-entered), which
    // is exactly why the QR is stored separately. So the venue is registered
    // again with no QR attached, the way a reload would deliver it.
    final reopened = SettingsRepository();
    await reopened.upsertCompanyConfiguration(
      company: venue(1, 'SM City Lucena'),
      paymentMethods: [
        const PaymentMethodMeta(name: 'CASH'),
        const PaymentMethodMeta(name: 'GCASH', extraFieldLabel: 'GCash Ref No.'),
      ],
    );

    final byCompany = await reopened.paymentMethodsByCompanyId();
    final gcash = byCompany[1]!.firstWhere((m) => m.name == 'GCASH');

    // Re-attached from local storage even though the incoming method carried
    // no image: an API refresh must not cost the seller their QR.
    expect(gcash.qrImageBytes, lucenaQr);
  });
}

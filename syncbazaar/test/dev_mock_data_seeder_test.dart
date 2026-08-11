import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/data/repositories/event_repository.dart';
import 'package:syncbazaar/data/repositories/orders_repository.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/data/repositories/sales_repository.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/dev/dev_mock_data_seeder.dart';
import 'package:syncbazaar/models/bazaar_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'DevMockDataSeeder loads assets/dev/mock_data.json without error',
    () async {
      SharedPreferences.setMockInitialValues({});
      final eventRepository = EventRepository();
      final productRepository = ProductRepository();
      final salesRepository = SalesRepository();
      final ordersRepository = OrdersRepository();
      final settingsRepository = SettingsRepository();
      final authRepository = AuthRepository();

      await DevMockDataSeeder(
        eventRepository: eventRepository,
        productRepository: productRepository,
        salesRepository: salesRepository,
        ordersRepository: ordersRepository,
        settingsRepository: settingsRepository,
        authRepository: authRepository,
      ).seed();

      final companies = await settingsRepository.listCompanies();
      final products = await productRepository.listProducts();
      final events = await eventRepository.listAll();
      final sales = await salesRepository.listSales();
      final orders = await ordersRepository.listOrders();

      expect(companies.length, greaterThanOrEqualTo(3));
      expect(products.length, 12);
      expect(events.length, 12);
      expect(sales, isNotEmpty);
      expect(orders.length, sales.length);

      final ongoing = events
          .where((e) => e.status == BazaarStatus.ongoing)
          .length;
      final upcoming = events
          .where((e) => e.status == BazaarStatus.upcoming)
          .length;
      final ended = events.where((e) => e.status == BazaarStatus.ended).length;
      expect(ongoing, greaterThanOrEqualTo(1));
      expect(upcoming, greaterThanOrEqualTo(6));
      expect(ended, greaterThanOrEqualTo(3));

      for (final product in products) {
        expect(product.stockQuantity, greaterThanOrEqualTo(0));

        // Every seeded product must carry a bundled photo. The catalog in
        // tool/generate_mock_data.py is deliberately limited to models that have
        // one — a model without a matching PNG would render as a grey
        // placeholder everywhere, which is easy to miss by eye and impossible to
        // miss here.
        expect(
          product.imagePath,
          isNotNull,
          reason: '${product.name} has no photo',
        );
        expect(
          product.imagePath,
          startsWith('assets/images/default_shoes/'),
          reason: '${product.name} has an unexpected photo path',
        );

        // Proves the file is actually bundled, not just referenced: rootBundle
        // throws if the asset isn't declared in pubspec.yaml or is missing.
        await expectLater(
          rootBundle.load(product.imagePath!),
          completes,
          reason:
              '${product.name}: ${product.imagePath} is not a bundled asset',
        );
      }

      for (final event in events) {
        final allocations = await eventRepository
            .allocationsForEventByAllocationKey(event.id);
        expect(
          allocations,
          isNotEmpty,
          reason: '${event.name} should have stock allocated',
        );
      }
    },
  );

  /// Every other bazaar in the generator is positioned relative to whenever
  /// the script last ran. August Fair is the one with fixed calendar dates,
  /// so it can be asserted exactly — and it's the one a demo is driven from.
  ///
  /// Deliberately says nothing about its *status*: that is derived from
  /// `DateTime.now()`, so pinning "ongoing" here would turn into a failing
  /// test on 8 August rather than a useful assertion.
  test('seeds August Fair day by day, inside the revenue band', () async {
    SharedPreferences.setMockInitialValues({});
    final eventRepository = EventRepository();
    final productRepository = ProductRepository();
    final salesRepository = SalesRepository();
    final ordersRepository = OrdersRepository();
    final settingsRepository = SettingsRepository();
    final authRepository = AuthRepository();

    await DevMockDataSeeder(
      eventRepository: eventRepository,
      productRepository: productRepository,
      salesRepository: salesRepository,
      ordersRepository: ordersRepository,
      settingsRepository: settingsRepository,
      authRepository: authRepository,
    ).seed();

    final events = await eventRepository.listAll();
    final fair = events.singleWhere(
      (e) => e.name == 'August Fair',
      orElse: () => throw StateError('August Fair was not seeded'),
    );

    expect(fair.startDate, DateTime(2026, 8, 3));
    expect(fair.endDate, DateTime(2026, 8, 7));
    expect(fair.acceptedPaymentMethods, containsAll(['CASH', 'GCASH']));

    final sales = (await salesRepository.listSales())
        .where((s) => s.eventId == fair.id)
        .toList();
    expect(sales, isNotEmpty);

    final byDay = <DateTime, List<double>>{};
    for (final sale in sales) {
      final day = DateTime(
        sale.timestamp.year,
        sale.timestamp.month,
        sale.timestamp.day,
      );
      byDay.putIfAbsent(day, () => []).add(sale.total);
    }
    final days = byDay.keys.toList()..sort();

    // The run opens on the Monday and fills forward one day at a time, and
    // it never sells on a day that hasn't happened. Checked as a contiguous
    // prefix rather than an exact set: the generator extends the fair as the
    // week passes, so naming the days would make this fail every Friday.
    final now = DateTime.now();
    expect(days.first, DateTime(2026, 8, 3));
    expect(
      days.last.isAfter(DateTime(now.year, now.month, now.day)),
      isFalse,
      reason: 'August Fair sold on a day that has not happened yet',
    );
    expect(
      days.last.isAfter(DateTime(2026, 8, 7)),
      isFalse,
      reason: 'August Fair sold after its end date',
    );
    for (var i = 0; i < days.length; i++) {
      expect(
        days[i],
        DateTime(2026, 8, 3).add(Duration(days: i)),
        reason: 'day ${i + 1} of the run is missing or out of order',
      );
    }

    for (final entry in byDay.entries) {
      final revenue = entry.value.fold<double>(0, (sum, t) => sum + t);
      // 25k is a hard ceiling in the generator, not an average — it rejects
      // a sale that would breach it and tries a cheaper SKU. The floor is
      // what stops a day reading as a dead bar next to the others.
      expect(
        revenue,
        inInclusiveRange(20000, 25000),
        reason: '${entry.key} revenue is outside the 20-25k band',
      );
    }

    // Both assigned staff exist, so the bazaar is reachable from an employee
    // login and not just the owner's.
    final staff = (await authRepository.listUsers())
        .where((u) => u.assignedEventIdsEffective.contains(fair.id))
        .toList();
    expect(staff.length, 2);

    // Sold units have to come out of what was allocated, or the POS will
    // show stock the bazaar never had.
    final allocations = await eventRepository
        .allocationsForEventByAllocationKey(fair.id);
    final allocated = allocations.values.fold<int>(0, (sum, q) => sum + q);
    final sold = sales.fold<int>(0, (sum, s) => sum + s.qty);
    expect(sold, lessThanOrEqualTo(allocated));
  });
}

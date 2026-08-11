import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/models/sale.dart';
import 'package:syncbazaar/services/dashboard_analytics_service.dart';

/// The Analyze card presents these numbers as fact, with no disclaimer to hide
/// behind, so the arithmetic and the slot-filling rules are pinned here.
void main() {
  const service = DashboardAnalyticsService();

  const eventNames = {1: 'Amkor Bazaar', 2: 'Company B Bazaar'};
  const productNames = {10: 'Air Force 1', 11: 'Samba OG'};
  const variantLabels = {100: 'White', 101: 'Black', 200: '42', 201: '38'};

  var nextId = 0;
  Sale sale({
    int eventId = 1,
    int productId = 10,
    int? optionA,
    int? optionB,
    String payment = 'Cash',
    int qty = 1,
    double total = 1000,
    DateTime? at,
    OrderStatus status = OrderStatus.completed,
  }) {
    return Sale(
      id: nextId,
      clientUuid: 'test-sale-${nextId++}',
      eventId: eventId,
      productId: productId,
      variantOptionIdA: optionA,
      variantOptionIdB: optionB,
      customerName: 'Customer',
      employeeId: 'e1',
      paymentMethod: payment,
      qty: qty,
      total: total,
      timestamp: at ?? DateTime.now(),
      orderStatus: status,
      synced: true,
    );
  }

  DashboardAnalytics compute(
    List<Sale> sales, {
    String filter = DashboardAnalyticsService.allBazaarsFilter,
  }) {
    return service.compute(
      selectedFilter: filter,
      sales: sales,
      eventNameById: eventNames,
      productNameById: productNames,
      variantLabelByOptionId: variantLabels,
    );
  }

  test('average order value is revenue over transactions', () {
    final result = compute([
      sale(total: 1000),
      sale(total: 2000),
      sale(total: 3000),
    ]);

    expect(result.transactionCount, 3);
    expect(result.averageOrderValue, 2000);
  });

  test('an empty scope reports empty instead of inventing numbers', () {
    final result = compute(const []);

    expect(result.isEmpty, isTrue);
    expect(result.metrics, isEmpty);
    expect(result.averageOrderValue, 0);
    expect(result.scopeLabel, 'all bazaars');
  });

  test('a bazaar filter scopes every figure to that bazaar', () {
    final result = compute([
      sale(eventId: 1, total: 1000),
      sale(eventId: 1, total: 3000),
      sale(eventId: 2, total: 9000),
    ], filter: 'Amkor Bazaar');

    expect(result.transactionCount, 2);
    expect(result.averageOrderValue, 2000);
    expect(result.scopeLabel, 'Amkor Bazaar');
  });

  test('completion rate counts only completed orders', () {
    final result = compute([
      sale(),
      sale(),
      sale(status: OrderStatus.returned),
      sale(status: OrderStatus.returned),
    ]);

    expect(result.completedOrders, 2);
    expect(result.completionRate, 0.5);
  });

  test(
    'best seller and top variant are measured in units, not transactions',
    () {
      // One big-quantity sale of Samba OG must beat three single-unit Air Force
      // sales — the question is "what moved", not "how often did it ring up".
      final result = compute([
        sale(productId: 10, optionA: 100, optionB: 200, qty: 1),
        sale(productId: 10, optionA: 100, optionB: 200, qty: 1),
        sale(productId: 10, optionA: 100, optionB: 200, qty: 1),
        sale(productId: 11, optionA: 101, optionB: 201, qty: 9),
      ]);

      final topProduct = result.metrics.firstWhere(
        (m) => m.kind == AnalyticsMetricKind.topProduct,
      );
      expect(topProduct.value, 'Samba OG');
      expect(topProduct.detail, '9 units sold');

      // Variants are counted across both option slots, so the colourway and the
      // size compete in the same ranking.
      final topVariant = result.metrics.firstWhere(
        (m) => m.kind == AnalyticsMetricKind.topVariant,
      );
      expect(topVariant.value, anyOf('Black', '38'));
      expect(topVariant.detail, '9 units sold');
    },
  );

  test('preferred payment reports the share, not just the winner', () {
    final result = compute([
      sale(payment: 'COOP'),
      sale(payment: 'COOP'),
      sale(payment: 'COOP'),
      sale(payment: 'Cash'),
    ]);

    final payment = result.metrics.firstWhere(
      (m) => m.kind == AnalyticsMetricKind.paymentMix,
    );
    expect(payment.value, 'COOP');
    expect(payment.detail, '75% of sales (3 of 4)');
  });

  group('metric slots', () {
    test('a multi-bazaar scope spends the third slot on top bazaar', () {
      final result = compute([
        sale(eventId: 1, optionA: 100, total: 5000),
        sale(eventId: 2, optionA: 101, total: 1000),
      ]);

      expect(result.metrics.length, 4);
      expect(
        result.metrics.map((m) => m.kind),
        containsAll([
          AnalyticsMetricKind.topProduct,
          AnalyticsMetricKind.topVariant,
          AnalyticsMetricKind.topBazaar,
          AnalyticsMetricKind.paymentMix,
        ]),
      );
      final topBazaar = result.metrics.firstWhere(
        (m) => m.kind == AnalyticsMetricKind.topBazaar,
      );
      expect(topBazaar.value, 'Amkor Bazaar');
    });

    test(
      'filtering to one bazaar swaps that slot rather than leaving a hole',
      () {
        // "Top bazaar: the bazaar you just selected" is not a finding, so the
        // grid must stay full by falling through to the next useful stat.
        final result = compute([
          sale(eventId: 1, optionA: 100),
          sale(eventId: 2, optionA: 101),
        ], filter: 'Amkor Bazaar');

        expect(result.metrics.length, 4);
        expect(
          result.metrics.map((m) => m.kind),
          isNot(contains(AnalyticsMetricKind.topBazaar)),
        );
        expect(
          result.metrics.map((m) => m.kind),
          contains(AnalyticsMetricKind.unitsSold),
        );
      },
    );

    test('a catalogue with no variants still fills four slots', () {
      final monday = DateTime(2026, 7, 27, 12);
      final result = compute([
        sale(eventId: 1, at: monday),
        sale(eventId: 1, at: monday.add(const Duration(days: 1))),
      ], filter: 'Amkor Bazaar');

      expect(result.metrics.length, 4);
      expect(
        result.metrics.map((m) => m.kind),
        isNot(contains(AnalyticsMetricKind.topVariant)),
      );
      expect(
        result.metrics.map((m) => m.kind),
        containsAll([
          AnalyticsMetricKind.unitsSold,
          AnalyticsMetricKind.busiestDay,
        ]),
      );
    });

    test('never shows more than four', () {
      final result = compute([
        sale(eventId: 1, optionA: 100, optionB: 200, at: DateTime(2026, 7, 27)),
        sale(eventId: 2, optionA: 101, optionB: 201, at: DateTime(2026, 7, 28)),
      ]);

      expect(result.metrics.length, 4);
    });
  });

  group('average order value trend', () {
    final today = DateTime.now();

    test('is withheld when there is no earlier week to compare against', () {
      final result = compute([
        sale(total: 1000, at: today),
        sale(total: 2000, at: today.subtract(const Duration(days: 1))),
      ]);

      // A zero baseline would compute as "+100%", which looks like growth and
      // is really just an absence of history.
      expect(result.averageOrderValueTrend, isNull);
    });

    test('compares the last 7 days against the 7 before', () {
      final result = compute([
        sale(total: 2000, at: today.subtract(const Duration(days: 1))),
        sale(total: 1000, at: today.subtract(const Duration(days: 9))),
      ]);

      expect(result.averageOrderValueTrend, closeTo(100, 0.001));
    });

    test('reports a decline as negative', () {
      final result = compute([
        sale(total: 500, at: today.subtract(const Duration(days: 1))),
        sale(total: 1000, at: today.subtract(const Duration(days: 9))),
      ]);

      expect(result.averageOrderValueTrend, closeTo(-50, 0.001));
    });
  });
}

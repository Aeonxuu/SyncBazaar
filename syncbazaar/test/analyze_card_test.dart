import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/services/dashboard_analytics_service.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/analyze_card.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/trend_pill.dart';

void main() {
  const populated = DashboardAnalytics(
    transactionCount: 308,
    averageOrderValue: 1240.5,
    averageOrderValueTrend: 8.4,
    completedOrders: 300,
    scopeLabel: 'all bazaars',
    metrics: [
      AnalyticsMetric(
        kind: AnalyticsMetricKind.topProduct,
        label: 'Best seller',
        value: 'Nike Air Force 1 \'07',
        detail: '42 units sold',
      ),
      AnalyticsMetric(
        kind: AnalyticsMetricKind.topVariant,
        label: 'Top variant',
        value: '42',
        detail: '38 units sold',
      ),
      AnalyticsMetric(
        kind: AnalyticsMetricKind.topBazaar,
        label: 'Top bazaar',
        value: 'Amkor Bazaar',
        detail: 'PHP 120,450.00 earned',
      ),
      AnalyticsMetric(
        kind: AnalyticsMetricKind.paymentMix,
        label: 'Preferred payment',
        value: 'COOP',
        detail: '62% of sales (191 of 308)',
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    DashboardAnalytics analytics, {
    double? height,
    double width = 520,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: AnalyzeCard(analytics: analytics),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('states its provenance instead of an AI disclaimer', (
    tester,
  ) async {
    await pump(tester, populated);

    expect(find.text('Analyze'), findsOneWidget);
    expect(
      find.text('Based on 308 recorded sales across all bazaars'),
      findsOneWidget,
    );

    // The card is plain arithmetic; nothing about it may imply a model.
    expect(find.textContaining('AI'), findsNothing);
    expect(find.textContaining('inaccuracies'), findsNothing);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.psychology_outlined), findsNothing);
  });

  testWidgets('leads with average order value and its trend', (tester) async {
    await pump(tester, populated);

    expect(find.text('Average order value'), findsOneWidget);
    expect(find.text('PHP 1,240.50'), findsOneWidget);
    expect(find.text('+8.4%'), findsOneWidget);
    expect(find.text('vs. the previous 7 days'), findsOneWidget);
  });

  testWidgets('shows every metric as label, value and evidence', (
    tester,
  ) async {
    await pump(tester, populated);

    for (final metric in populated.metrics) {
      expect(find.text(metric.label), findsOneWidget);
      expect(find.text(metric.value), findsOneWidget);
      expect(find.text(metric.detail), findsOneWidget);
    }

    expect(find.text('Orders completed'), findsOneWidget);
    expect(find.text('300 of 308  ·  97%'), findsOneWidget);
  });

  testWidgets('hides the trend when there is no baseline week', (tester) async {
    await pump(
      tester,
      const DashboardAnalytics(
        transactionCount: 1,
        averageOrderValue: 950,
        averageOrderValueTrend: null,
        completedOrders: 1,
        scopeLabel: 'all bazaars',
        metrics: [],
      ),
    );

    expect(find.byType(TrendPill), findsNothing);
    expect(find.textContaining('vs. the previous'), findsNothing);
    expect(find.text('Revenue divided by transactions'), findsOneWidget);
    // Singular, because "1 recorded sales" reads as a bug.
    expect(
      find.text('Based on 1 recorded sale across all bazaars'),
      findsOneWidget,
    );
  });

  testWidgets('an empty scope says so rather than showing sample figures', (
    tester,
  ) async {
    await pump(
      tester,
      const DashboardAnalytics.empty(scopeLabel: 'Amkor Bazaar'),
    );

    expect(find.text('Nothing to analyze yet'), findsOneWidget);
    expect(find.text('No sales recorded for Amkor Bazaar yet'), findsOneWidget);
    // The card this replaced fell back to four invented sentences.
    expect(find.textContaining('120,450'), findsNothing);
    expect(find.text('Average order value'), findsNothing);
  });

  testWidgets('sizes itself when stacked in the narrow-screen scroll view', (
    tester,
  ) async {
    // Below 900px the dashboard drops the two cards into a column inside a
    // SingleChildScrollView, so the card is handed an unbounded height. That
    // is the constraint a flexible child throws on, and it is not the path
    // the fixed-height tests above take.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: AnalyzeCard(analytics: populated),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AnalyzeCard)).height, lessThan(600));
    expect(find.text('Orders completed'), findsOneWidget);
  });

  group('fits the height the dashboard pins it to', () {
    // `pairedCardHeight` in dashboard_screen.dart. The narrow end of the range
    // is the two-column layout at a 900px window: (900 - 48 - 16) / 2 = 418.
    const pairedCardHeight = 384.0;

    for (final width in [418.0, 520.0, 700.0]) {
      testWidgets('at ${width.toInt()}px wide', (tester) async {
        await pump(tester, populated, height: pairedCardHeight, width: width);

        // Overflow would otherwise only show up as a stripe in a browser.
        expect(tester.takeException(), isNull);

        // Nothing may be pushed behind the grid's overflow scroller: every
        // cell, and the strip below it, has to be on screen unaided.
        for (final metric in populated.metrics) {
          expect(find.text(metric.value), findsOneWidget);
        }
        expect(find.text('Orders completed'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text('Orders completed')).dy,
          lessThan(tester.getBottomLeft(find.byType(AnalyzeCard)).dy),
        );
      });
    }
  });
}

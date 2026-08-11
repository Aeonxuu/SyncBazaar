import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/dashboard_kpi_card.dart';

/// The KPI tiles are the first thing on the dashboard and sit in a row, so any
/// asymmetry in their padding is visible as a set rather than one card at a
/// time. These pin the two things that were wrong.
void main() {
  /// `_kpiCardHeight` in dashboard_screen.dart.
  const gridHeight = 96.0;

  /// `EdgeInsets.all(16)` in the card, plus its 1px border.
  const expectedInset = 17.0;

  Future<Rect> pumpCard(
    WidgetTester tester, {
    double width = 276,
    double? height,
    bool toggle = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          // A bare Align would hand the card the screen's height as a loose
          // constraint, and its Column would fill it — so an unset `height`
          // has to mean genuinely unbounded for the intrinsic measurement to
          // mean anything.
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              height: height,
              child: DashboardKpiCard(
                title: 'Total Sale',
                value: 'PHP 210,231.00',
                icon: Icons.attach_money_outlined,
                onTap: toggle ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(DashboardKpiCard));
  }

  group('padding stays symmetric at any height the grid hands it', () {
    // The bug: with childAspectRatio the tile height tracked the column width,
    // so the same card was 102px tall at a 1000px window and 151px at 1440 —
    // 16px above the content and 31-80px of dead space below it.
    for (final height in [84.0, 96.0, 124.0, 151.0]) {
      testWidgets('at ${height.toInt()}px tall', (tester) async {
        final card = await pumpCard(tester, height: height);

        final label = tester.getRect(find.byIcon(Icons.attach_money_outlined));
        final value = tester.getRect(find.text('PHP 210,231.00'));

        expect(label.top - card.top, expectedInset, reason: 'top');
        expect(card.bottom - value.bottom, expectedInset, reason: 'bottom');
        expect(label.left - card.left, expectedInset, reason: 'left');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('height does not vary with the width of the window', (
    tester,
  ) async {
    // Every tile in the row must be the same shape whatever the viewport, so
    // the card's own content — not the column width — decides its height.
    final heights = <double>[];
    for (final width in [226.0, 276.0, 336.0, 640.0]) {
      final card = await pumpCard(tester, width: width);
      heights.add(card.height);
    }

    expect(heights.toSet(), hasLength(1));
    expect(
      heights.first,
      lessThanOrEqualTo(gridHeight),
      reason: 'content taller than the grid slot would overflow every KPI tile',
    );
  });

  testWidgets('a toggle card keeps the same padding as a plain one', (
    tester,
  ) async {
    // The chevron on the tappable KPIs must not push the value off the
    // baseline the other three sit on.
    final plain = await pumpCard(tester, height: gridHeight);
    final plainValue = tester.getRect(find.text('PHP 210,231.00'));
    final plainOffset = plain.bottom - plainValue.bottom;

    final toggled = await pumpCard(tester, height: gridHeight, toggle: true);
    final toggledValue = tester.getRect(find.text('PHP 210,231.00'));

    expect(toggled.bottom - toggledValue.bottom, plainOffset);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
  });
}

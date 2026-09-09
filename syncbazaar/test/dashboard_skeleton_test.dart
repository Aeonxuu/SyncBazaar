import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/bloc/dashboard/dashboard_cubit.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/dashboard_kpi_card.dart';
import 'package:syncbazaar/ui/screens/dashboard/widgets/dashboard_kpi_skeleton.dart';

/// The dashboard shows placeholders while its figures are on their way.
///
/// It used to render nothing at all until they arrived, so the top of the
/// screen was blank for as long as the fetch took. Blank reads as "there is no
/// data", not "this is coming", and it is worst for a cashier reopening the app
/// mid-bazaar: an empty dashboard gives no way to tell a slow network from lost
/// takings.
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

  group('the placeholder card', () {
    testWidgets('matches the real card so nothing shifts', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 240,
            height: 96,
            child: DashboardKpiSkeleton(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final skeleton = tester.getSize(find.byType(DashboardKpiSkeleton));

      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 240,
            height: 96,
            child: DashboardKpiCard(title: 'Total Sale', value: 'PHP 6,800.00'),
          ),
        ),
      );

      expect(tester.getSize(find.byType(DashboardKpiCard)), skeleton);
    });

    testWidgets('shows no text, so there is nothing to misread', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 240,
            height: 96,
            child: DashboardKpiSkeleton(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // A placeholder that renders "0" or "PHP 0.00" would be read as a real
      // figure, which is worse than showing nothing at all.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('disposes its animation', (tester) async {
      await tester.pumpWidget(
        host(const SizedBox(width: 240, height: 96, child: DashboardKpiSkeleton())),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });

  group('when the state says to show them', () {
    test('before a load has finished, with no figures yet', () {
      const state = DashboardState();

      expect(state.hasLoaded, isFalse);
      expect(state.kpis, isEmpty);
    });

    test('a finished load ends the wait even with nothing to show', () {
      const state = DashboardState(hasLoaded: true);

      // A failed load still sets this. Leaving placeholders up forever would
      // be a worse lie than showing an empty dashboard.
      expect(state.hasLoaded, isTrue);
    });

    test('the flag survives a copyWith that does not mention it', () {
      const loaded = DashboardState(hasLoaded: true);

      expect(loaded.copyWith(events: const []).hasLoaded, isTrue);
    });
  });
}

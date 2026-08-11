import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/models/product.dart';
import 'package:syncbazaar/ui/screens/pos/widgets/pos_product_card.dart';

/// The POS grid went from three columns to four, so every card is narrower.
/// The card splits its height evenly between the photo and the details, and
/// the details half has a fixed floor — name, price row and a 32px Add button.
/// These pin the sizing rule that keeps the button from being clipped.
void main() {
  const product = Product(
    id: 1,
    name: 'Nike Air Force 1 \'07 Triple White',
    basePrice: 5495,
    stockQuantity: 12,
    status: ProductStatus.active,
  );

  /// Mirrors the delegate in `_productPanel`.
  double extentFor(double cardWidth) => math.max(cardWidth / 0.72, 208.0);

  int columnsFor(double available, double gap, double minCardWidth) {
    for (var columns = 4; columns > 2; columns--) {
      if ((available - (columns - 1) * gap) / columns >= minCardWidth) {
        return columns;
      }
    }
    return 2;
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required double width,
    required double height,
    bool inStock = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: PosProductCard(
                product: product,
                isEnabled: inStock,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('card survives every size the four-column grid produces', () {
    // Panel widths across the range the POS runs at: the product panel is
    // flex 7 of 10 inside the shell, so roughly 440-900px.
    for (final panelWidth in [440.0, 560.0, 700.0, 900.0, 1100.0]) {
      testWidgets('panel ${panelWidth.toInt()}px', (tester) async {
        const gap = 12.0;
        final columns = columnsFor(panelWidth, gap, 150);
        final cardWidth = (panelWidth - (columns - 1) * gap) / columns;

        await pumpCard(tester, width: cardWidth, height: extentFor(cardWidth));

        expect(tester.takeException(), isNull);
        // The Add button is the thing that gets clipped first.
        expect(find.text('Add to cart'), findsOneWidget);
        expect(find.textContaining('5,495'), findsOneWidget);
      });
    }

    testWidgets('at the smallest extent the floor allows', (tester) async {
      // 208 is the floor; below it the details half drops under the ~96px its
      // contents need and the button starts to clip.
      await pumpCard(tester, width: 150, height: 208);

      expect(tester.takeException(), isNull);
      expect(find.text('Add to cart'), findsOneWidget);
    });

    testWidgets('out of stock still fits', (tester) async {
      await pumpCard(tester, width: 150, height: 208, inStock: false);

      expect(tester.takeException(), isNull);
      expect(find.text('Out of stock'), findsOneWidget);
    });
  });

  group('nested corner radii', () {
    // `inner = outer − gap`, so the button's curve stays parallel to the
    // card's. Measured off the rendered tree rather than read off the
    // constants, so moving the padding without moving the radius fails here.
    final anyOutlinedButton = find.byWidgetPredicate(
      (w) => w is OutlinedButton,
    );

    double cardRadius(WidgetTester tester) {
      final card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PosProductCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = card.decoration! as BoxDecoration;
      return (decoration.borderRadius! as BorderRadius).bottomLeft.x;
    }

    double buttonRadius(WidgetTester tester) {
      final button = tester.widget<OutlinedButton>(anyOutlinedButton);
      final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
      return (shape.borderRadius as BorderRadius).bottomLeft.x;
    }

    testWidgets('the button is inset by the same gap on both axes', (
      tester,
    ) async {
      await pumpCard(tester, width: 170, height: extentFor(170));

      final card = tester.getRect(find.byType(PosProductCard));
      final button = tester.getRect(anyOutlinedButton);

      // A concentric relation needs one gap, not two: if the side and bottom
      // insets disagree there is no single radius that keeps the arcs
      // parallel. This was 10 horizontal / 8 vertical.
      expect(button.left - card.left, card.bottom - button.bottom);
      expect(card.right - button.right, button.left - card.left);
    });

    testWidgets('the button radius is the card radius minus that gap', (
      tester,
    ) async {
      await pumpCard(tester, width: 170, height: extentFor(170));

      final gap =
          tester.getRect(anyOutlinedButton).left -
          tester.getRect(find.byType(PosProductCard)).left;

      expect(buttonRadius(tester), cardRadius(tester) - gap);
      // The inverted form — a button rounder than the container that holds
      // it — pinches the gap at the corner. Guard against it directly.
      expect(buttonRadius(tester), lessThan(cardRadius(tester)));
    });

    testWidgets('the photo carries the card radius on the top corners', (
      tester,
    ) async {
      await pumpCard(tester, width: 170, height: extentFor(170));

      final clipped = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(PosProductCard),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      final radius = clipped.borderRadius as BorderRadius;

      expect(radius.topLeft.x, cardRadius(tester));
      expect(radius.topRight.x, cardRadius(tester));
      // Bottom corners are square — the details half owns those.
      expect(radius.bottomLeft.x, 0);
    });

    testWidgets('the card no longer exceeds the inline radius cap', (
      tester,
    ) async {
      await pumpCard(tester, width: 170, height: extentFor(170));

      // Section 5: nothing inline goes above 10; 14 and 16 are reserved for
      // modals and the login panel. This card sat at 16 as a carve-out.
      expect(cardRadius(tester), lessThanOrEqualTo(10));
    });
  });

  group('column count', () {
    test('prefers four when each card can stay readable', () {
      expect(columnsFor(900, 12, 150), 4);
      expect(columnsFor(700, 12, 150), 4);
      // 4 cards would be 149px here, under the floor.
      expect(columnsFor(620, 12, 150), 3);
    });

    test('never drops below two, however narrow', () {
      expect(columnsFor(300, 12, 150), 2);
      expect(columnsFor(120, 12, 150), 2);
    });

    test('a hard four would have produced unusable cards', () {
      // What `crossAxisCount: 4` did at the narrow end, and the reason the
      // count is computed instead of fixed.
      const narrowPanel = 440.0;
      const naive = (narrowPanel - 3 * 12) / 4;
      expect(naive, lessThan(150));
      expect(columnsFor(narrowPanel, 12, 150), lessThan(4));
    });
  });
}

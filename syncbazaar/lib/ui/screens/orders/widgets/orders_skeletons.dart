import 'package:flutter/material.dart';

import '../../../widgets/skeleton.dart';

/// A bazaar card in the Orders picker with nothing in it yet.
///
/// Shaped to the real card: 16px padding, radius 10, hairline border, the name
/// and dates at the top and the status badge beside the arrow at the bottom.
/// The grid around it uses the same 152px height, so nothing moves when the
/// real cards land.
class OrdersBazaarCardSkeleton extends StatelessWidget {
  const OrdersBazaarCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: const SkeletonBreathing(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBar(width: 170, height: 18),
            SizedBox(height: 8),
            SkeletonBar(width: 120, height: 12),
            Spacer(),
            Row(
              children: [
                SkeletonBar(width: 64, height: 22, radius: 6),
                Spacer(),
                SkeletonBar(width: 18, height: 18, radius: 9),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The orders table's rows before the sales arrive.
///
/// Shaped to the real row: the customer over a time and payment line, the
/// product over its variant, then unit price, quantity and total at the same
/// 4/5/2/28/92/2 split plus the 76px refund slot and 10px vertical padding. The heading row above is the
/// real one and stays put.
class OrderRowsSkeleton extends StatelessWidget {
  const OrderRowsSkeleton({super.key});

  /// Enough to fill a tablet's table without scrolling.
  static const _rows = 8;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading orders',
      child: ExcludeSemantics(
        child: ListView.separated(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _rows,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFF3F3F6)),
          itemBuilder: (_, i) => _Row(index: i),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.index});

  final int index;

  // Varied so the column reads as different people, fixed so a rebuild does
  // not make it twitch.
  static const _customerWidths = [110.0, 84.0, 130.0, 96.0, 120.0, 90.0];
  static const _productWidths = [150.0, 124.0, 168.0, 136.0, 158.0, 118.0];

  @override
  Widget build(BuildContext context) {
    final customer = _customerWidths[index % _customerWidths.length];
    final product = _productWidths[index % _productWidths.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SkeletonBreathing(
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: customer, height: 13),
                  const SizedBox(height: 6),
                  const SkeletonBar(width: 90, height: 11),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: product, height: 13),
                  const SizedBox(height: 6),
                  const SkeletonBar(width: 104, height: 11),
                ],
              ),
            ),
            const Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: SkeletonBar(width: 56, height: 12),
              ),
            ),
            const SizedBox(width: 28),
            const SizedBox(
              width: 92,
              child: Center(child: SkeletonBar(width: 18, height: 12)),
            ),
            const Expanded(
              flex: 2,
              child: Center(child: SkeletonBar(width: 64, height: 12)),
            ),
            // The refund slot, empty while loading, so the columns above sit
            // where the real ones will.
            const SizedBox(width: 76),
          ],
        ),
      ),
    );
  }
}

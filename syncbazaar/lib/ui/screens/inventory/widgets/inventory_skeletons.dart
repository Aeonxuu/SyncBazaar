import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../widgets/skeleton.dart';

/// A KPI card with its figure not yet in.
///
/// Shaped to `_InventoryKpiCard`: same 18px padding, radius 8, surface fill,
/// with two bars standing where the value and the label will be.
class InventoryKpiSkeleton extends StatelessWidget {
  const InventoryKpiSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const SkeletonBreathing(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBar(width: 96, height: 26),
            SizedBox(height: 9),
            SkeletonBar(width: 128, height: 11),
          ],
        ),
      ),
    );
  }
}

/// One inventory row with nothing in it yet.
///
/// Shaped to `_buildRow`'s columns -- checkbox gutter, photo + name/price,
/// two variant columns, a stock column, and the action gutter when the
/// viewer can manage the catalogue -- and to the real row's own padding
/// (`EdgeInsets.fromLTRB(_tableInset, 10, _tableInset, 10)`), so the table
/// does not jump in height once the real rows land.
class InventoryRowSkeleton extends StatelessWidget {
  const InventoryRowSkeleton({super.key, required this.canManage});

  final bool canManage;

  static const double _tableInset = 16;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_tableInset, 10, _tableInset, 10),
      child: SkeletonBreathing(
        child: Row(
          children: [
            const SizedBox(width: 36),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  const SkeletonBar(width: 40, height: 40, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SkeletonBar(width: 140, height: 13),
                        SizedBox(height: 6),
                        SkeletonBar(width: 64, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(flex: 3, child: SkeletonBar(width: 48, height: 12)),
            const Expanded(flex: 3, child: SkeletonBar(width: 48, height: 12)),
            const SizedBox(width: 80, child: SkeletonBar(width: 36, height: 12)),
            if (canManage) const SizedBox(width: 80),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../widgets/skeleton.dart';

/// A bazaar card with nothing in it yet.
///
/// Shaped to `_BazaarCard`: same 16px padding, radius 10, hairline border and
/// surface fill, with bars where the name, status pill, dates and the full-width
/// button will be. The grid around it sets the same 200px height, so the page
/// does not move when the real cards arrive.
class BazaarCardSkeleton extends StatelessWidget {
  const BazaarCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDEDF1)),
      ),
      child: const SkeletonBreathing(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBar(width: 180, height: 18),
            SizedBox(height: 12),
            SkeletonBar(width: 68, height: 22, radius: 6),
            SizedBox(height: 14),
            SkeletonBar(width: 140, height: 12),
            Spacer(),
            SkeletonBar(width: double.infinity, height: 38, radius: 8),
          ],
        ),
      ),
    );
  }
}

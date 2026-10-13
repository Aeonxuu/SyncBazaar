import 'package:flutter/material.dart';

import '../../../widgets/skeleton.dart';

/// The Documentation list before its bazaars arrive.
///
/// Shaped to the real card: 14px padding, radius 12 and the same soft shadow,
/// with the name, venue and dates stacked on the left and the status badge over
/// the "View details" pill on the right. The list around it uses the same 36px
/// side margin and 10px gap, so nothing moves when the real cards land.
///
/// Drawn under the real tab bar, which is already true. It stands in for all
/// three tabs, since none of them has anything to show until the data does.
class DocumentationListSkeleton extends StatelessWidget {
  const DocumentationListSkeleton({super.key});

  /// Enough to fill a tablet's height without scrolling.
  static const _cards = 5;

  static const _kCardShadow = [
    BoxShadow(color: Color(0x11000000), blurRadius: 20, offset: Offset(0, 4)),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading bazaars',
      child: ExcludeSemantics(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
          itemCount: _cards,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _Card(index: i),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.index});

  final int index;

  // Varied so the list reads as different bazaars, but fixed so a rebuild does
  // not make it twitch.
  static const _nameWidths = [220.0, 180.0, 250.0, 200.0, 170.0];

  @override
  Widget build(BuildContext context) {
    final nameWidth = _nameWidths[index % _nameWidths.length];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: DocumentationListSkeleton._kCardShadow,
      ),
      child: SkeletonBreathing(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: nameWidth, height: 18),
                  const SizedBox(height: 9),
                  const SkeletonBar(width: 120, height: 12),
                  const SizedBox(height: 10),
                  const SkeletonBar(width: 150, height: 12),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonBar(width: 68, height: 22, radius: 999),
                SizedBox(height: 10),
                SkeletonBar(width: 104, height: 28, radius: 999),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

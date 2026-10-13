import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../widgets/skeleton.dart';

/// The staff table's rows before the people arrive.
///
/// Shaped to the real row (34px avatar beside a name and an email, then the
/// role, date hired and bazaars columns at the same 5/2/2/2 split, and the
/// action gutter when the viewer can edit), with the same 12px vertical
/// padding, so nothing shifts when the real rows land. The heading row above
/// is the real one and stays put: it is already true, and keeping it means
/// only the part that is waiting looks like it is waiting.
class StaffRowsSkeleton extends StatelessWidget {
  const StaffRowsSkeleton({super.key, required this.showActions});

  final bool showActions;

  /// Enough to fill a tablet's table without scrolling. Fewer would leave a
  /// hole below; more would be drawn off-screen for nothing.
  static const _rows = 7;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading staff',
      child: ExcludeSemantics(
        child: ListView.separated(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _rows,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFF3F3F6)),
          itemBuilder: (_, i) => _Row(index: i, showActions: showActions),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.index, required this.showActions});

  final int index;
  final bool showActions;

  // Name widths vary a little so the column reads as people, not a grid of
  // identical bars. Fixed, not random: a skeleton that changes on rebuild
  // twitches.
  static const _nameWidths = [132.0, 108.0, 148.0, 120.0, 140.0, 100.0, 126.0];

  @override
  Widget build(BuildContext context) {
    final nameWidth = _nameWidths[index % _nameWidths.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SkeletonBreathing(
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.inputFill,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SkeletonBar(width: nameWidth, height: 13),
                        const SizedBox(height: 6),
                        SkeletonBar(width: nameWidth + 40, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBar(width: 64, height: 22, radius: 6),
              ),
            ),
            const Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBar(width: 72, height: 12),
              ),
            ),
            const Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBar(width: 28, height: 12),
              ),
            ),
            if (showActions) const SizedBox(width: 80),
          ],
        ),
      ),
    );
  }
}

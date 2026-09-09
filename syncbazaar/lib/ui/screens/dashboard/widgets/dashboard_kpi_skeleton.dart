import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

/// A KPI card with its figures not yet in.
///
/// The dashboard used to render nothing at all until the numbers arrived, so
/// the top of the screen was blank for as long as the fetch took, and blank
/// reads as "there is nothing here" rather than "this is coming". It is worst
/// exactly where it matters most: a cashier reopening the app mid-bazaar sees
/// an empty dashboard and has no way to tell a slow network from lost takings.
///
/// Shaped to the real card rather than a generic block, so the layout does not
/// shift when the numbers land: same 96px height, same 10px radius, same
/// hairline, same 16px padding, and two bars standing where the label and the
/// value will be.
class DashboardKpiSkeleton extends StatefulWidget {
  const DashboardKpiSkeleton({super.key});

  @override
  State<DashboardKpiSkeleton> createState() => _DashboardKpiSkeletonState();
}

class _DashboardKpiSkeletonState extends State<DashboardKpiSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Built here rather than as a late final initialiser, so there is always
    // something to dispose.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A slow breath rather than a sweeping shimmer. This sits under a row of
    // real cards for a second or two, and anything faster turns the top of the
    // dashboard into the busiest thing on screen while it waits.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = reduceMotion ? 0.5 : _controller.value;
          return Opacity(opacity: 0.45 + (t * 0.25), child: child);
        },
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Where the icon and title sit.
            Row(
              children: [
                _Bar(width: 18, height: 18, radius: 4),
                SizedBox(width: 10),
                _Bar(width: 84, height: 11),
              ],
            ),
            // Where the figure lands. Wider and taller, because the number is
            // the thing being waited for.
            _Bar(width: 132, height: 26),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, this.radius = 5});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

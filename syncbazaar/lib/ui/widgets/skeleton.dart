import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';

/// A slow breathing fade shared by every list skeleton, matching
/// `DashboardKpiSkeleton` -- a breath rather than a sweeping shimmer, since
/// several of these sit on screen together for a second or two while the
/// catalogue reloads.
class SkeletonBreathing extends StatefulWidget {
  const SkeletonBreathing({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonBreathing> createState() => _SkeletonBreathingState();
}

class _SkeletonBreathingState extends State<SkeletonBreathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = reduceMotion ? 0.5 : _controller.value;
        return Opacity(opacity: 0.45 + (t * 0.25), child: child);
      },
      child: widget.child,
    );
  }
}

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    required this.width,
    required this.height,
    this.radius = 5,
  });

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

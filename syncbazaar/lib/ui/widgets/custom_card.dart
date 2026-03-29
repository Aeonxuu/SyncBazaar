import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';

class CustomCard extends StatelessWidget {
  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8E8E8), width: 1),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Padding(padding: padding, child: child),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';

class DashboardSectionCard extends StatelessWidget {
  const DashboardSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;

  /// One quiet line under the title saying what the numbers cover — the
  /// window, the scope, or how many records they rest on.
  ///
  /// Part of the card rather than the first line of [child] so every section
  /// states its basis in the same place, at the same weight. A dashboard that
  /// answers "over what period?" differently in each card makes the reader
  /// re-learn the layout per card.
  final String? subtitle;

  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A Column hands its non-flexible children an unbounded height, so a card
    // pinned to a fixed height by the caller would still tell [child] it had
    // infinite room — and any child sizing itself off that would overflow the
    // card by exactly the amount it guessed wrong. Give the child the real
    // remaining space when there is one.
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: constraints.maxHeight.isFinite
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            const SizedBox(height: 14),
            if (constraints.maxHeight.isFinite)
              Expanded(child: child)
            else
              child,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../widgets/custom_card.dart';

class StockAllocationGroup {
  const StockAllocationGroup({
    required this.productName,
    required this.rows,
  });

  final String productName;
  final List<StockAllocationRow> rows;
}

class StockAllocationRow {
  const StockAllocationRow({
    required this.key,
    required this.label,
    required this.allocated,
    required this.remaining,
  });

  final String key;
  final String label;
  final int allocated;
  final int remaining;
}

class StockAllocationCard extends StatelessWidget {
  const StockAllocationCard({
    super.key,
    required this.groups,
    required this.isAdminOrOwner,
    required this.onAllocationChanged,
    required this.onCancel,
    required this.onSubmit,
    this.isSubmitEnabled = true,
    this.isAllocationEnabled = true,
  });

  final List<StockAllocationGroup> groups;
  final bool isAdminOrOwner;
  final void Function(String itemKey, int value) onAllocationChanged;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final bool isSubmitEnabled;
  final bool isAllocationEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF9A6A00),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Allocation',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Assign quantities per product variant',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!isAllocationEnabled) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.35)),
              ),
              child: Text(
                'Complete Create Bazaar and tap Next to unlock stock allocation.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          SizedBox(
            height: 320,
            child: SingleChildScrollView(
              child: Column(
                children: groups
                    .map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.productName,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...group.rows.map(
                                (row) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          row.label,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: isAllocationEnabled
                                            ? () => onAllocationChanged(
                                                row.key,
                                                (row.allocated - 1).clamp(0, 9999),
                                              )
                                            : null,
                                        icon: const Icon(Icons.remove_circle_outline),
                                      ),
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${row.allocated}',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: isAllocationEnabled
                                            ? () => onAllocationChanged(
                                                row.key,
                                                row.allocated + 1,
                                              )
                                            : null,
                                        icon: const Icon(Icons.add_circle_outline),
                                      ),
                                      Text(
                                        'Stock: ${row.remaining}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: (isSubmitEnabled && isAllocationEnabled)
                    ? onSubmit
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.35),
                  disabledForegroundColor: Colors.white70,
                ),
                child: Text(isAdminOrOwner ? 'Finish' : 'Submit for Approval'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

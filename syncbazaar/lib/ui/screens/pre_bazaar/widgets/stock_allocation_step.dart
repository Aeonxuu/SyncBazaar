import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../widgets/quantity_stepper.dart';
import '../../../../core/utils/formatters.dart';

/// Fixed column widths for the allocation table.
///
/// This is the whole point of the layout: the stepper and the availability
/// figure sit in reserved columns, so they line up down the entire list
/// regardless of how long a variant label is or how many digits a number has.
/// The previous version let a variable-width "Stock: N" label push the +/−
/// buttons around, so no two rows agreed on where the controls were.
const double _allocateColumn = 124;
const double _availableColumn = 92;
const double _columnGap = 16;

class StockAllocationGroup {
  const StockAllocationGroup({required this.productName, required this.rows});

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

  /// Units still in master inventory after this allocation.
  final int remaining;
}

/// Step 2: how much of each SKU goes to this bazaar.
class StockAllocationStep extends StatelessWidget {
  const StockAllocationStep({
    super.key,
    required this.groups,
    required this.onAllocationChanged,
    required this.searchController,
    required this.onSearchChanged,
  });

  final List<StockAllocationGroup> groups;
  final void Function(String itemKey, int value) onAllocationChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final totalAllocated = groups.fold<int>(
      0,
      (sum, group) =>
          sum + group.rows.fold<int>(0, (s, row) => s + row.allocated),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    hintStyle: const TextStyle(color: Colors.black38),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Colors.black45,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // The running total is the number this whole step exists to
            // produce, so it stays visible while scrolling a long list rather
            // than only being discoverable at the bottom.
            _AllocationTotal(total: totalAllocated),
          ],
        ),
        const SizedBox(height: 16),
        _ColumnHeader(),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: groups.isEmpty
              ? _EmptyState(
                  isSearching: searchController.text.trim().isNotEmpty,
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: groups.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) => _ProductGroup(
                    group: groups[index],
                    onAllocationChanged: onAllocationChanged,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black45,
      fontWeight: FontWeight.w600,
      fontSize: 11.5,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Row(
        children: [
          Expanded(child: Text('Product / variant', style: style)),
          const SizedBox(width: _columnGap),
          SizedBox(
            width: _allocateColumn,
            child: Text('Allocate', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: _columnGap),
          SizedBox(
            width: _availableColumn,
            child: Text(
              'Left in stock',
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductGroup extends StatelessWidget {
  const _ProductGroup({required this.group, required this.onAllocationChanged});

  final StockAllocationGroup group;
  final void Function(String itemKey, int value) onAllocationChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allocatedHere = group.rows.fold<int>(0, (s, r) => s + r.allocated);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Per-product subtotal, so a collapsed scan of the list still
              // answers "did I allocate anything for this product?".
              if (allocatedHere > 0)
                Text(
                  '${formatCount(allocatedHere)} allocated',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < group.rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _AllocationRow(
              row: group.rows[i],
              onChanged: (value) =>
                  onAllocationChanged(group.rows[i].key, value),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.row, required this.onChanged});

  final StockAllocationRow row;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = row.remaining == 0;

    return Row(
      children: [
        Expanded(
          child: Padding(
            // Indented under the product name so the variant reads as
            // belonging to it without needing a box around the group.
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black87,
              ),
            ),
          ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _allocateColumn,
          child: Center(
            child: QuantityStepper(
              value: row.allocated,
              // Cap is what's left plus what this row already took, so the
              // plus disables exactly when master stock runs out.
              max: row.allocated + row.remaining,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: _columnGap),
        SizedBox(
          width: _availableColumn,
          child: Text(
            isOut ? 'None left' : formatCount(row.remaining),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isOut ? AppColors.error : Colors.black54,
              fontWeight: isOut ? FontWeight.w600 : FontWeight.w500,
              fontSize: isOut ? 12 : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _AllocationTotal extends StatelessWidget {
  const _AllocationTotal({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: total > 0 ? AppColors.primaryLight : AppColors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatCount(total),
            style: theme.textTheme.titleMedium?.copyWith(
              color: total > 0 ? AppColors.primary : Colors.black38,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            total == 1 ? 'unit allocated' : 'units allocated',
            style: theme.textTheme.bodySmall?.copyWith(
              color: total > 0 ? AppColors.primary : Colors.black45,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 30,
            color: Colors.black26,
          ),
          const SizedBox(height: 10),
          Text(
            isSearching
                ? 'No products match your search.'
                : 'No active products to allocate.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
          if (!isSearching) ...[
            const SizedBox(height: 4),
            Text(
              'Only Active products can be allocated — check Master Inventory.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black38),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../data/repositories/product_repository.dart'
    show ProductRepository, VariantCategoryDraft;
import '../../../models/product.dart';
import '../../../models/product_variant.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/product_thumbnail.dart';
import '../../widgets/selectable_option_button.dart';
import '../../../core/utils/formatters.dart';

/// Outline for unchecked boxes in the inventory table. Material's default is
/// a 2px `onSurface` rule, which reads heavier than the hairline dividers
/// around it; this thins and softens it to match. A plain [BorderSide] is
/// only drawn while unchecked, so the checked state keeps its solid purple
/// fill. Kept above the default hairline colour so the control still has a
/// visible boundary — an invisible checkbox is not a minimal one.
const BorderSide _checkboxSide = BorderSide(color: Colors.black26, width: 1.2);

/// Horizontal inset for the table's header, rows and bulk bar. The page
/// gutter is 24; a compact checkbox paints an 18px box centred in a 32px hit
/// target, so ~7px of transparent padding already sits to its left.
/// Insetting by 16 lands the checkbox's visible edge on the gutter, keeping
/// the table optically aligned with the title and KPIs above it even though
/// the surface itself now runs full-bleed.
const double _tableInset = 16;

/// Hairline used for every rule on this screen and in its dialogs — between
/// table rows, and between a dialog's header, body and footer.
const Color _borderColor = Color(0xFFEDEDF1);

/// The single rule dividing the controls from the table. It reads a step
/// darker than [_borderColor] on purpose: with the table's container gone,
/// this line is the only thing marking where the data region starts, so it
/// should outrank the hairlines *between* rows rather than match them.
const Color _separatorColor = Color(0xFFE2E2E8);

/// Row hover tint, so "this row is under the cursor" looks the same
/// everywhere it appears.
const Color _rowHoverColor = Color(0xFFFAFAFC);

/// Fill for text inputs and the photo well in this screen's dialogs.
///
/// A neutral gray rather than the old purple-tinted `#F5F1FB`: `primaryLight`
/// is the *unselected* fill in the selection colour rule, so using it on
/// inputs made ordinary fields carry a hint of "option you can pick". Neutral
/// grey leaves purple to mean brand and selection.
///
/// Sits a clear step below [AppColors.surface] (`#FEFEFE`) so a field is
/// legible as a field, and a step below the `#F7F7F9` panels so an input
/// nested inside one can invert to white without the two reading as the same
/// depth.
const Color _inputFill = Color(0xFFF0F1F4);

/// Tap-target footprint of a [_RowActionButton]. Shared so a table or form
/// column can reserve exactly the space one occupies and stay aligned.
const double _rowActionSize = 34;

/// Size for the small trailing action icons (rename, delete, close).
///
/// Flutter bundles Material Icons as a *static* font, so `Icon.weight` — the
/// variable-font axis that would genuinely thin a glyph — has no effect here.
/// Apparent stroke weight is reduced the two ways that do work: the outlined
/// icon set, and size. A 24px glyph's ~2px stroke scales to ~1.4px at 17,
/// which is what actually makes these read as light rather than chunky.
const double _actionIconSize = 17;

/// Which SKUs the table is showing.
///
/// Four of these are lifecycle states; [outOfStock] is derived from stock
/// instead. Mixing them in one bar is deliberate — from the user's side these
/// are all just "which part of the inventory am I looking at", and splitting
/// them into a tab bar plus a separate stock filter would make the most
/// common question ("what's empty?") the hardest one to ask.
enum _InventoryTab { all, active, draft, archived, outOfStock }

extension _InventoryTabLabel on _InventoryTab {
  String get label => switch (this) {
    _InventoryTab.all => 'All',
    _InventoryTab.active => 'Active',
    _InventoryTab.draft => 'Draft',
    _InventoryTab.archived => 'Archived',
    _InventoryTab.outOfStock => 'Out of stock',
  };

  bool matches(InventoryRow row) => switch (this) {
    _InventoryTab.all => true,
    _InventoryTab.active => row.status == ProductStatus.active,
    _InventoryTab.draft => row.status == ProductStatus.draft,
    _InventoryTab.archived => row.status == ProductStatus.archived,
    // Archived SKUs are excluded on purpose: this tab is a worklist of
    // what still needs a decision, so archiving something removes it from
    // the list rather than leaving it there to be re-read every time.
    _InventoryTab.outOfStock =>
      row.stock == 0 && row.status != ProductStatus.archived,
  };
}

/// Row ordering for the master inventory table.
///
/// Deliberately a small, closed set: four named orders in a menu beat a free
/// "sort by column + direction" matrix here, because only two columns are
/// worth ordering by and stating them in words ("Lowest stock") is plainer
/// than asking the user to assemble the same meaning from a column and an
/// arrow (Hick's law — fewer, clearer choices).
enum _InventorySort { nameAsc, nameDesc, stockDesc, stockAsc }

extension _InventorySortLabel on _InventorySort {
  String get label => switch (this) {
    _InventorySort.nameAsc => 'Name (A–Z)',
    _InventorySort.nameDesc => 'Name (Z–A)',
    _InventorySort.stockDesc => 'Highest stock',
    _InventorySort.stockAsc => 'Lowest stock',
  };
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Selection is per SKU, keyed by allocation key — archiving acts on one
  /// combination, so selecting whole products would be the wrong granularity.
  final Set<String> _selectedKeys = <String>{};
  _InventoryTab _tab = _InventoryTab.all;
  _InventorySort _sort = _InventorySort.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryRow> _visibleRows(InventoryState state) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = state.rows.where((row) {
      if (!_tab.matches(row)) return false;
      if (query.isEmpty) return true;
      // Searches down to the SKU, so "triple white" or "37" narrows to the
      // matching combinations rather than to whole products.
      return row.product.name.toLowerCase().contains(query) ||
          (row.optionOneValue?.toLowerCase().contains(query) ?? false) ||
          (row.optionTwoValue?.toLowerCase().contains(query) ?? false);
    }).toList();
    return _sortRows(filtered);
  }

  /// Sorts the SKUs flat — each one stands on its own.
  ///
  /// Rows used to be grouped under a lead product row, which meant a stock
  /// sort could only reorder whole products: the single empty size inside an
  /// otherwise full product stayed buried in its block. Sorting the rows
  /// themselves is what lets "Lowest stock" actually surface every empty
  /// combination, wherever it lives.
  List<InventoryRow> _sortRows(List<InventoryRow> rows) {
    final sorted = [...rows];
    int byName(InventoryRow a, InventoryRow b) {
      final result = a.product.name.toLowerCase().compareTo(
        b.product.name.toLowerCase(),
      );
      // Same product: keep its combinations in their defined order, so an
      // alphabetical list still reads Color-then-Size within a product.
      if (result != 0) return result;
      return _variantLabel(a).compareTo(_variantLabel(b));
    }

    sorted.sort((a, b) {
      switch (_sort) {
        case _InventorySort.nameAsc:
          return byName(a, b);
        case _InventorySort.nameDesc:
          return byName(b, a);
        case _InventorySort.stockDesc:
          final result = b.stock.compareTo(a.stock);
          // Alphabetical tiebreak, so equal stock isn't shuffled arbitrarily.
          return result != 0 ? result : byName(a, b);
        case _InventorySort.stockAsc:
          final result = a.stock.compareTo(b.stock);
          return result != 0 ? result : byName(a, b);
      }
    });
    return sorted;
  }

  String _variantLabel(InventoryRow row) =>
      '${row.optionOneValue ?? ''}|${row.optionTwoValue ?? ''}';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryCubit, InventoryState>(
      builder: (context, state) {
        final rows = _visibleRows(state);
        return ColoredBox(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 20),
                    _buildKpiRow(context, state),
                    const SizedBox(height: 20),
                    _buildToolbar(context, state),
                  ],
                ),
              ),
              // The table is no longer drawn as a card. One full-bleed rule
              // separates the controls from the data, and the table's own
              // surface picks up immediately below it — so the line reads as
              // the top edge of the table region rather than as a border
              // floating inside the page.
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: _separatorColor)),
                  ),
                  child: _buildTable(context, state, rows),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Master Inventory',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (widget.user.isAdminOrOwner) ...[
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              // The one primary action on this screen, so it earns the
              // most generous target of anything in the header.
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            label: const Text('Add Product'),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiRow(BuildContext context, InventoryState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _InventoryKpiCard(
            label: 'Total inventory volume',
            value: formatCount(state.totalVolume),
          ),
          _InventoryKpiCard(
            label: 'Inventory value',
            value: formatPeso(state.inventoryValue),
          ),
          _InventoryKpiCard(
            label: 'Inventory turnover',
            value: state.inventoryTurnover.toStringAsFixed(2),
          ),
        ];
        // Below ~720px three side-by-side cards squeeze their numbers into
        // ellipses, so stack them instead of letting the values truncate.
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context, InventoryState state) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StatusTabs(
          selected: _tab,
          onSelected: (tab) => setState(() {
            _tab = tab;
            _selectedKeys.clear();
          }),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search products',
              hintStyle: const TextStyle(color: Colors.black38),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: Colors.black45,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      splashRadius: 18,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: true,
              fillColor: AppColors.surface,
              border: _inputBorder(_borderColor),
              enabledBorder: _inputBorder(_borderColor),
              focusedBorder: _inputBorder(AppColors.primary, width: 1.5),
            ),
          ),
        ),
        _SortDropdown(
          selected: _sort,
          onSelected: (sort) => setState(() => _sort = sort),
        ),
      ],
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget _buildTable(
    BuildContext context,
    InventoryState state,
    List<InventoryRow> rows,
  ) {
    final canManage = widget.user.isAdminOrOwner;
    final visibleKeys = {for (final row in rows) row.allocationKey};
    final selectedVisible = _selectedKeys.intersection(visibleKeys);
    final allSelected =
        visibleKeys.isNotEmpty && selectedVisible.length == visibleKeys.length;

    // No fill or outline of its own: the surface and the top rule come from
    // the band this sits inside, so the table is a region of the page rather
    // than an object on it.
    return Column(
      children: [
        // Contextual bulk bar: only appears once something is selected, so
        // it never occupies space it hasn't earned.
        AnimatedSize(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          alignment: Alignment.topCenter,
          child: selectedVisible.isEmpty
              ? const SizedBox(width: double.infinity)
              : _buildBulkBar(context, rows, selectedVisible),
        ),
        _buildTableHeader(context, canManage, allSelected, rows),
        const Divider(height: 1, color: _borderColor),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  itemCount: rows.length,
                  // Uniform rules: every row is an equal, self-contained item
                  // now, so nothing should look nested under anything else.
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: _borderColor),
                  itemBuilder: (context, index) =>
                      _buildRow(context, rows[index], canManage),
                ),
        ),
      ],
    );
  }

  Widget _buildBulkBar(
    BuildContext context,
    List<InventoryRow> rows,
    Set<String> selected,
  ) {
    final selectedRows = rows
        .where((row) => selected.contains(row.allocationKey))
        .toList();
    // If everything picked is already archived, the useful action is putting
    // it back — offering "Archive" there would be a no-op the user can't
    // undo from this bar.
    final allArchived =
        selectedRows.isNotEmpty &&
        selectedRows.every((row) => row.status == ProductStatus.archived);
    final affectedProducts = {for (final row in selectedRows) row.product.id};

    return Container(
      width: double.infinity,
      // No fill: the bar is separated from the header by a rule instead, so
      // it doesn't read as a second, competing surface inside the table.
      padding: const EdgeInsets.fromLTRB(_tableInset, 8, _tableInset, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Text(
            '${selected.length} selected',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () =>
                _setArchivedForKeys(context, selected, archived: !allArchived),
            icon: Icon(
              allArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              size: 16,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            label: Text(allArchived ? 'Restore' : 'Archive'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _deleteSelectedProducts(
              context,
              selectedRows,
              affectedProducts,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            // Named "product" because that is the granularity: a single
            // combination can't be deleted without editing the product's
            // variants, so the label must not imply otherwise.
            label: Text(
              affectedProducts.length == 1
                  ? 'Delete product'
                  : 'Delete ${affectedProducts.length} products',
            ),
          ),
        ],
      ),
    );
  }

  /// Archiving is reversible, so it applies immediately with a confirmation
  /// message rather than blocking behind a dialog — modals are for actions
  /// the user cannot take back.
  Future<void> _setArchivedForKeys(
    BuildContext context,
    Set<String> keys, {
    required bool archived,
  }) async {
    final count = keys.length;
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<InventoryCubit>();
    await cubit.setArchivedForKeys(keys, archived: archived);
    if (!mounted) return;
    setState(_selectedKeys.clear);
    final noun = count == 1 ? 'variant' : 'variants';
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Text(
          archived
              ? '$count $noun archived. Their stock can no longer be allocated to a bazaar.'
              : '$count $noun restored.',
        ),
      ),
    );
  }

  /// Deletion is product-level, so the confirmation names the products that
  /// will actually disappear rather than counting the rows that were ticked.
  Future<void> _deleteSelectedProducts(
    BuildContext context,
    List<InventoryRow> selectedRows,
    Set<int> productIds,
  ) async {
    final names = <String>{for (final row in selectedRows) row.product.name};
    final listed = names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')} and ${names.length - 3} more';
    final cubit = context.read<InventoryCubit>();

    final confirmed = await showConfirmationDialog(
      context: context,
      title: productIds.length == 1 ? 'Delete product' : 'Delete products',
      message: productIds.length == 1
          ? 'Delete "$listed"? Every variant and all its stock go with it. '
                'This cannot be undone.'
          : 'Delete $listed? Every variant and all their stock go with them. '
                'This cannot be undone.',
      confirmLabel: 'Delete',
      tone: ConfirmationTone.destructive,
    );
    if (!confirmed || !mounted) return;
    await cubit.deleteMany(productIds);
    if (!mounted) return;
    setState(_selectedKeys.clear);
  }

  Widget _buildTableHeader(
    BuildContext context,
    bool canManage,
    bool allSelected,
    List<InventoryRow> rows,
  ) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black45,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(_tableInset, 12, _tableInset, 12),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: canManage
                ? Checkbox(
                    value: allSelected,
                    // Tri-state would imply a third meaning; a plain
                    // select-all/none is enough here.
                    onChanged: rows.isEmpty
                        ? null
                        : (value) => setState(() {
                            final keys = {
                              for (final row in rows) row.allocationKey,
                            };
                            if (value == true) {
                              _selectedKeys.addAll(keys);
                            } else {
                              _selectedKeys.removeAll(keys);
                            }
                          }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: AppColors.primary,
                    side: _checkboxSide,
                  )
                : null,
          ),
          Expanded(flex: 5, child: Text('Product', style: style)),
          Expanded(flex: 3, child: Text('Category 1', style: style)),
          Expanded(flex: 3, child: Text('Category 2', style: style)),
          SizedBox(width: 80, child: Text('Stock', style: style)),
          if (canManage) const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// One SKU row — a complete, self-contained item.
  ///
  /// Every row carries its own photo, name, checkbox and archive action.
  /// Rows used to be grouped, with those controls appearing once per product
  /// on a lead row, which meant a single empty combination could not be
  /// selected or retired on its own. Treating each SKU as its own thing is
  /// what makes "archive the sizes we're out of" possible at all.
  Widget _buildRow(BuildContext context, InventoryRow row, bool canManage) {
    final product = row.product;
    final isSelected = _selectedKeys.contains(row.allocationKey);
    final isArchived = row.status == ProductStatus.archived;

    return _InventoryTableRow(
      isSelected: isSelected,
      onTap: canManage
          ? () => _showProductDialog(context, product: product)
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: canManage
                ? Checkbox(
                    value: isSelected,
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedKeys.add(row.allocationKey);
                      } else {
                        _selectedKeys.remove(row.allocationKey);
                      }
                    }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: AppColors.primary,
                    side: _checkboxSide,
                  )
                : null,
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                // 1:1 product photo, matching the row height.
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ProductThumbnail(
                    imagePath: product.imagePath,
                    imageBytes: product.imageBytes,
                    borderRadius: BorderRadius.circular(8),
                    iconSize: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          // Surfaced on every tab, not just the Archived one,
                          // so "why can't I allocate this?" is answerable
                          // without changing filters.
                          if (row.status != ProductStatus.active) ...[
                            const SizedBox(width: 8),
                            _StatusBadge(status: row.status),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatPeso(product.basePrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _VariantValueCell(value: row.optionOneValue),
          ),
          Expanded(
            flex: 3,
            child: _VariantValueCell(value: row.optionTwoValue),
          ),
          SizedBox(width: 80, child: _StockCell(quantity: row.stock)),
          if (canManage)
            SizedBox(
              width: 40,
              // Archive, not delete. Retiring one empty combination is the
              // per-row action that makes sense; deleting from here would
              // destroy the whole product from a row that represents one of
              // its sizes, so deletion stays in the bulk bar where the
              // confirmation can name what it's about to remove.
              child: _RowActionButton(
                icon: isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                tooltip: isArchived
                    ? 'Restore this variant'
                    : 'Archive this variant',
                hoverColor: AppColors.primary,
                onPressed: () => _setArchivedForKeys(context, {
                  row.allocationKey,
                }, archived: !isArchived),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasFilters =
        _searchController.text.trim().isNotEmpty || _tab != _InventoryTab.all;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 38,
            color: Colors.black26,
          ),
          const SizedBox(height: 10),
          Text(
            hasFilters
                ? 'No products match your search and filters.'
                : 'No products in the master inventory yet.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await _showProductDialog(context);
  }

  /// Resolves everything the product form needs *before* opening it, so the
  /// dialog never has to render a spinner where its own fields should be.
  Future<void> _showProductDialog(
    BuildContext context, {
    Product? product,
  }) async {
    final cubit = context.read<InventoryCubit>();

    final variantCategories = <_VariantCategoryInput>[];
    final comboStock = <String, String>{};

    if (product != null) {
      final groups = await cubit.variantGroupsForProduct(product.id);
      final optionsByGroup = <List<ProductVariantOption>>[];
      for (final group in groups) {
        final options = await cubit.variantOptionsForGroup(group.id);
        optionsByGroup.add(options);
        variantCategories.add(
          _VariantCategoryInput(name: group.name)
            ..values.addAll(
              options.map(
                (option) => _VariantValueInput(
                  value: option.value,
                  extraPrice: _plainNumber(option.extraPrice),
                ),
              ),
            ),
        );
      }
      if (variantCategories.isNotEmpty) {
        final stocks = await cubit.combinationStocksForProduct(product.id);
        if (optionsByGroup.length == 1) {
          for (final optionA in optionsByGroup[0]) {
            final stock = stocks[(optionA.id, null)] ?? 0;
            comboStock[ProductRepository.combinationValueKey(optionA.value)] =
                stock == 0 ? '' : stock.toString();
          }
        } else if (optionsByGroup.length == 2) {
          for (final optionA in optionsByGroup[0]) {
            for (final optionB in optionsByGroup[1]) {
              final key = ProductRepository.combinationValueKey(
                optionA.value,
                optionB.value,
              );
              final stock = stocks[(optionA.id, optionB.id)] ?? 0;
              comboStock[key] = stock == 0 ? '' : stock.toString();
            }
          }
        }
      }
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      // A part-filled form shouldn't be thrown away by a stray click on the
      // scrim. Cancel and × are the deliberate ways out.
      barrierDismissible: false,
      builder: (_) => BlocProvider<InventoryCubit>.value(
        value: cubit,
        child: _ProductFormDialog(
          product: product,
          variantCategories: variantCategories,
          comboStock: comboStock,
        ),
      ),
    );
  }
}

/// A quiet trailing icon button that only takes on colour under the cursor.
///
/// Painting every destructive icon red would make a plain list of rows look
/// hazardous, and once everything is red nothing reads as dangerous (Von
/// Restorff). Resting grey, red at the moment of intent, gets the warning to
/// the user exactly when it's useful.
class _RowActionButton extends StatefulWidget {
  const _RowActionButton({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color hoverColor;

  /// Null disables the button; the icon drops to `black26` so "can't do this
  /// right now" is visible rather than only discoverable by clicking.
  final VoidCallback? onPressed;

  @override
  State<_RowActionButton> createState() => _RowActionButtonState();
}

class _RowActionButtonState extends State<_RowActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        onPressed: widget.onPressed,
        splashRadius: 18,
        tooltip: widget.tooltip,
        constraints: const BoxConstraints(
          minWidth: _rowActionSize,
          minHeight: _rowActionSize,
        ),
        padding: EdgeInsets.zero,
        // Hover is seen dozens of times a session, so the transition stays at
        // the shortest token — enough to avoid a hard snap, not enough to
        // notice as an animation.
        icon: TweenAnimationBuilder<Color?>(
          duration: AppMotion.feedback,
          curve: AppMotion.easeOut,
          tween: ColorTween(
            begin: Colors.black38,
            end: widget.onPressed == null
                ? Colors.black26
                : _hovered
                ? widget.hoverColor
                : Colors.black38,
          ),
          builder: (context, color, _) =>
              Icon(widget.icon, size: _actionIconSize, color: color),
        ),
      ),
    );
  }
}

/// One variant group being edited (e.g. "Color") and its values.
///
/// The controllers live on the model rather than in the widget tree: the old
/// form used `TextFormField.initialValue` inside an unkeyed list, so removing
/// row 1 of 3 left row 2's text sitting in row 1. Tying the controller to the
/// object means text follows the value it belongs to, whatever its index.
class _VariantCategoryInput {
  _VariantCategoryInput({String name = ''})
    : nameController = TextEditingController(text: name);

  final TextEditingController nameController;
  final List<_VariantValueInput> values = [];

  String get name => nameController.text;

  void dispose() {
    nameController.dispose();
    for (final value in values) {
      value.dispose();
    }
  }
}

class _VariantValueInput {
  _VariantValueInput({String value = '', String extraPrice = '0'})
    : valueController = TextEditingController(text: value),
      extraPriceController = TextEditingController(text: extraPrice);

  final TextEditingController valueController;
  final TextEditingController extraPriceController;

  String get value => valueController.text;
  String get extraPrice => extraPriceController.text;

  void dispose() {
    valueController.dispose();
    extraPriceController.dispose();
  }
}

class _InventoryKpiCard extends StatelessWidget {
  const _InventoryKpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            // The value is the reason this card exists, so it gets the
            // largest type on the screen. Scaled down rather than
            // ellipsized if a number outgrows its column — a truncated
            // figure is worse than a slightly smaller one.
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

/// All / Active / Draft / Archived / Out of stock.
///
/// Underline tabs rather than filled chips: this is a view switcher over one
/// dataset, and tabs are the pattern people already read that way (Jakob's
/// Law).
class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.selected, required this.onSelected});

  final _InventoryTab selected;
  final ValueChanged<_InventoryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in _InventoryTab.values) ...[
          if (tab != _InventoryTab.all) const SizedBox(width: 18),
          _StatusTab(
            label: tab.label,
            isSelected: selected == tab,
            onTap: () => onSelected(tab),
          ),
        ],
      ],
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected ? AppColors.primary : Colors.black54,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: AppMotion.small,
              curve: AppMotion.easeOut,
              height: 2.5,
              width: isSelected ? 20 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A table row with hover/selection feedback.
///
/// Hover is gated behind a fine pointer so touch devices don't latch a
/// hover state on tap.
class _InventoryTableRow extends StatefulWidget {
  const _InventoryTableRow({
    required this.child,
    required this.isSelected,
    this.onTap,
  });

  final Widget child;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<_InventoryTableRow> createState() => _InventoryTableRowState();
}

class _InventoryTableRowState extends State<_InventoryTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isSelected
        ? AppColors.primaryLight
        : _hovered
        ? _rowHoverColor
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          color: color,
          padding: const EdgeInsets.fromLTRB(_tableInset, 10, _tableInset, 10),
          child: widget.child,
        ),
      ),
    );
  }
}

/// One variant value in a SKU row, e.g. "Triple White" or "37".
///
/// Renders a muted dash when the product doesn't use this variant group, so
/// an empty cell reads as "not applicable" rather than as missing data.
class _VariantValueCell extends StatelessWidget {
  const _VariantValueCell({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return Text(
        '—',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.black26),
      );
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _StockCell extends StatelessWidget {
  const _StockCell({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    final (color, weight) = switch (quantity) {
      0 => (AppColors.error, FontWeight.w700),
      < 10 => (const Color(0xFFB45309), FontWeight.w700),
      _ => (AppColors.text, FontWeight.w600),
    };
    return Text(
      quantity == 0 ? 'Out of stock' : '$quantity',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: color,
        fontWeight: weight,
        fontSize: quantity == 0 ? 11.5 : null,
      ),
    );
  }
}

/// Small badge marking a product that isn't Active.
///
/// Active products get no badge at all — labelling the normal case adds ink
/// to every row without adding information. Only the exceptions are marked.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ProductStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProductStatus.archived => const Color(0xFF4B5563),
      ProductStatus.draft => const Color(0xFFB45309),
      ProductStatus.active => const Color(0xFF2E7D32),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

/// Renders a double without a trailing `.0`, so an extra price of 0 shows as
/// "0" in a text field rather than "0.0".
String _plainNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

enum _ProductStep { details, options, stock }

/// Add/Edit Product.
///
/// Replaces a ~760-line `StatefulBuilder` closure. Beyond the visual pass,
/// four things were wrong with the old form and are fixed here:
///
/// 1. **Errors appeared as SnackBars** at the bottom of the *screen* — away
///    from the field at fault, auto-dismissing, and never marking which input
///    to fix. Validation is now inline, next to the offending field.
/// 2. **A three-step flow with no visible steps.** Turning on variants
///    silently turned Save into Next, twice. There's now a stepper showing
///    where you are and how much is left.
/// 3. **Variant rows lost their text.** Rows used `TextFormField.initialValue`
///    with no keys, so deleting row 1 of 3 left row 2's text sitting in row 1.
///    Each input now owns a controller tied to its object, not its index.
/// 4. **Controllers were never disposed** — the old closure leaked one set per
///    open. A real [State] disposes them.
class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.product,
    required this.variantCategories,
    required this.comboStock,
  });

  final Product? product;

  /// Pre-loaded variant groups for an edit; the dialog takes ownership and
  /// disposes their controllers.
  final List<_VariantCategoryInput> variantCategories;
  final Map<String, String> comboStock;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;

  /// Stock inputs for variant combinations, keyed by combination. Built
  /// lazily because the set of combinations changes as the user edits values.
  final Map<String, TextEditingController> _comboControllers = {};

  late final List<_VariantCategoryInput> _variantCategories;
  late bool _hasVariants;
  late ProductStatus _status;
  String? _imagePath;
  Uint8List? _imageBytes;
  _ProductStep _step = _ProductStep.details;
  bool _saving = false;

  String? _nameError;
  String? _priceError;
  String? _stockError;

  /// For problems that belong to the step as a whole rather than one field
  /// (e.g. "add at least one variant category").
  String? _stepError;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _priceController = TextEditingController(
      text: product == null ? '' : _plainNumber(product.basePrice),
    );
    _stockController = TextEditingController(
      text: product == null ? '' : product.stockQuantity.toString(),
    );
    _variantCategories = widget.variantCategories;
    _hasVariants = _variantCategories.isNotEmpty;
    _status = product?.status ?? ProductStatus.active;
    _imagePath = product?.imagePath;
    _imageBytes = product?.imageBytes;
    widget.comboStock.forEach((key, value) {
      _comboControllers[key] = TextEditingController(text: value);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    for (final controller in _comboControllers.values) {
      controller.dispose();
    }
    for (final category in _variantCategories) {
      category.dispose();
    }
    super.dispose();
  }

  /// Stock boxes start *empty* rather than pre-filled with "0". A literal 0
  /// sitting in the field has to be selected and deleted before a real number
  /// can be typed, on every box; as a hint it communicates the same default
  /// without standing in the way. An empty box is read as 0 everywhere below.
  TextEditingController _comboController(String key) {
    return _comboControllers.putIfAbsent(key, TextEditingController.new);
  }

  /// A stock box's value, treating blank as 0. Returns null only when the text
  /// is present but isn't a whole number.
  int? _comboStockValue(String key) {
    final text = _comboController(key).text.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text);
  }

  /// Every sellable combination of the current variant values, in the same
  /// key format the repository stores stock under.
  List<String> _comboKeys() {
    if (_variantCategories.isEmpty) return const [];
    final valuesA = _nonEmptyValues(_variantCategories[0]);
    if (_variantCategories.length == 1) {
      return [
        for (final a in valuesA) ProductRepository.combinationValueKey(a),
      ];
    }
    final valuesB = _nonEmptyValues(_variantCategories[1]);
    return [
      for (final a in valuesA)
        for (final b in valuesB) ProductRepository.combinationValueKey(a, b),
    ];
  }

  List<String> _nonEmptyValues(_VariantCategoryInput category) {
    return category.values
        .map((value) => value.value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  int _totalComboStock() {
    return _comboKeys().fold<int>(
      0,
      (sum, key) => sum + (_comboStockValue(key) ?? 0),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _pickImage() async {
    // Downscaled at pick time by the plugin itself: a modern phone photo is
    // several thousand pixels wide, and the largest place this is ever drawn
    // is a product card. Capping here keeps the bytes we hold in memory
    // proportional to what's actually displayed.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    // Read as bytes rather than keeping the path. On the web `XFile.path` is
    // a `blob:` URL that neither Image.asset nor Image.file can load, and
    // dart:io's File doesn't exist there — bytes are the one representation
    // that renders on every platform this app targets.
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      // A picked photo has no addressable location, so any inherited asset
      // path is now stale and would win over the new bytes on the next edit.
      _imagePath = null;
    });
  }

  /// Validates the details step, filling in per-field errors.
  bool _validateDetails() {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim());

    setState(() {
      _nameError = name.isEmpty ? 'Product name is required.' : null;
      _priceError = _priceController.text.trim().isEmpty
          ? 'Base price is required.'
          : price == null
          ? 'Enter a number, e.g. 1800.'
          : price <= 0
          ? 'Price must be more than 0.'
          : null;
      _stockError = _hasVariants
          ? null
          : _stockController.text.trim().isEmpty
          ? 'Stock is required.'
          : stock == null
          ? 'Enter a whole number.'
          : stock < 0
          ? 'Stock cannot be negative.'
          : null;
      _stepError = null;
    });

    return _nameError == null && _priceError == null && _stockError == null;
  }

  /// Validates the variant-options step. These failures are reported as one
  /// step-level message because they're about the set of options, not about a
  /// single input the user can be pointed at.
  bool _validateOptions() {
    String? error;
    if (_variantCategories.isEmpty) {
      error = 'Add at least one option group, e.g. Color.';
    }
    for (final category in _variantCategories) {
      if (error != null) break;
      final name = category.name.trim();
      if (name.isEmpty) {
        error = 'Every option group needs a name.';
        break;
      }
      final values = _nonEmptyValues(category);
      if (values.isEmpty) {
        error = 'Add at least one value for "$name".';
        break;
      }
      final unique = values.map((value) => value.toUpperCase()).toSet();
      if (unique.length != values.length) {
        error = 'Values in "$name" must each be different.';
      }
    }
    setState(() => _stepError = error);
    return error == null;
  }

  bool _validateStock() {
    String? error;
    for (final key in _comboKeys()) {
      final parsed = _comboStockValue(key);
      if (parsed == null) {
        error = 'Every combination needs a whole number.';
        break;
      }
      if (parsed < 0) {
        error = 'Stock cannot be negative.';
        break;
      }
    }
    setState(() => _stepError = error);
    return error == null;
  }

  void _goBack() {
    setState(() {
      _stepError = null;
      _step = _step == _ProductStep.stock
          ? _ProductStep.options
          : _ProductStep.details;
    });
  }

  /// Advances, or saves on the last step. The primary button is the only way
  /// forward, so it owns both jobs.
  Future<void> _submit() async {
    if (_saving) return;

    if (_step == _ProductStep.details) {
      if (!_validateDetails()) return;
      if (!_hasVariants) {
        await _save();
        return;
      }
      setState(() {
        // Seed an empty group so the next step opens with something to fill
        // in rather than a bare "Add option group" button.
        if (_variantCategories.isEmpty) {
          _variantCategories.add(
            _VariantCategoryInput()..values.add(_VariantValueInput()),
          );
        }
        for (final category in _variantCategories) {
          if (category.values.isEmpty) {
            category.values.add(_VariantValueInput());
          }
        }
        _step = _ProductStep.options;
      });
      return;
    }

    if (_step == _ProductStep.options) {
      if (!_validateOptions()) return;
      setState(() => _step = _ProductStep.stock);
      return;
    }

    if (!_validateStock()) return;
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cubit = context.read<InventoryCubit>();
    final name = _nameController.text.trim();
    final basePrice = double.parse(_priceController.text.trim());

    if (!_hasVariants) {
      await cubit.saveProduct(
        id: widget.product?.id,
        name: name,
        description: widget.product?.description,
        basePrice: basePrice,
        imagePath: _imagePath,
        imageBytes: _imageBytes,
        stockQuantity: int.parse(_stockController.text.trim()),
        status: _status,
      );
    } else {
      final combinationStocks = <String, int>{
        for (final key in _comboKeys()) key: _comboStockValue(key) ?? 0,
      };
      final variantGroups = _variantCategories.map((category) {
        return VariantCategoryDraft(
          name: category.name.trim(),
          optionValues: category.values.map((value) => value.value).toList(),
          extraPriceByValue: {
            for (final value in category.values)
              value.value: double.tryParse(value.extraPrice.trim()) ?? 0,
          },
        );
      }).toList();

      await cubit.saveProduct(
        id: widget.product?.id,
        name: name,
        description: widget.product?.description,
        basePrice: basePrice,
        imagePath: _imagePath,
        imageBytes: _imageBytes,
        variantGroups: variantGroups,
        combinationStocks: combinationStocks,
        status: _status,
      );
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: _borderColor),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: _buildStepBody(context),
              ),
            ),
            const Divider(height: 1, color: _borderColor),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _isEditing ? 'Edit Product' : 'Add Product',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                splashRadius: 18,
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  size: _actionIconSize,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          // The stepper only exists when there's more than one step to be at.
          AnimatedSize(
            duration: AppMotion.small,
            curve: AppMotion.easeOut,
            alignment: Alignment.topLeft,
            child: _hasVariants
                ? Padding(
                    padding: const EdgeInsets.only(top: 12, right: 14),
                    child: _buildStepper(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(BuildContext context) {
    const labels = ['Details', 'Options', 'Stock'];
    final currentIndex = _ProductStep.values.indexOf(_step);

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i <= currentIndex ? AppColors.primary : _borderColor,
              ),
            ),
          _StepMarker(
            number: i + 1,
            label: labels[i],
            isDone: i < currentIndex,
            isCurrent: i == currentIndex,
            // Steps already cleared can be revisited; jumping ahead would
            // skip the validation that earns the next step.
            onTap: i < currentIndex
                ? () => setState(() {
                    _stepError = null;
                    _step = _ProductStep.values[i];
                  })
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildStepBody(BuildContext context) {
    return switch (_step) {
      _ProductStep.details => _buildDetailsStep(context),
      _ProductStep.options => _buildOptionsStep(context),
      _ProductStep.stock => _buildStockStep(context),
    };
  }

  // ---------------------------------------------------------- details step

  Widget _buildDetailsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImagePicker(context),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FormField(
                    label: 'Product name',
                    error: _nameError,
                    child: TextField(
                      controller: _nameController,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      style: Theme.of(context).textTheme.bodyMedium,
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                      decoration: _fieldDecoration(
                        hint: 'e.g. Air Jordan 1 Low',
                        hasError: _nameError != null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FormField(
                label: 'Base price',
                error: _priceError,
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (_) {
                    if (_priceError != null) {
                      setState(() => _priceError = null);
                    }
                  },
                  decoration: _fieldDecoration(
                    hint: '0.00',
                    hasError: _priceError != null,
                    prefixText: 'PHP',
                  ),
                ),
              ),
            ),
            // With variants on, stock is entered per combination on step 3 —
            // a single stock box here would contradict that.
            if (!_hasVariants) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _FormField(
                  label: 'Stock quantity',
                  error: _stockError,
                  child: TextField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (_) {
                      if (_stockError != null) {
                        setState(() => _stockError = null);
                      }
                    },
                    decoration: _fieldDecoration(
                      hint: 'e.g. 24',
                      hasError: _stockError != null,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        // Section break, one step up the scale from the 16 between fields,
        // so Status and the variants panel read as their own groups.
        const SizedBox(height: 24),
        _buildStatusField(context),
        const SizedBox(height: 24),
        _buildVariantToggle(context),
      ],
    );
  }

  Widget _buildImagePicker(BuildContext context) {
    final hasImage =
        (_imageBytes != null && _imageBytes!.isNotEmpty) ||
        (_imagePath != null && _imagePath!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel(text: 'Photo'),
        const SizedBox(height: 6),
        // 1:1, matching how the table and POS grid render a product — what
        // you frame here is what you'll see there.
        SizedBox(
          width: 104,
          height: 104,
          child: Material(
            color: _inputFill,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickImage,
              child: hasImage
                  ? ProductThumbnail(
                      imagePath: _imagePath,
                      imageBytes: _imageBytes,
                      borderRadius: BorderRadius.circular(10),
                      iconSize: 26,
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 22,
                          color: AppColors.primary,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Add photo',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (hasImage) ...[
          const SizedBox(height: 4),
          // The preview is now the confirmation, so there's no filename
          // caption to read — just the two things you'd want to do next.
          SizedBox(
            width: 104,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _pickImage,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Replace'),
                ),
                _RowActionButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Remove photo',
                  hoverColor: AppColors.error,
                  onPressed: () => setState(() {
                    _imageBytes = null;
                    _imagePath = null;
                  }),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusField(BuildContext context) {
    // Archived is only offered on an existing archived product: it's a state
    // you restore *from*, not one you'd create a product into. Hiding it when
    // it doesn't apply keeps the common case to a two-way choice.
    final statuses = <ProductStatus>[
      ProductStatus.active,
      ProductStatus.draft,
      if (widget.product?.status == ProductStatus.archived)
        ProductStatus.archived,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel(text: 'Status'),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final status in statuses) ...[
              if (status != statuses.first) const SizedBox(width: 8),
              SelectableOptionButton(
                label: status.label,
                isSelected: _status == status,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                onTap: () => setState(() => _status = status),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Says what the choice actually does. Only Active stock reaches a
        // bazaar; both other states are held back, for different reasons.
        Text(
          switch (_status) {
            ProductStatus.active => 'Available to allocate to a bazaar.',
            ProductStatus.draft =>
              'Still being set up — cannot be allocated to a bazaar yet.',
            ProductStatus.archived =>
              'Out of circulation — cannot be allocated until set to Active.',
          },
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black45,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Widget _buildVariantToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sold in options',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  'Track stock per Color, Size, and the like (up to 2 groups).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _hasVariants,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            onChanged: (value) => setState(() {
              _hasVariants = value;
              _stockError = null;
            }),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- options step

  Widget _buildOptionsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'What varies between units of this product?',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        // Groups are told apart by a rule and their own heading rather than
        // by a tinted box each. A panel around fields that are already boxed
        // stacks two containers to say one thing, and on a step that is
        // nothing but fields it just adds visual weight.
        for (var i = 0; i < _variantCategories.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 20),
            const Divider(height: 1, color: _borderColor),
            const SizedBox(height: 20),
          ],
          _buildOptionGroup(context, i),
        ],
        if (_variantCategories.length < 2) ...[
          const SizedBox(height: 20),
          const Divider(height: 1, color: _borderColor),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _variantCategories.add(
                _VariantCategoryInput()..values.add(_VariantValueInput()),
              );
              _stepError = null;
            }),
            icon: const Icon(Icons.add_rounded, size: 17),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: _separatorColor),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            label: const Text('Add option group'),
          ),
        ],
        if (_stepError != null) ...[
          const SizedBox(height: 16),
          _StepErrorBanner(message: _stepError!),
        ],
      ],
    );
  }

  Widget _buildOptionGroup(BuildContext context, int index) {
    final category = _variantCategories[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _FieldLabel(text: 'Option group ${index + 1}'),
            const Spacer(),
            // Sits on the heading line rather than beside the name field, so
            // the field can run the full width and the icon lines up with the
            // per-value remove buttons underneath it.
            _RowActionButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove this option group',
              hoverColor: AppColors.error,
              onPressed: () => setState(() {
                _variantCategories.removeAt(index).dispose();
                _stepError = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: category.nameController,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          onChanged: (_) {
            if (_stepError != null) setState(() => _stepError = null);
          },
          decoration: _fieldDecoration(
            hint: index == 0 ? 'e.g. Color' : 'e.g. Size',
          ),
        ),
        const SizedBox(height: 16),
        // Naming the two columns once beats repeating "Value" and a cryptic
        // "+ 0" as placeholder text in every row.
        const Row(
          children: [
            Expanded(flex: 3, child: _FieldLabel(text: 'Value')),
            SizedBox(width: 8),
            Expanded(flex: 2, child: _FieldLabel(text: 'Extra price')),
            SizedBox(width: 2),
            SizedBox(width: _rowActionSize),
          ],
        ),
        const SizedBox(height: 6),
        for (var v = 0; v < category.values.length; v++) ...[
          if (v > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: category.values[v].valueController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (_) {
                    if (_stepError != null) setState(() => _stepError = null);
                  },
                  decoration: _fieldDecoration(
                    hint: index == 0 ? 'e.g. Black' : 'e.g. 42',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: category.values[v].extraPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: _fieldDecoration(hint: '0.00', prefixText: '+'),
                ),
              ),
              const SizedBox(width: 2),
              _RowActionButton(
                icon: Icons.close_rounded,
                tooltip: 'Remove value',
                hoverColor: AppColors.error,
                // A group with one value left can't lose it — an option
                // group with nothing in it isn't a thing.
                onPressed: category.values.length <= 1
                    ? null
                    : () =>
                          setState(() => category.values.removeAt(v).dispose()),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // Given a real button body at close to the fields' own height, so it
        // reads as a control in the same family rather than as a stray link
        // tucked under them. Left edge lines up with the Value column.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => category.values.add(_VariantValueInput())),
            icon: const Icon(Icons.add_rounded, size: 17),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: _inputFill,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            label: const Text('Add value'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ stock step

  Widget _buildStockStep(BuildContext context) {
    final single = _variantCategories.length == 1;
    final nameA = _variantCategories.isEmpty
        ? ''
        : _variantCategories[0].name.trim();
    final nameB = _variantCategories.length > 1
        ? _variantCategories[1].name.trim()
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          single
              ? 'How many of each ${nameA.isEmpty ? 'value' : nameA.toLowerCase()}?'
              : 'How many of each $nameA × $nameB?',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (single)
          ..._buildSingleGroupStock(context)
        else
          ..._buildPairedGroupStock(context),
        const SizedBox(height: 14),
        // A running total, so the number that lands in the table isn't a
        // surprise after adding a dozen boxes.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                'Total stock',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                formatCount(_totalComboStock()),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_stepError != null) ...[
          const SizedBox(height: 14),
          _StepErrorBanner(message: _stepError!),
        ],
      ],
    );
  }

  List<Widget> _buildSingleGroupStock(BuildContext context) {
    final values = _nonEmptyValues(_variantCategories[0]);
    return [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: _borderColor),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  values[i],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                width: 96,
                child: _buildStockBox(
                  ProductRepository.combinationValueKey(values[i]),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildPairedGroupStock(BuildContext context) {
    final valuesA = _nonEmptyValues(_variantCategories[0]);
    final valuesB = _nonEmptyValues(_variantCategories[1]);
    return [
      for (var i = 0; i < valuesA.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                valuesA[i],
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final valueB in valuesB)
                    SizedBox(
                      width: 104,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FieldLabel(text: valueB),
                          const SizedBox(height: 5),
                          _buildStockBox(
                            ProductRepository.combinationValueKey(
                              valuesA[i],
                              valueB,
                            ),
                            fillColor: AppColors.surface,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildStockBox(String key, {Color? fillColor}) {
    return TextField(
      controller: _comboController(key),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
      // Rebuilds so the running total stays in step with what's typed.
      onChanged: (_) => setState(() => _stepError = null),
      decoration: _fieldDecoration(hint: '0', fillColor: fillColor),
    );
  }

  // ----------------------------------------------------------------- footer

  Widget _buildFooter(BuildContext context) {
    final isLastStep = !_hasVariants || _step == _ProductStep.stock;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          if (_hasVariants && _step != _ProductStep.details)
            TextButton.icon(
              onPressed: _saving ? null : _goBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
                // Same metrics as Cancel — both are secondary text buttons,
                // and matching them keeps the footer from looking assembled
                // out of two different button systems.
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              label: const Text('Back'),
            ),
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(
                alpha: 0.45,
              ),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              // The dialog's one primary action, so it gets the widest target
              // here — and a fixed minimum so the label swapping between
              // "Continue" and "Save product" doesn't resize the footer.
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isLastStep ? 'Save product' : 'Continue'),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    String? hint,
    String? prefixText,
    bool hasError = false,
    Color? fillColor,
  }) {
    const radius = BorderRadius.all(Radius.circular(8));
    OutlineInputBorder border(Color color, double width) {
      return OutlineInputBorder(
        borderRadius: radius,
        borderSide: color == Colors.transparent
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      // Deliberately a prefix *icon*, not `prefixText`: InputDecorator fades
      // a real prefixText to opacity 0 until the field is focused or has
      // content, which hid the currency exactly when it was most useful —
      // on an empty field, before anything had been typed.
      prefixIcon: prefixText == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Text(
                prefixText,
                style: const TextStyle(color: Colors.black45, fontSize: 13.5),
              ),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      isDense: true,
      filled: true,
      fillColor: fillColor ?? _inputFill,
      contentPadding: EdgeInsets.fromLTRB(
        prefixText == null ? 12 : 0,
        12,
        12,
        12,
      ),
      // An invalid field carries a red outline so it's findable at a glance,
      // rather than relying on the message alone.
      border: border(hasError ? AppColors.error : Colors.transparent, 1),
      enabledBorder: border(hasError ? AppColors.error : Colors.transparent, 1),
      focusedBorder: border(
        hasError ? AppColors.error : AppColors.primary,
        1.5,
      ),
    );
  }
}

/// A field label, its input, and the error that belongs to it — kept in one
/// widget so a message can never drift away from the box it describes.
class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 6),
        child,
        // Grows in rather than appearing instantly, so a message never shoves
        // the rest of the form down in one jump.
        AnimatedSize(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          alignment: Alignment.topLeft,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontSize: 11.5,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Colors.black54,
        fontWeight: FontWeight.w600,
        fontSize: 11.5,
      ),
    );
  }
}

/// Error banner for problems that belong to a whole step rather than to one
/// input — the old form put these in a SnackBar at the bottom of the screen,
/// far from the dialog and gone in four seconds.
class _StepErrorBanner extends StatelessWidget {
  const _StepErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered marker in the product form's step indicator.
class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.number,
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = isDone || isCurrent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.small,
              curve: AppMotion.easeOut,
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : _borderColor,
                shape: BoxShape.circle,
              ),
              child: isDone
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : Colors.black38,
                      ),
                    ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: isActive ? AppColors.primary : Colors.black38,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row-order control for the master inventory toolbar.
///
/// A menu rather than four visible chips: the guidelines prefer chips for a
/// small option set, but that holds when the options are *toggles the user
/// scans*. These four are mutually exclusive states of one setting, only one
/// of which is ever true, and laying them out in a row next to the search bar
/// would spend the widest part of the toolbar restating three orders nobody
/// picked. A dropdown that names the current order is also the pattern every
/// other data table uses (Jakob's law).
///
/// It is *not* a cycling button like the bazaar status filter — that works for
/// three states you'd step through, but reaching the fourth option here would
/// take three taps with the label changing under the cursor each time.
///
/// Sized to the secondary-action tier and matched to the search field's
/// height, so the toolbar reads as one aligned band (Gestalt). Its width is
/// still content-sized — the tier rule this respects is "don't inflate a
/// secondary control's prominence", not "never align with a neighbour".
class _SortDropdown extends StatefulWidget {
  const _SortDropdown({required this.selected, required this.onSelected});

  final _InventorySort selected;
  final ValueChanged<_InventorySort> onSelected;

  @override
  State<_SortDropdown> createState() => _SortDropdownState();
}

class _SortDropdownState extends State<_SortDropdown> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_InventorySort>(
      tooltip: 'Sort products',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 240),
      initialValue: widget.selected,
      color: AppColors.surface,
      elevation: 3,
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _borderColor),
      ),
      onOpened: () => setState(() => _isOpen = true),
      onCanceled: () => setState(() => _isOpen = false),
      onSelected: (value) {
        setState(() => _isOpen = false);
        widget.onSelected(value);
      },
      itemBuilder: (context) => [
        for (final sort in _InventorySort.values) ...[
          // A rule between the two name orders and the two stock orders:
          // they answer different questions, and the break makes the menu
          // scannable as two pairs rather than one list of four.
          if (sort == _InventorySort.stockDesc)
            const PopupMenuDivider(height: 9),
          PopupMenuItem<_InventorySort>(
            value: sort,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: sort == widget.selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    sort.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: sort == widget.selected
                          ? AppColors.primary
                          : AppColors.text,
                      fontWeight: sort == widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: AnimatedContainer(
        duration: AppMotion.small,
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isOpen ? AppColors.primary : _borderColor,
            width: _isOpen ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 17,
              color: Colors.black45,
            ),
            const SizedBox(width: 8),
            // Names the active order instead of saying "Sort": the control
            // reports the table's current state rather than only its purpose.
            Text(
              widget.selected.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _isOpen ? 0.5 : 0,
              duration: AppMotion.small,
              curve: AppMotion.easeOut,
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

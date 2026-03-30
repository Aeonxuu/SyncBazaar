import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/dashboard/dashboard_cubit.dart';
import '../../../bloc/inventory/inventory_cubit.dart';
import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/bazaar_event.dart';
import '../../../models/product.dart';
import '../../../models/product_variant.dart';
import '../../../models/sale.dart';
import '../../../models/user.dart';
import '../../../data/repositories/product_repository.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/custom_card.dart';
import 'widgets/pos_product_card.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        if (state.selectedEvent == null) {
          return _eventSelector(context, state);
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(flex: 7, child: _productPanel(context, state)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _cartPanel(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _eventSelector(BuildContext context, PosState state) {
    final width = MediaQuery.sizeOf(context).width;
    final cardSize = width >= 1200 ? 320.0 : 280.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Active Bazaar',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: state.events.map((event) {
              final enabled = event.status == BazaarStatus.ongoing;
              final statusColor = event.status == BazaarStatus.ongoing
                  ? const Color(0xFF2E7D32)
                  : event.status == BazaarStatus.upcoming
                  ? const Color(0xFFB45309)
                  : AppColors.error;

              return Opacity(
                opacity: enabled ? 1 : 0.5,
                child: SizedBox(
                  width: cardSize,
                  child: CustomCard(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  event.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (user.isAdminOrOwner)
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.settings_outlined),
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _showEditEventDialog(
                                        context,
                                        state,
                                        event,
                                      );
                                      return;
                                    }
                                    final confirmed = await showConfirmationDialog(
                                      context: context,
                                      title: 'Delete Bazaar',
                                      message:
                                          'Are you sure you want to delete "${event.name}"?',
                                      confirmLabel: 'Delete',
                                    );
                                    if (confirmed != true || !context.mounted) {
                                      return;
                                    }
                                    await context
                                        .read<PosCubit>()
                                        .deleteEventFromPos(
                                          user: user,
                                          event: event,
                                        );
                                    if (context.mounted) {
                                      await context.read<DashboardCubit>().load(
                                        user,
                                      );
                                      await context
                                          .read<InventoryCubit>()
                                          .load();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Bazaar deleted successfully.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              event.status.name.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Start: ${_formatDate(event.startDate)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Finish: ${_formatDate(event.endDate)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary,
                                    Color.lerp(
                                      AppColors.primary,
                                      Colors.white,
                                      0.18,
                                    )!,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ElevatedButton(
                                onPressed: enabled
                                    ? () => context
                                          .read<PosCubit>()
                                          .selectEvent(event)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Open POS'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _productPanel(BuildContext context, PosState state) {
    final categories = state.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => context.read<PosCubit>().backToEventSelection(),
              icon: const Icon(Icons.arrow_back_rounded),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              label: const Text('Back to Bazaar Selection'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: categories
              .map(
                (c) => ChoiceChip(
                  label: Text(c),
                  selected: c == state.category,
                  onSelected: (_) => context.read<PosCubit>().selectCategory(c),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            itemCount: state.filteredProducts.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (context, i) {
              final product = state.filteredProducts[i];
              final inStock = product.stockQuantity > 0;
              return PosProductCard(
                product: product,
                subtitle:
                    'Category: ${state.categoryNames[product.categoryId] ?? 'Uncategorized'} • Stock: ${product.stockQuantity}',
                isEnabled: inStock,
                onTap: () => _showVariantPicker(context, product),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cartPanel(BuildContext context, PosState state) {
    final requiresEmployeeId = state.requiresEmployeeId;
    const subtleInputBg = Color(0xFFF5F1FB);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current order',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Customer name',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 6),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: subtleInputBg,
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
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: context.read<PosCubit>().updateCustomerName,
          ),
          const SizedBox(height: 8),
          Text(
            'Payment method',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: state.selectedPaymentMethod,
            items: state.paymentMethods
                .map(
                  (m) => DropdownMenuItem<String>(
                    value: m.name,
                    child: Text(m.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                context.read<PosCubit>().updatePaymentMethod(value);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: subtleInputBg,
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
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (requiresEmployeeId)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee ID',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.black45),
                ),
                const SizedBox(height: 6),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: subtleInputBg,
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
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: context.read<PosCubit>().updateEmployeeId,
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Discount',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _discountPill(context, state, 10),
              _discountPill(context, state, 20),
              _discountPill(context, state, 30),
              Text(
                'Selected: ${state.discountPercent}%',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: state.cart.length,
              itemBuilder: (context, i) {
                final item = state.cart[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.cartLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'PHP ${item.lineTotal.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => context
                                  .read<PosCubit>()
                                  .decrementCartItem(i),
                              icon: const Icon(Icons.remove_circle_outline),
                              visualDensity: VisualDensity.compact,
                            ),
                            Text('${item.quantity}'),
                            IconButton(
                              onPressed: () async {
                                final ok = await context
                                    .read<PosCubit>()
                                    .incrementCartItem(i);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cannot exceed available stock for this item.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              Text('Subtotal', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(
                'PHP ${state.subtotal.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Discount', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(
                '- PHP ${state.discountAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Total',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'PHP ${state.total.toStringAsFixed(2)}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: state.cart.isEmpty
                      ? null
                      : () => context.read<PosCubit>().cancelDraft(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: state.cart.isEmpty
                      ? null
                      : () async {
                          if (state.requiresEmployeeId &&
                              state.employeeId.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Employee ID is required for selected payment method.',
                                ),
                              ),
                            );
                            return;
                          }
                          final status = await _pickStatus(
                            context,
                            state.total,
                          );
                          if (status == null) return;
                          final sold = await context.read<PosCubit>().completeSale(
                            user: user,
                            status: status,
                          );
                          if (!sold && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Some items are out of stock. Please review cart quantities.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (context.mounted) {
                            await context.read<DashboardCubit>().load(user);
                            await context.read<OrdersCubit>().load();
                          }
                        },
                  child: const Text('Finish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _discountPill(BuildContext context, PosState state, int value) {
    final selected = state.discountPercent == value;
    return OutlinedButton(
      onPressed: () => context.read<PosCubit>().setDiscountPercent(value),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.black26,
          width: 1,
        ),
        foregroundColor: selected ? AppColors.primary : Colors.black87,
      ),
      child: Text('$value%'),
    );
  }

  Future<void> _showEditEventDialog(
    BuildContext context,
    PosState state,
    BazaarEvent event,
  ) async {
    final cubit = context.read<PosCubit>();
    final nameController = TextEditingController(text: event.name);
    DateTimeRange selectedRange = DateTimeRange(
      start: event.startDate,
      end: event.endDate,
    );
    final existingAllocations = await cubit.eventAllocations(event.id);
    final productRepository = context.read<ProductRepository>();
    final allocationItems = await productRepository.allocationItems();
    final allocations = <String, int>{};
    final maxByKey = <String, int>{};

    for (final item in allocationItems) {
      final allocated = existingAllocations[item.allocationKey] ?? 0;
      allocations[item.allocationKey] = allocated;
      maxByKey[item.allocationKey] = item.availableQuantity + allocated;
    }

    if (!context.mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Bazaar'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Bazaar Name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDateRange: selectedRange,
                          );
                          if (range != null) {
                            setState(() => selectedRange = range);
                          }
                        },
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          '${_formatDate(selectedRange.start)} - ${_formatDate(selectedRange.end)}',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Allocated Stocks',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...allocationItems.map((item) {
                        final allocated = allocations[item.allocationKey] ?? 0;
                        final maxQty = maxByKey[item.allocationKey] ?? 0;
                        final lineLabel = item.group == null || item.option == null
                            ? item.product.name
                            : '${item.product.name} / ${item.group!.name} ${item.option!.value}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lineLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: allocated <= 0
                                    ? null
                                    : () => setState(
                                        () => allocations[item.allocationKey] =
                                            allocated - 1,
                                      ),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('$allocated'),
                              IconButton(
                                onPressed: allocated >= maxQty
                                    ? null
                                    : () => setState(
                                        () => allocations[item.allocationKey] =
                                            allocated + 1,
                                      ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !context.mounted) {
      return;
    }

    final ok = await cubit.updateEventFromPos(
      user: user,
      event: event,
      name: nameController.text.trim().isEmpty
          ? event.name
          : nameController.text.trim(),
      startDate: selectedRange.start,
      endDate: selectedRange.end,
      newAllocations: allocations,
    );

    if (!context.mounted) {
      return;
    }

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to update bazaar. Check stock allocations and try again.',
          ),
        ),
      );
      return;
    }

    await context.read<DashboardCubit>().load(user);
    await context.read<InventoryCubit>().load();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bazaar updated successfully.')),
      );
    }
  }

  Future<OrderStatus?> _pickStatus(BuildContext context, double total) async {
    OrderStatus selected = OrderStatus.completed;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirm Sale',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total: PHP ${total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order status',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<OrderStatus>(
                          initialValue: selected,
                          items: OrderStatus.values
                              .map(
                                (s) => DropdownMenuItem<OrderStatus>(
                                  value: s,
                                  child: Text(s.name.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selected = value);
                            }
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            filled: true,
                            fillColor: const Color(0xFFF5F1FB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                              foregroundColor: const Color(0xFFC62828),
                              side: const BorderSide(color: Color(0xFFC62828)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            label: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            label: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (confirmed != true) {
      return null;
    }
    return selected;
  }

  Future<void> _showVariantPicker(BuildContext context, Product product) async {
    final cubit = context.read<PosCubit>();
    final group = await cubit.variantGroupForProduct(product.id);
    final options = await cubit.variantOptionsForProduct(product.id);
    final variantStocks = await cubit.variantStocksByOptionId(product.id);
    final nonVariantStock = await cubit.availableStock(
      productId: product.id,
      variantOptionId: null,
    );
    ProductVariantOption? selected;
    int quantity = 1;

    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final hasVariants = group != null && options.isNotEmpty;
            final cart = context.read<PosCubit>().state.cart;
            final selectedOptionId = selected?.id;
            final inCartQty = cart
                .where(
                  (item) =>
                      item.product.id == product.id &&
                      item.variantOptionId == (hasVariants ? selectedOptionId : null),
                )
                .fold<int>(0, (sum, item) => sum + item.quantity);
            final availableForSelection = hasVariants
                ? ((selectedOptionId == null ? 0 : (variantStocks[selectedOptionId] ?? 0)) - inCartQty)
                : (nonVariantStock - inCartQty);
            final maxSelectable = availableForSelection < 0 ? 0 : availableForSelection;
            if (quantity > maxSelectable && maxSelectable > 0) {
              quantity = maxSelectable;
            }
            final canAdd =
                quantity > 0 &&
                (!hasVariants || selected != null) &&
                maxSelectable > 0 &&
                quantity <= maxSelectable;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (hasVariants) ...[
                    Text(
                      'Select ${group.name}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: options
                          .map(
                            (option) => ChoiceChip(
                              label: Text(
                                '${option.value} (${variantStocks[option.id] ?? 0})',
                              ),
                              selected: selected?.id == option.id,
                              onSelected: (variantStocks[option.id] ?? 0) <= 0
                                  ? null
                                  : (_) {
                                setState(() {
                                  selected = option;
                                  quantity = 1;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!hasVariants)
                    Text(
                      'Available stock: ${maxSelectable < 0 ? 0 : maxSelectable}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                  if (hasVariants && selected != null)
                    Text(
                      'Available for ${selected!.value}: ${maxSelectable < 0 ? 0 : maxSelectable}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      IconButton(
                        onPressed: quantity <= 1
                            ? null
                            : () => setState(() => quantity -= 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '$quantity',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: quantity >= maxSelectable
                            ? null
                            : () => setState(() => quantity += 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      Text(
                        'PHP ${((product.basePrice + (selected?.extraPrice ?? 0)) * quantity).toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAdd
                          ? () async {
                              final added = await cubit.addToCart(
                                product,
                                variantGroup: group,
                                variantOption: selected,
                                quantity: quantity,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              if (!added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cannot add more than available stock.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(context);
                            }
                          : null,
                      child: const Text('Add to Cart'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

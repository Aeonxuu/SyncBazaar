import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/orders/orders_cubit.dart';
import '../../../bloc/pos/pos_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../models/order.dart';
import '../../../models/sale.dart';
import '../../../models/user.dart';
import '../../screens/dashboard/widgets/dashboard_section_card.dart';
import '../../widgets/confirmation_dialog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const _kCardShadow = [
    BoxShadow(
      color: Color(0x11000000),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersCubit>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, OrdersState>(
      builder: (context, state) {
        if (state.selectedEventId == null && widget.user.isAdminOrOwner) {
          return _bazaarSelector(context);
        }

        final orders = state.visibleOrders(widget.user);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Orders', style: Theme.of(context).textTheme.headlineSmall),
                  if (widget.user.isAdminOrOwner)
                    TextButton.icon(
                      onPressed: () => context.read<OrdersCubit>().filterByEvent(null),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Change Bazaar'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DashboardSectionCard(
                  title: 'Transaction History',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: state.paymentMethod,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('ALL')),
                            DropdownMenuItem(value: 'CASH', child: Text('CASH')),
                            DropdownMenuItem(value: 'COOP', child: Text('COOP')),
                            DropdownMenuItem(value: 'OTHER', child: Text('OTHER')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              context.read<OrdersCubit>().filterByPayment(value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          initialValue: state.status,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('ALL')),
                            DropdownMenuItem(
                              value: 'Completed',
                              child: Text('COMPLETED'),
                            ),
                            DropdownMenuItem(
                              value: 'Pending',
                              child: Text('PENDING'),
                            ),
                            DropdownMenuItem(
                              value: 'Incomplete',
                              child: Text('INCOMPLETE'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              context.read<OrdersCubit>().filterByStatus(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 420,
                        child: orders.isEmpty
                            ? _emptyOrders(context)
                            : ListView.builder(
                                itemCount: orders.length,
                                itemBuilder: (context, index) {
                                  final order = orders[index];
                                  return _orderRow(context, order, index);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bazaarSelector(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardSize = width >= 1200 ? 320.0 : 280.0;

    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(16),
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
                children: state.events.asMap().entries.map((entry) {
                  final index = entry.key;
                  final event = entry.value;
                  return SizedBox(
                    width: cardSize,
                    child: _AnimatedEntrance(
                      delayMs: 40 * (index % 8),
                      child: _InteractiveCard(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          context.read<OrdersCubit>().filterByEvent(event.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _kCardShadow,
                          ),
                          child: AspectRatio(
                            aspectRatio: 0.95,
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
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2ECFC),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.storefront_outlined,
                                        color: AppColors.primary,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1A2E7D32),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'ACTIVE BAZAAR',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFF2E7D32),
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const Spacer(),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2ECFC),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'View Orders',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.arrow_forward_rounded,
                                          color: AppColors.primary,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyOrders(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _kCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF2ECFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No orders found.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderRow(BuildContext context, Order order, int index) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final subStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AnimatedEntrance(
        delayMs: 28 * (index % 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _kCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  _statusBadge(context, order.orderStatus),
                ],
              ),
              const SizedBox(height: 6),
              Text(order.productLabel, style: textStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metaChip(context, 'Bazaar #${order.eventId}'),
                  _metaChip(context, order.paymentMethod),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 170, maxWidth: 220),
                    child: DropdownButtonFormField<OrderStatus>(
                      initialValue: order.orderStatus,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F1FB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: OrderStatus.values
                          .map(
                            (status) => DropdownMenuItem<OrderStatus>(
                              value: status,
                              child: Text(status.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (newStatus) async {
                        if (newStatus == null || newStatus == order.orderStatus) {
                          return;
                        }
                        final ok = await showConfirmationDialog(
                          context: context,
                          title: 'Confirm status change',
                          message: 'Are you sure?',
                        );
                        if (!ok || !context.mounted) return;
                        await context.read<OrdersCubit>().updateStatus(order.id, newStatus);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Update order status using the selector.',
                style: subStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2ECFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, OrderStatus status) {
    final (bg, fg) = switch (status) {
      OrderStatus.completed => (const Color(0x1A2E7D32), const Color(0xFF2E7D32)),
      OrderStatus.pending => (const Color(0x1AF59E0B), const Color(0xFFB45309)),
      OrderStatus.incomplete => (const Color(0x1AC62828), const Color(0xFFC62828)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({
    required this.child,
    required this.delayMs,
  });

  final Widget child;
  final int delayMs;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (!mounted) return;
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.06),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}

class _InteractiveCard extends StatefulWidget {
  const _InteractiveCard({
    required this.onTap,
    required this.child,
    required this.borderRadius,
  });

  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<_InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<_InteractiveCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.99 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: widget.child,
        ),
      ),
    );
  }
}

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
import '../../widgets/custom_card.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<OrdersCubit>().load());
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
                      _headerRow(context),
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      SizedBox(
                        height: 420,
                        child: orders.isEmpty
                            ? Center(
                                child: Text(
                                  'No orders found.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            : ListView.builder(
                                itemCount: orders.length,
                                itemBuilder: (context, index) {
                                  final order = orders[index];
                                  return _orderRow(context, order);
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
                children: state.events.map((event) {
                  return SizedBox(
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
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      context.read<OrdersCubit>().filterByEvent(event.id);
                                    },
                                    icon: const Icon(Icons.arrow_forward, size: 16),
                                    label: const Text('View Orders'),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Widget _headerRow(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Customer', style: style)),
        Expanded(flex: 2, child: Text('Bazaar', style: style)),
        Expanded(flex: 4, child: Text('Product', style: style)),
        Expanded(flex: 2, child: Text('Payment Methods', style: style)),
        Expanded(flex: 3, child: Text('Order Status', style: style)),
      ],
    );
  }

  Widget _orderRow(BuildContext context, Order order) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(order.customerName, style: textStyle)),
          Expanded(flex: 2, child: Text(order.eventId.toString(), style: textStyle)),
          Expanded(flex: 4, child: Text(order.productLabel, style: textStyle)),
          Expanded(flex: 2, child: Text(order.paymentMethod, style: textStyle)),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<OrderStatus>(
              initialValue: order.orderStatus,
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
    );
  }
}

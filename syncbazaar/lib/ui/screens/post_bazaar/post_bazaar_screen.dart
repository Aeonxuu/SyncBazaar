import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/orders_repository.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../models/order.dart';
import '../../../models/product.dart';
import '../../../models/sale.dart';
import '../../widgets/custom_card.dart';
import '../../widgets/confirmation_dialog.dart';

class PostBazaarScreen extends StatefulWidget {
  const PostBazaarScreen({super.key});

  @override
  State<PostBazaarScreen> createState() => _PostBazaarScreenState();
}

class _PostBazaarScreenState extends State<PostBazaarScreen> {
  late Future<_PostBazaarData> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _loadData();
  }

  Future<_PostBazaarData> _loadData() async {
    final salesRepository = context.read<SalesRepository>();
    final ordersRepository = context.read<OrdersRepository>();
    final productRepository = context.read<ProductRepository>();
    final eventRepository = context.read<EventRepository>();

    final sales = await salesRepository.listSales();
    final orders = await ordersRepository.listOrders();
    final products = await productRepository.listProducts();
    final events = await eventRepository.listAll();
    final eventNameById = {for (final event in events) event.id: event.name};
    return _PostBazaarData(
      sales: sales,
      orders: orders,
      products: products,
      eventNameById: eventNameById,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _futureData = _loadData();
    });
    await _futureData;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'SOA Draft'),
              Tab(text: 'List of Orders'),
              Tab(text: 'Inventory Reconciliation'),
            ],
          ),
          Expanded(
            child: FutureBuilder<_PostBazaarData>(
              future: _futureData,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: TabBarView(
                    children: [
                      _soaDraft(context, data),
                      _ordersExport(context, data),
                      _reconciliation(context, data),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _soaDraft(BuildContext context, _PostBazaarData data) {
    final grossSales = data.sales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    final incentive = grossSales * 0.10;
    final buffer = grossSales * 0.10;
    final net = grossSales - incentive - buffer;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gross sales: PHP ${grossSales.toStringAsFixed(2)}'),
              Text(
                'Incentive deduction (10%): PHP ${incentive.toStringAsFixed(2)}',
              ),
              Text('Buffer deduction (10%): PHP ${buffer.toStringAsFixed(2)}'),
              Text('Net amount: PHP ${net.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              Text(
                'Transactions captured: ${data.sales.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('SOA draft generated.')),
                      );
                    },
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Generate Draft SOA'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF export queued.')),
                      );
                    },
                    child: const Text('Export PDF'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV export queued.')),
                      );
                    },
                    child: const Text('Export CSV'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ordersExport(BuildContext context, _PostBazaarData data) {
    final ordersByEvent = <int, List<Order>>{};
    for (final order in data.orders) {
      ordersByEvent.putIfAbsent(order.eventId, () => []).add(order);
    }

    final cash = data.orders.where((o) => o.paymentMethod == 'CASH').length;
    final coop = data.orders.where((o) => o.paymentMethod == 'COOP').length;
    final other = data.orders.where((o) => o.paymentMethod == 'OTHER').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Order exports based on current transaction records'),
              const SizedBox(height: 8),
              Text('Total orders: ${data.orders.length}'),
              Text('CASH: $cash   COOP: $coop   OTHER: $other'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CASH list exported.')),
                      );
                    },
                    child: const Text('Export CASH list'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('COOP list exported.')),
                      );
                    },
                    child: const Text('Export COOP list'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('OTHER list exported.')),
                      );
                    },
                    child: const Text('Export Other list'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...ordersByEvent.entries.map((entry) {
          final eventId = entry.key;
          final orders = entry.value;
          final eventName = data.eventNameById[eventId] ?? 'Event #$eventId';
          final cashCount = orders.where((o) => o.paymentMethod == 'CASH').length;
          final coopCount = orders.where((o) => o.paymentMethod == 'COOP').length;
          final otherCount = orders.where((o) => o.paymentMethod == 'OTHER').length;
          final completedCount = orders.where((o) => o.orderStatus.name == 'completed').length;
          final pendingCount = orders.where((o) => o.orderStatus.name == 'pending').length;

          return CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Total orders: ${orders.length}'),
                Text('CASH: $cashCount • COOP: $coopCount • OTHER: $otherCount'),
                Text('Completed: $completedCount • Pending: $pendingCount'),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _reconciliation(BuildContext context, _PostBazaarData data) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current inventory after reservations and sales'),
              const SizedBox(height: 8),
              ...data.products.map(
                (product) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${product.name} / ${product.variant} / ${product.size}',
                  ),
                  subtitle: Text('Remaining stock: ${product.stockQuantity}'),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  final confirmed = await showConfirmationDialog(
                    context: context,
                    title: 'Finalize Bazaar',
                    message: 'Are you sure you want to finalize this bazaar? This action will close all ongoing transactions and cannot be undone.',
                  );
                  if (confirmed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bazaar finalized.')),
                    );
                  }
                },
                child: const Text('Finalize Bazaar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostBazaarData {
  const _PostBazaarData({
    required this.sales,
    required this.orders,
    required this.products,
    required this.eventNameById,
  });

  final List<Sale> sales;
  final List<Order> orders;
  final List<Product> products;
  final Map<int, String> eventNameById;
}

import '../../models/order.dart';
import '../../models/sale.dart';

class OrdersRepository {
  final List<Order> _orders = [
    Order(
      id: 1,
      saleId: 1,
      eventId: 1,
      customerName: 'Juan Dela Cruz',
      productLabel: 'Runner Pro / Black / 42',
      orderStatus: OrderStatus.pending,
      userId: 3,
      paymentMethod: 'COOP',
      updatedAt: DateTime.now(),
      synced: false,
    ),
  ];

  Future<List<Order>> listOrders() async => _orders;

  Future<void> addOrder(Order order) async => _orders.add(order);

  Future<void> updateOrderStatus(int orderId, OrderStatus status) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    _orders[idx] = _orders[idx].copyWith(orderStatus: status, synced: false);
  }

  Future<List<Order>> listUnsyncedOrders() async =>
      _orders.where((o) => !o.synced).toList();
}

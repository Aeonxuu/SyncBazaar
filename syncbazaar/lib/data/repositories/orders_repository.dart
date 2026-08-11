import '../../models/order.dart';

class OrdersRepository {
  final List<Order> _orders = [];

  Future<List<Order>> listOrders() async => _orders;

  Future<void> addOrder(Order order) async => _orders.add(order);

  Future<List<Order>> listUnsyncedOrders() async =>
      _orders.where((o) => !o.synced).toList();
}

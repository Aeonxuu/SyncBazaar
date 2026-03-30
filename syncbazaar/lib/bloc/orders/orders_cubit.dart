import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/order.dart';
import '../../models/sale.dart';
import '../../models/user.dart';

class OrdersState {
  const OrdersState({
    this.orders = const [],
    this.selectedEventId,
    this.paymentMethod = 'All',
    this.status = 'All',
  });

  final List<Order> orders;
  final int? selectedEventId;
  final String paymentMethod;
  final String status;

  List<Order> visibleOrders(AppUser user) {
    var result = orders;
    if (user.role == UserRole.employee) {
      result = result.where((o) => o.userId == user.id).toList();
    }
    if (selectedEventId != null) {
      result = result.where((o) => o.eventId == selectedEventId).toList();
    }
    if (paymentMethod != 'All') {
      result = result.where((o) => o.paymentMethod == paymentMethod).toList();
    }
    if (status != 'All') {
      result = result
          .where((o) => o.orderStatus.name == status.toLowerCase())
          .toList();
    }
    return result;
  }

  OrdersState copyWith({
    List<Order>? orders,
    int? selectedEventId,
    String? paymentMethod,
    String? status,
    bool clearEvent = false,
  }) {
    return OrdersState(
      orders: orders ?? this.orders,
      selectedEventId: clearEvent
          ? null
          : (selectedEventId ?? this.selectedEventId),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
    );
  }
}

class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit(this._ordersRepository, this._salesRepository)
      : super(const OrdersState());

  final OrdersRepository _ordersRepository;
  final SalesRepository _salesRepository;

  Future<void> load() async {
    emit(state.copyWith(orders: await _ordersRepository.listOrders()));
  }

  Future<void> updateStatus(int orderId, OrderStatus status) async {
    final order = await _ordersRepository.getOrderById(orderId);
    await _ordersRepository.updateOrderStatus(orderId, status);
    if (order != null) {
      await _salesRepository.updateSaleOrderStatus(order.saleId, status);
    }
    await load();
  }

  void filterByEvent(int? eventId) {
    emit(
      eventId == null
          ? state.copyWith(clearEvent: true)
          : state.copyWith(selectedEventId: eventId),
    );
  }

  void filterByPayment(String payment) =>
      emit(state.copyWith(paymentMethod: payment));
  void filterByStatus(String status) => emit(state.copyWith(status: status));
}

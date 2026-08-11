import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/user.dart';

/// A single completed transaction, joining an [Order]'s resolved product
/// label with its [Sale]'s financial figures — purely for display in the
/// read-only Transaction History table.
class TransactionRecord {
  const TransactionRecord({
    required this.orderId,
    required this.customerName,
    required this.timestamp,
    required this.productLabel,
    required this.unitPrice,
    required this.quantity,
    required this.total,
    required this.eventId,
    required this.paymentMethod,
    required this.userId,
  });

  final int orderId;
  final String customerName;
  final DateTime timestamp;
  final String productLabel;
  final double unitPrice;
  final int quantity;
  final double total;
  final int eventId;
  final String paymentMethod;
  final int userId;
}

class OrdersState {
  const OrdersState({
    this.records = const [],
    this.selectedEventId,
    this.paymentMethod = 'All',
  });

  final List<TransactionRecord> records;
  final int? selectedEventId;
  final String paymentMethod;

  List<TransactionRecord> visibleRecords(AppUser user) {
    var result = records;
    if (user.role == UserRole.employee) {
      result = result.where((r) => r.userId == user.id).toList();
    }
    if (selectedEventId != null) {
      result = result.where((r) => r.eventId == selectedEventId).toList();
    }
    if (paymentMethod != 'All') {
      result = result.where((r) => r.paymentMethod == paymentMethod).toList();
    }
    return result;
  }

  OrdersState copyWith({
    List<TransactionRecord>? records,
    int? selectedEventId,
    String? paymentMethod,
    bool clearEvent = false,
  }) {
    return OrdersState(
      records: records ?? this.records,
      selectedEventId: clearEvent
          ? null
          : (selectedEventId ?? this.selectedEventId),
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit(this._ordersRepository, this._salesRepository)
    : super(const OrdersState());

  final OrdersRepository _ordersRepository;
  final SalesRepository _salesRepository;

  Future<void> load() async {
    final orders = await _ordersRepository.listOrders();
    final sales = await _salesRepository.listSales();
    final saleById = {for (final sale in sales) sale.id: sale};

    final records = <TransactionRecord>[];
    for (final order in orders) {
      final sale = saleById[order.saleId];
      if (sale == null) {
        continue;
      }
      records.add(
        TransactionRecord(
          orderId: order.id,
          customerName: order.customerName,
          timestamp: sale.timestamp,
          productLabel: order.productLabel,
          unitPrice: sale.qty > 0 ? sale.total / sale.qty : sale.total,
          quantity: sale.qty,
          total: sale.total,
          eventId: order.eventId,
          paymentMethod: order.paymentMethod,
          userId: order.userId,
        ),
      );
    }
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    emit(state.copyWith(records: records));
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
}

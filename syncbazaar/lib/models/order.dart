import 'sale.dart';

class Order {
  const Order({
    required this.id,
    required this.saleId,
    required this.eventId,
    required this.customerName,
    required this.productLabel,
    required this.orderStatus,
    required this.userId,
    required this.paymentMethod,
    required this.updatedAt,
    required this.synced,
  });

  final int id;
  final int saleId;
  final int eventId;
  final String customerName;
  final String productLabel;
  final OrderStatus orderStatus;
  final int userId;
  final String paymentMethod;
  final DateTime updatedAt;
  final bool synced;

  Order copyWith({OrderStatus? orderStatus, bool? synced}) {
    return Order(
      id: id,
      saleId: saleId,
      eventId: eventId,
      customerName: customerName,
      productLabel: productLabel,
      orderStatus: orderStatus ?? this.orderStatus,
      userId: userId,
      paymentMethod: paymentMethod,
      updatedAt: DateTime.now(),
      synced: synced ?? this.synced,
    );
  }
}

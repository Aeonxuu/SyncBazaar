enum OrderStatus { completed, pending, incomplete }

class Sale {
  const Sale({
    required this.id,
    required this.eventId,
    required this.productId,
    this.variantOptionId,
    required this.customerName,
    required this.employeeId,
    required this.paymentMethod,
    required this.qty,
    required this.total,
    required this.timestamp,
    required this.orderStatus,
    required this.synced,
  });

  final int id;
  final int eventId;
  final int productId;
  final int? variantOptionId;
  final String customerName;
  final String employeeId;
  final String paymentMethod;
  final int qty;
  final double total;
  final DateTime timestamp;
  final OrderStatus orderStatus;
  final bool synced;
}

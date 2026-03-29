class EventInventory {
  const EventInventory({
    required this.id,
    required this.eventId,
    required this.productId,
    this.variantOptionId,
    required this.allocatedQuantity,
    required this.soldQuantity,
  });

  final int id;
  final int eventId;
  final int productId;
  final int? variantOptionId;
  final int allocatedQuantity;
  final int soldQuantity;

  int get remaining => allocatedQuantity - soldQuantity;
}

import '../../models/sale.dart';

/// Turns one bazaar's sales into the app's [Sale] records.
///
/// Two responses are needed, because the server splits what the client keeps
/// together: `sale/` carries the amount and the customer, `payment/` carries
/// how they paid. They are joined on the sale id here so nothing above this
/// has to know they were ever apart.
///
/// [allocationKeyForStockId] turns the `EventStock` row a sale points at back
/// into the product-and-options combination the app names things by — the same
/// bridge used to upload a sale, read the other way.
///
/// [paymentMethodNameById] resolves the payment's foreign key to the name the
/// receipt and the dashboard's payment mix both expect.
List<Sale> mapSalesResponse(
  List<dynamic> salesPayload, {
  required int eventId,
  required List<dynamic> paymentsPayload,
  required String? Function(int stockId) allocationKeyForStockId,
  required String Function(int methodId) paymentMethodNameById,
}) {
  final paymentsBySaleId = <int, Map<String, dynamic>>{};
  for (final entry in paymentsPayload) {
    final map = entry as Map<String, dynamic>;
    final saleId = (map['sale'] as num?)?.toInt();
    if (saleId != null) {
      paymentsBySaleId[saleId] = map;
    }
  }

  final sales = <Sale>[];
  for (final entry in salesPayload) {
    final map = entry as Map<String, dynamic>;
    final id = (map['id'] as num).toInt();

    final stockId = (map['event_stock'] as num?)?.toInt();
    final key = stockId == null ? null : allocationKeyForStockId(stockId);
    if (key == null) {
      // The sale points at stock this client cannot resolve — an archived
      // variant, or a product the vendor has since delisted. Skipped rather
      // than shown against the wrong shoe.
      continue;
    }
    final parts = key.split(':');
    final optionA = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final optionB = int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0;

    final payment = paymentsBySaleId[id];
    final methodId = (payment?['mode_of_payment'] as num?)?.toInt();

    sales.add(
      Sale(
        id: id,
        // Sales seeded or entered server-side have no client uuid. Derived
        // from the server id so it is still unique and still stable across
        // reloads — the field is an identity, and two records sharing an empty
        // string would look like the same sale.
        clientUuid: (map['client_uuid'] as String?) ?? 'server-$id',
        eventId: eventId,
        productId: int.tryParse(parts.first) ?? 0,
        variantOptionIdA: optionA == 0 ? null : optionA,
        variantOptionIdB: optionB == 0 ? null : optionB,
        customerName: normalizeCustomerName(map['customer_name'] as String?),
        soldById: (map['sold_by'] as num?)?.toInt() ?? 0,
        // Holds the reference a payment method asked for -- a GCash number,
        // say. Named employeeId for historical reasons; the POS fills it from
        // the payment's extra field.
        employeeId: (payment?['required_information'] as String?) ?? '',
        paymentMethod: methodId == null
            ? 'CASH'
            : paymentMethodNameById(methodId),
        qty: (map['quantity'] as num?)?.toInt() ?? 0,
        total: double.tryParse('${map['total']}') ?? 0,
        timestamp:
            DateTime.tryParse('${map['timestamp']}')?.toLocal() ??
            DateTime.now(),
        orderStatus: map['order_status'] == 'RT'
            ? OrderStatus.returned
            : OrderStatus.completed,
        // It came from the server, so by definition it is there.
        synced: true,
      ),
    );
  }
  return sales;
}

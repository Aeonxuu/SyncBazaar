import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/product_repository.dart';
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
  OrdersCubit(this._salesRepository, this._productRepository)
    : super(const OrdersState());

  final SalesRepository _salesRepository;
  final ProductRepository _productRepository;

  /// Builds the transaction history from sales.
  ///
  /// It used to be built from `Order` records, looking each one's sale up by
  /// id. Orders live only in this device's memory, so once sales started
  /// coming back from the server the history was empty on every launch: a
  /// bazaar with a day of takings behind it reported nothing sold.
  ///
  /// The sale is the record of what happened; an order carried the same facts
  /// again, plus a label.
  ///
  /// That label used to be preferred where an order was in memory, which meant
  /// the same shoe was spelled two ways in one list: "(Color Black, Size 42)"
  /// for a sale rung up since launch, "(Black, 42)" for one read back from the
  /// server. Every row is rebuilt from the catalogue now, so the history reads
  /// the same however old the sale is.
  Future<void> load() async {
    final sales = await _salesRepository.listSales();
    final labels = await _productLabels();

    final records = <TransactionRecord>[
      for (final sale in sales)
        TransactionRecord(
          orderId: sale.id,
          customerName: sale.customerName,
          timestamp: sale.timestamp,
          productLabel: labels.labelFor(
            productId: sale.productId,
            optionIdA: sale.variantOptionIdA,
            optionIdB: sale.variantOptionIdB,
          ),
          unitPrice: sale.qty > 0 ? sale.total / sale.qty : sale.total,
          quantity: sale.qty,
          total: sale.total,
          eventId: sale.eventId,
          paymentMethod: sale.paymentMethod,
          userId: sale.soldById,
        ),
    ];
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    emit(state.copyWith(records: records));
  }

  /// Product and option names, for rebuilding "what was sold" from a sale.
  Future<_ProductLabels> _productLabels() async {
    final products = await _productRepository.listProducts();
    final names = {for (final product in products) product.id: product.name};
    final options = <int, String>{};
    for (final product in products) {
      final groups = await _productRepository.variantGroupsForProduct(
        product.id,
      );
      final groupNames = {for (final group in groups) group.id: group.name};
      for (final option in await _productRepository.allVariantOptionsForProduct(
        product.id,
      )) {
        // Named with its category -- "Color Black", not "Black" -- which is
        // how the cart, the receipt and the exported order list all say it.
        final groupName = groupNames[option.variantGroupId];
        options[option.id] = groupName == null
            ? option.value
            : '$groupName ${option.value}';
      }
    }
    return _ProductLabels(names: names, optionValues: options);
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

/// Product and option names, so a sale can say what was sold.
class _ProductLabels {
  const _ProductLabels({required this.names, required this.optionValues});

  final Map<int, String> names;
  final Map<int, String> optionValues;

  /// "Nike Air Max SC (Color Black, Size 42)".
  ///
  /// Falls back to the product alone when an option is unknown -- an archived
  /// variant, say -- rather than printing a bare id at a cashier.
  String labelFor({required int productId, int? optionIdA, int? optionIdB}) {
    final name = names[productId] ?? 'Unknown product';
    final parts = [
      for (final id in [optionIdA, optionIdB])
        if (id != null && optionValues[id] != null) optionValues[id]!,
    ];
    return parts.isEmpty ? name : '$name (${parts.join(', ')})';
  }
}

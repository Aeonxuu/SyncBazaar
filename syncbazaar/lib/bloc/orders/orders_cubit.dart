import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/remote/api_client.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/refund.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../services/sale_upload_service.dart';

/// What a row of the history records.
///
/// A refund is its own row rather than a change to the sale it undoes: the sale
/// keeps its positive total and shows as returned, and the refund sits beside
/// it as money going out, so a column of totals adds up to the cash on hand.
enum TransactionKind { sale, refund }

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
    this.status = OrderStatus.completed,
    this.refund,
    this.serverSaleId,
    this.productName,
    this.variantDetail,
    this.stockLabel,
    this.kind = TransactionKind.sale,
    this.approvedByName,
    this.paymentReference = '',
  });

  /// The reference the sale was paid with: a GCash number, a bank slip. Empty
  /// for cash. Kept so a refund can be checked against it -- the money sent back
  /// has its own reference, and typing the original's again is a slip.
  final String paymentReference;

  /// Whether this row is a sale or the refund of one.
  final TransactionKind kind;

  bool get isRefund => kind == TransactionKind.refund;

  /// Whose password approved the refund. Only on a refund row.
  final String? approvedByName;

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

  /// Whether the sale was returned. A refunded sale always is; a sale can also
  /// be returned without a refund, by a return recorded on the server.
  final OrderStatus status;

  /// The refund issued for this sale, if any. One per sale: the server refuses
  /// a second.
  final Refund? refund;

  /// The product's own name, without its variant. Null when only the combined
  /// [productLabel] is known.
  final String? productName;

  /// The variant on its own line: colour values bare, the rest named, joined
  /// with a dot -- "Cloud White/Core Black/Gum · Size 38".
  final String? variantDetail;

  /// What goes back on the shelf, in a sentence: the product, then the parts
  /// that tell two of it apart besides colour -- "Adidas Samba OG, Size 38".
  final String? stockLabel;

  /// The server's id for the sale, which is what a refund addresses.
  ///
  /// Not [orderId]: for a sale rung up on this device that is a number made up
  /// from the clock, and the server has no sale by it. Null until the server
  /// has confirmed the sale.
  final int? serverSaleId;

  /// Whether the server holds this sale and knows its id.
  bool get onServer => serverSaleId != null;

  /// Where the refund button belongs on this row: only a sale the server holds
  /// that is neither returned nor already refunded can still be refunded.
  bool get isRefundable =>
      !isRefund && onServer && status != OrderStatus.returned && refund == null;
}

class OrdersState {
  const OrdersState({
    this.records = const [],
    this.selectedEventId,
    this.paymentMethod = 'All',
    this.isLoading = false,
    this.assignedEventIds,
  });

  /// The bazaars the server says the signed-in employee is assigned to, read
  /// when Orders last loaded. Null until it has been, or where there is no
  /// server to ask.
  ///
  /// Fresher than the ids captured at sign-in, which miss a bazaar the person
  /// was put on afterwards.
  final List<int>? assignedEventIds;

  /// True while sales are being fetched. An empty [records] cannot say whether
  /// nothing was sold or the answer has not arrived, and the table greeted
  /// everyone with "has not sold anything yet" for as long as the load took.
  final bool isLoading;

  final List<TransactionRecord> records;
  final int? selectedEventId;
  final String paymentMethod;

  /// The bazaars [user] is assigned to, as best known: the server's answer from
  /// the last load, else what sign-in recorded.
  List<int> assignedFor(AppUser user) =>
      assignedEventIds ?? user.assignedEventIdsEffective;

  /// The same user with the freshest assignments, for asking what they may do.
  AppUser withFreshAssignments(AppUser user) {
    final fresh = assignedEventIds;
    if (fresh == null || user.isAdminOrOwner) {
      return user;
    }
    return user.copyWith(assignedEventIds: fresh);
  }

  /// What [user] may see.
  ///
  /// An employee sees every sale at the bazaars they are assigned to, not just
  /// their own. Whoever is refunding a sale is rarely whoever rang it up -- the
  /// refund handler is a colleague -- and a till where the person who can
  /// approve a refund cannot see the sale is no use. Each row says who sold it,
  /// and the sale's `sold_by` is untouched, so per-employee figures still
  /// follow who actually made the sale.
  List<TransactionRecord> visibleRecords(AppUser user) {
    var result = records;
    if (user.role == UserRole.employee) {
      final assigned = assignedFor(user).toSet();
      result = result.where((r) => assigned.contains(r.eventId)).toList();
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
    bool? isLoading,
    List<int>? assignedEventIds,
  }) {
    return OrdersState(
      assignedEventIds: assignedEventIds ?? this.assignedEventIds,
      isLoading: isLoading ?? this.isLoading,
      records: records ?? this.records,
      selectedEventId: clearEvent
          ? null
          : (selectedEventId ?? this.selectedEventId),
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

class OrdersCubit extends Cubit<OrdersState> {
  /// [events] lets Orders ask the server which bazaars an employee is on, and
  /// [uploader] lets it send sales that are still waiting. Both are absent in
  /// the demo build and in tests that do not need them.
  OrdersCubit(
    this._salesRepository,
    this._productRepository, {
    EventRepository? events,
    SaleUploadService? uploader,
  }) : _events = events,
       _uploader = uploader,
       super(const OrdersState()) {
    // So the rows follow the data: a sale uploaded, a refund issued or a sync
    // finished while this screen is open shows at once, without leaving it.
    _changes = _salesRepository.changes.listen((_) => _reloadQuietly());
  }

  StreamSubscription<void>? _changes;
  bool _reloading = false;
  bool _dirty = false;

  @override
  Future<void> close() {
    _changes?.cancel();
    return super.close();
  }

  /// Rebuilds the rows after the data changed underneath them.
  ///
  /// Quiet: no loading state, since the rows on screen stay until the new ones
  /// replace them. Changes that arrive while a rebuild runs are folded into one
  /// more pass rather than each starting its own.
  Future<void> _reloadQuietly() async {
    // Nobody signed in means nothing of anybody's to show.
    if (isClosed || !(_events?.hasSession ?? true)) {
      return;
    }
    if (_reloading) {
      _dirty = true;
      return;
    }
    _reloading = true;
    try {
      do {
        _dirty = false;
        await _loadRecords();
      } while (_dirty && !isClosed);
    } catch (_) {
      // The rows on screen stay; the next change tries again.
    } finally {
      _reloading = false;
    }
  }

  final SalesRepository _salesRepository;
  final ProductRepository _productRepository;
  final EventRepository? _events;
  final SaleUploadService? _uploader;

  /// Back to nothing, for when somebody signs out. What Orders held belongs to
  /// the person who was signed in, including the bazaar they had picked.
  void reset() => emit(const OrdersState());

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
    emit(state.copyWith(isLoading: true));
    try {
      await _loadRecords();
    } catch (_) {
      emit(state.copyWith(isLoading: false));
      rethrow;
    }
    // After the rows are on screen, never before: sending can take as long as
    // the connection does, and the list should not wait on it.
    unawaited(_sendWaitingSales());
  }

  /// Sends sales that never made it, then shows them with the ids the server
  /// gave them.
  ///
  /// A sale is uploaded the moment it is rung, but that can fail -- most
  /// simply by signing out before it lands -- and nothing else retries it. Until
  /// it has reached the server it has no id the server knows, so it cannot be
  /// refunded, and the person looking at it has no way to tell why. Opening
  /// Orders is when they would notice, so it is when to try again.
  Future<void> _sendWaitingSales() async {
    final uploader = _uploader;
    // Not before anyone has signed in: this cubit loads at launch, and there is
    // no token to send anything with yet.
    if (uploader == null || !(_events?.hasSession ?? true)) {
      return;
    }
    try {
      final waiting = await _salesRepository.listUnsyncedSales();
      if (waiting.isEmpty) {
        return;
      }
      // The rows update themselves when the upload lands: it changes the
      // sales, and the repository says so.
      await uploader.uploadPending();
    } catch (_) {
      // Stays waiting, and is tried again next time.
    }
  }

  Future<void> _loadRecords() async {
    final assigned = await _freshAssignedEventIds();
    final sales = await _salesRepository.listSales();
    final refundByServerSaleId = {
      for (final refund in await _salesRepository.listRefunds())
        refund.saleId: refund,
    };
    final labels = await _productLabels();

    TransactionRecord recordFor(Sale sale) {
      final parts = labels.partsFor(
        productId: sale.productId,
        optionIdA: sale.variantOptionIdA,
        optionIdB: sale.variantOptionIdB,
      );
      return TransactionRecord(
        orderId: sale.id,
        customerName: sale.customerName,
        timestamp: sale.timestamp,
        productLabel: labels.labelFor(
          productId: sale.productId,
          optionIdA: sale.variantOptionIdA,
          optionIdB: sale.variantOptionIdB,
        ),
        productName: parts.name,
        variantDetail: parts.variantDetail,
        stockLabel: parts.stockLabel,
        unitPrice: sale.qty > 0 ? sale.total / sale.qty : sale.total,
        quantity: sale.qty,
        total: sale.total,
        eventId: sale.eventId,
        paymentMethod: sale.paymentMethod,
        userId: sale.soldById,
        status: sale.orderStatus,
        refund: sale.serverId == null
            ? null
            : refundByServerSaleId[sale.serverId],
        serverSaleId: sale.serverId,
        // Named `employeeId` on the model, which it has never held: the POS
        // writes the payment method's extra field into it.
        paymentReference: sale.employeeId,
      );
    }

    final saleByServerId = {
      for (final sale in sales)
        if (sale.serverId != null) sale.serverId!: sale,
    };

    TransactionRecord refundRecordFor(Refund refund) {
      // The sale it undoes, for what was sold and who sold it. A refund whose
      // sale is not among those loaded is still money that went out, so it is
      // shown rather than dropped.
      final sale = saleByServerId[refund.saleId];
      final parts = sale == null
          ? null
          : labels.partsFor(
              productId: sale.productId,
              optionIdA: sale.variantOptionIdA,
              optionIdB: sale.variantOptionIdB,
            );
      return TransactionRecord(
        kind: TransactionKind.refund,
        // Negative so it can never collide with a sale's id.
        orderId: -refund.id,
        customerName: refund.customerName.isNotEmpty
            ? refund.customerName
            : (sale?.customerName ?? kWalkInCustomer),
        timestamp: refund.createdAt,
        productLabel: sale == null
            ? 'Unknown product'
            : labels.labelFor(
                productId: sale.productId,
                optionIdA: sale.variantOptionIdA,
                optionIdB: sale.variantOptionIdB,
              ),
        productName: parts?.name,
        variantDetail: parts?.variantDetail,
        stockLabel: parts?.stockLabel,
        // Money out, so negative. The quantity stays positive: it is how many
        // came back, and a negative count would read as a different thing.
        unitPrice: -(sale != null && sale.qty > 0
            ? refund.amount / sale.qty
            : refund.amount),
        quantity: sale?.qty ?? 1,
        total: -refund.amount,
        eventId: refund.eventId,
        paymentMethod: refund.methodName.isNotEmpty
            ? refund.methodName
            : (sale?.paymentMethod ?? 'CASH'),
        // The seller's, not whoever tapped refund: an employee sees refunds of
        // sales at their bazaars the same as the sales themselves.
        userId: sale?.soldById ?? 0,
        status: OrderStatus.returned,
        refund: refund,
        approvedByName: refund.authorizedByName,
        serverSaleId: refund.saleId,
      );
    }

    final records = [
      for (final sale in sales) recordFor(sale),
      for (final refund in await _salesRepository.listRefunds())
        refundRecordFor(refund),
    ];
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    emit(
      state.copyWith(
        records: records,
        isLoading: false,
        assignedEventIds: assigned,
      ),
    );
  }

  /// The bazaars the server has the signed-in user on, or null to keep what was
  /// known. A failure here costs freshness, not the list.
  Future<List<int>?> _freshAssignedEventIds() async {
    try {
      return await _events?.fetchAssignedEventIds();
    } on ApiException {
      return null;
    }
  }

  /// Product and option names, for rebuilding "what was sold" from a sale.
  Future<_ProductLabels> _productLabels() async {
    final products = await _productRepository.listProducts();
    final names = {for (final product in products) product.id: product.name};
    final options = <int, String>{};
    final parts = <int, (String?, String)>{};
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
        parts[option.id] = (groupName, option.value);
      }
    }
    return _ProductLabels(
      names: names,
      optionValues: options,
      optionParts: parts,
    );
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
  const _ProductLabels({
    required this.names,
    required this.optionValues,
    this.optionParts = const {},
  });

  final Map<int, String> names;
  final Map<int, String> optionValues;

  /// Option id to its category and its value, for laying a variant out in
  /// pieces instead of as one string.
  final Map<int, (String?, String)> optionParts;

  /// A colour is recognisable on its own ("Cloud White"), so it goes without
  /// its category; "38" is not, so a size keeps its word.
  static bool _isColour(String? group) {
    final name = group?.trim().toLowerCase();
    return name == 'color' || name == 'colour';
  }

  /// The product and its variant, laid out for a dialog rather than a table.
  ({String name, String variantDetail, String stockLabel}) partsFor({
    required int productId,
    int? optionIdA,
    int? optionIdB,
  }) {
    final name = names[productId] ?? 'Unknown product';
    final detail = <String>[];
    final apart = <String>[];
    for (final id in [optionIdA, optionIdB]) {
      final part = id == null ? null : optionParts[id];
      if (part == null) {
        continue;
      }
      final (group, value) = part;
      if (_isColour(group) || group == null) {
        detail.add(value);
      } else {
        detail.add('$group $value');
        apart.add('$group $value');
      }
    }
    return (
      name: name,
      variantDetail: detail.join(' · '),
      stockLabel: [name, ...apart].join(', '),
    );
  }

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

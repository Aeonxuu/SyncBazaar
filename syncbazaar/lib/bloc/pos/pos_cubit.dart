import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/event_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/bazaar_event.dart';
import '../../models/company.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../models/receipt.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../services/receipt_payment_sections.dart';

class CartItem {
  CartItem({
    required this.product,
    required this.quantity,
    this.groupA,
    this.optionA,
    this.groupB,
    this.optionB,
  });

  final Product product;
  int quantity;
  final ProductVariantGroup? groupA;
  final ProductVariantOption? optionA;
  final ProductVariantGroup? groupB;
  final ProductVariantOption? optionB;

  double get unitPrice =>
      product.basePrice +
      (optionA?.extraPrice ?? 0) +
      (optionB?.extraPrice ?? 0);
  double get lineTotal => unitPrice * quantity;

  int? get variantOptionIdA => optionA?.id;
  int? get variantOptionIdB => optionB?.id;

  String get cartLabel {
    final parts = <String>[];
    if (groupA != null && optionA != null) {
      parts.add('${groupA!.name} ${optionA!.value}');
    }
    if (groupB != null && optionB != null) {
      parts.add('${groupB!.name} ${optionB!.value}');
    }
    if (parts.isEmpty) {
      return product.name;
    }
    return '${product.name} (${parts.join(', ')})';
  }
}

class PosState {
  const PosState({
    this.events = const [],
    this.selectedEvent,
    this.products = const [],
    this.cart = const [],
    this.paymentMethods = const [],
    this.selectedPaymentMethod = 'CASH',
    this.customerName = '',
    this.paymentExtraFieldValue = '',
    this.cashTendered = '',
  });

  final List<BazaarEvent> events;
  final BazaarEvent? selectedEvent;
  final List<Product> products;
  final List<CartItem> cart;
  final List<PaymentMethodMeta> paymentMethods;
  final String selectedPaymentMethod;
  final String customerName;
  final String paymentExtraFieldValue;

  /// Raw text of the "Cash received" field, kept as typed so a half-entered
  /// amount does not get rounded or reformatted under the cashier's cursor.
  final String cashTendered;

  double get subtotal => cart.fold(0, (sum, item) => sum + item.lineTotal);

  /// Equal to [subtotal] today. Kept as its own name because the checkout
  /// path, the receipt and the recorded sale all mean "what the customer
  /// pays", and the per-product discount that replaces the order-level one
  /// will land here rather than at every call site.
  double get total => subtotal;

  PaymentMethodMeta? get selectedPaymentMethodMeta {
    final selected = selectedPaymentMethod.trim().toUpperCase();
    return paymentMethods
        .where((m) => m.name.trim().toUpperCase() == selected)
        .cast<PaymentMethodMeta?>()
        .firstWhere((m) => m != null, orElse: () => null);
  }

  String? get selectedExtraFieldLabel {
    final label = selectedPaymentMethodMeta?.extraFieldLabel?.trim();
    if (label == null || label.isEmpty) {
      return null;
    }
    return label;
  }

  bool get requiresPaymentExtraField => selectedExtraFieldLabel != null;

  /// The receipt behaviour of the selected payment method.
  ///
  /// The POS asks this rather than testing for `'CASH'` itself, so a future
  /// method that also hands money back needs no change here.
  ReceiptPaymentSection get paymentSection =>
      ReceiptSectionRegistry.resolve(selectedPaymentMethod);

  bool get requiresCashTendered => paymentSection.requiresTendered;

  /// Null when the field is empty or not a number — i.e. not yet valid.
  double? get cashTenderedValue {
    final parsed = double.tryParse(cashTendered.trim());
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  /// Null until enough has been tendered to cover the total, so the UI can
  /// distinguish "not entered yet" from "short".
  double? get changeDue {
    final tendered = cashTenderedValue;
    if (tendered == null || tendered < total) {
      return null;
    }
    return tendered - total;
  }

  /// Whether checkout is allowed to proceed on the payment side.
  bool get cashTenderedIsSufficient {
    if (!requiresCashTendered) {
      return true;
    }
    final tendered = cashTenderedValue;
    return tendered != null && tendered >= total;
  }

  PosState copyWith({
    List<BazaarEvent>? events,
    BazaarEvent? selectedEvent,
    List<Product>? products,
    List<CartItem>? cart,
    List<PaymentMethodMeta>? paymentMethods,
    String? selectedPaymentMethod,
    String? customerName,
    String? paymentExtraFieldValue,
    String? cashTendered,
    bool clearSelectedEvent = false,
  }) {
    return PosState(
      events: events ?? this.events,
      selectedEvent: clearSelectedEvent
          ? null
          : (selectedEvent ?? this.selectedEvent),
      products: products ?? this.products,
      cart: cart ?? this.cart,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      selectedPaymentMethod:
          selectedPaymentMethod ?? this.selectedPaymentMethod,
      customerName: customerName ?? this.customerName,
      paymentExtraFieldValue:
          paymentExtraFieldValue ?? this.paymentExtraFieldValue,
      cashTendered: cashTendered ?? this.cashTendered,
    );
  }
}

class PosCubit extends Cubit<PosState> {
  PosCubit(
    this._eventRepository,
    this._productRepository,
    this._salesRepository,
    this._ordersRepository,
    this._settingsRepository,
  ) : super(const PosState());

  static const _uuid = Uuid();

  final EventRepository _eventRepository;
  final ProductRepository _productRepository;
  final SalesRepository _salesRepository;
  final OrdersRepository _ordersRepository;
  final SettingsRepository _settingsRepository;
  List<PaymentMethodMeta> _basePaymentMethods = const [];

  Future<void> load(AppUser user) async {
    final events = await _eventRepository.listVisibleForUser(user);
    final products = await _productRepository.listProducts();
    final globalMethods = await _settingsRepository.paymentMethods();
    _basePaymentMethods = globalMethods;
    final methods = _methodsForEvent(null, globalMethods);
    emit(
      state.copyWith(
        events: events,
        clearSelectedEvent: true,
        products: products,
        paymentMethods: methods,
        selectedPaymentMethod: methods.isEmpty ? 'CASH' : methods.first.name,
      ),
    );
  }

  Future<void> selectEvent(BazaarEvent event) async {
    final allProducts = await _productRepository.listProducts();
    final allocations = await _eventRepository
        .allocationsForEventByAllocationKey(event.id);

    final allocatedProductIds = allocations.entries
        .where((entry) => entry.value > 0)
        .map((entry) => int.tryParse(entry.key.split(':').first))
        .whereType<int>()
        .toSet();

    final allowedProducts = allocatedProductIds.isEmpty
        ? <Product>[]
        : allProducts
              .where((product) => allocatedProductIds.contains(product.id))
              .toList();

    final methods = _methodsForEvent(
      event,
      _basePaymentMethods.isEmpty ? state.paymentMethods : _basePaymentMethods,
    );
    emit(
      state.copyWith(
        selectedEvent: event,
        products: allowedProducts,
        paymentMethods: methods,
        selectedPaymentMethod: methods.isEmpty ? 'CASH' : methods.first.name,
      ),
    );
  }

  void backToEventSelection() {
    emit(state.copyWith(clearSelectedEvent: true, cart: const []));
  }

  // Switching method clears both per-method inputs: a reference number typed
  // for GCash means nothing once the customer decides to pay cash, and a
  // stale tendered amount would silently compute the wrong change.
  void updatePaymentMethod(String value) => emit(
    state.copyWith(
      selectedPaymentMethod: value,
      paymentExtraFieldValue: '',
      cashTendered: '',
    ),
  );
  void updateCustomerName(String value) =>
      emit(state.copyWith(customerName: value));
  void updatePaymentExtraFieldValue(String value) =>
      emit(state.copyWith(paymentExtraFieldValue: value));
  void updateCashTendered(String value) =>
      emit(state.copyWith(cashTendered: value));
  Future<int> availableStock({
    required int productId,
    int? optionIdA,
    int? optionIdB,
  }) {
    return _productRepository.combinationStock(
      productId: productId,
      optionIdA: optionIdA,
      optionIdB: optionIdB,
    );
  }

  Future<Map<(int?, int?), int>> combinationStocksForProduct(int productId) {
    return _productRepository.combinationStocksForProduct(productId);
  }

  int _reservedInCart({
    required int productId,
    int? optionIdA,
    int? optionIdB,
  }) {
    return state.cart
        .where(
          (item) =>
              item.product.id == productId &&
              item.variantOptionIdA == optionIdA &&
              item.variantOptionIdB == optionIdB,
        )
        .fold<int>(0, (sum, item) => sum + item.quantity);
  }

  Future<bool> addToCart(
    Product product, {
    ProductVariantGroup? groupA,
    ProductVariantOption? optionA,
    ProductVariantGroup? groupB,
    ProductVariantOption? optionB,
    int quantity = 1,
  }) async {
    final requested = quantity.clamp(1, 9999);
    final optionIdA = optionA?.id;
    final optionIdB = optionB?.id;
    final available = await availableStock(
      productId: product.id,
      optionIdA: optionIdA,
      optionIdB: optionIdB,
    );
    final alreadyInCart = _reservedInCart(
      productId: product.id,
      optionIdA: optionIdA,
      optionIdB: optionIdB,
    );
    if ((alreadyInCart + requested) > available) {
      return false;
    }

    final updated = [...state.cart];
    final idx = updated.indexWhere(
      (item) =>
          item.product.id == product.id &&
          item.variantOptionIdA == optionIdA &&
          item.variantOptionIdB == optionIdB,
    );

    if (idx == -1) {
      updated.add(
        CartItem(
          product: product,
          quantity: requested,
          groupA: groupA,
          optionA: optionA,
          groupB: groupB,
          optionB: optionB,
        ),
      );
    } else {
      updated[idx].quantity += requested;
    }
    emit(state.copyWith(cart: updated));
    return true;
  }

  Future<bool> incrementCartItem(int index) async {
    final updated = [...state.cart];
    if (index < 0 || index >= updated.length) return false;
    final item = updated[index];
    final available = await availableStock(
      productId: item.product.id,
      optionIdA: item.variantOptionIdA,
      optionIdB: item.variantOptionIdB,
    );
    final reserved = _reservedInCart(
      productId: item.product.id,
      optionIdA: item.variantOptionIdA,
      optionIdB: item.variantOptionIdB,
    );
    if ((reserved + 1) > available) {
      return false;
    }
    updated[index].quantity += 1;
    emit(state.copyWith(cart: updated));
    return true;
  }

  void decrementCartItem(int index) {
    final updated = [...state.cart];
    if (index < 0 || index >= updated.length) return;
    if (updated[index].quantity <= 1) {
      updated.removeAt(index);
    } else {
      updated[index].quantity -= 1;
    }
    emit(state.copyWith(cart: updated));
  }

  void cancelDraft() {
    emit(
      state.copyWith(
        cart: const [],
        customerName: '',
        paymentExtraFieldValue: '',
        cashTendered: '',
        selectedPaymentMethod: state.paymentMethods.isEmpty
            ? 'CASH'
            : state.paymentMethods.first.name,
      ),
    );
  }

  Future<Map<String, int>> eventAllocations(int eventId) {
    return _eventRepository.allocationsForEventByAllocationKey(eventId);
  }

  Future<bool> updateEventFromPos({
    required AppUser user,
    required BazaarEvent event,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, int> newAllocations,
  }) async {
    final existing = await _eventRepository.allocationsForEventByAllocationKey(
      event.id,
    );
    final allKeys = {...existing.keys, ...newAllocations.keys};
    final stockDeltas = <String, int>{};
    for (final key in allKeys) {
      final oldQty = existing[key] ?? 0;
      final newQty = newAllocations[key] ?? 0;
      final delta = oldQty - newQty;
      if (delta != 0) {
        stockDeltas[key] = delta;
      }
    }

    final adjusted = await _productRepository.adjustStocksByAllocationKey(
      stockDeltas,
    );
    if (!adjusted) {
      return false;
    }

    await _eventRepository.updateEvent(
      eventId: event.id,
      name: name,
      startDate: startDate,
      endDate: endDate,
      allocationsByAllocationKey: newAllocations,
    );
    await load(user);
    return true;
  }

  Future<void> deleteEventFromPos({
    required AppUser user,
    required BazaarEvent event,
  }) async {
    final existing = await _eventRepository.allocationsForEventByAllocationKey(
      event.id,
    );
    final release = <String, int>{
      for (final e in existing.entries) e.key: e.value,
    };
    await _productRepository.adjustStocksByAllocationKey(release);
    await _eventRepository.deleteEvent(event.id);
    await load(user);
  }

  Future<List<ProductVariantGroup>> variantGroupsForProduct(int productId) {
    return _productRepository.variantGroupsForProduct(productId);
  }

  Future<List<ProductVariantOption>> variantOptionsForGroup(int groupId) {
    return _productRepository.variantOptionsForGroup(groupId);
  }

  /// Commits the sale and returns the receipt for it, or null if it could not
  /// be committed.
  ///
  /// Returns [ReceiptData] rather than a bool because the receipt can only be
  /// assembled from the cart, and the cart is cleared as the last act of this
  /// method. The persisted `Sale` rows are no substitute: one row per line
  /// item, sharing no basket id, storing no unit price and no product name.
  /// So the receipt is snapshotted here, at the one moment all of it is known.
  Future<ReceiptData?> completeSale({required AppUser user}) async {
    const status = OrderStatus.completed;
    final event = state.selectedEvent;
    if (event == null || state.cart.isEmpty) {
      return null;
    }

    final subtotal = state.subtotal;
    final ratio = subtotal <= 0 ? 1.0 : state.total / subtotal;
    final soldAt = DateTime.now();

    for (final item in state.cart) {
      final deducted = await _productRepository.reserveForSale(
        productId: item.product.id,
        optionIdA: item.variantOptionIdA,
        optionIdB: item.variantOptionIdB,
        quantity: item.quantity,
      );
      if (!deducted) {
        return null;
      }

      final sale = Sale(
        id: DateTime.now().millisecondsSinceEpoch + item.product.id,
        // One uuid per cart line, minted here at the moment of sale rather than
        // when the sale is uploaded. The server dedupes on it, so a batch that
        // reaches it but whose reply is lost can be re-sent safely — which is
        // the normal case on bazaar wifi, not the exceptional one.
        //
        // Per line rather than per basket because the server's Sale is one
        // stock row plus a quantity, so each line has to dedupe on its own.
        clientUuid: _uuid.v4(),
        eventId: event.id,
        productId: item.product.id,
        variantOptionIdA: item.variantOptionIdA,
        variantOptionIdB: item.variantOptionIdB,
        customerName: normalizeCustomerName(state.customerName),
        employeeId: state.paymentExtraFieldValue,
        paymentMethod: state.selectedPaymentMethod,
        qty: item.quantity,
        total: item.lineTotal * ratio,
        timestamp: DateTime.now(),
        orderStatus: status,
        synced: false,
      );
      await _salesRepository.addSale(sale);

      await _ordersRepository.addOrder(
        Order(
          id: DateTime.now().microsecondsSinceEpoch,
          saleId: sale.id,
          eventId: event.id,
          customerName: sale.customerName,
          productLabel: item.cartLabel,
          orderStatus: status,
          userId: user.id,
          paymentMethod: sale.paymentMethod,
          updatedAt: DateTime.now(),
          synced: false,
        ),
      );
    }

    // Built before the emit below, which clears the cart it reads from.
    final receipt = await _buildReceipt(user: user, event: event, at: soldAt);

    emit(
      state.copyWith(
        cart: const [],
        customerName: '',
        paymentExtraFieldValue: '',
        cashTendered: '',
        selectedPaymentMethod: state.paymentMethods.isEmpty
            ? 'CASH'
            : state.paymentMethods.first.name,
      ),
    );
    return receipt;
  }

  Future<ReceiptData> _buildReceipt({
    required AppUser user,
    required BazaarEvent event,
    required DateTime at,
  }) async {
    final storeName = await _settingsRepository.storeName();

    // The venue hosting the bazaar. Absent from the receipt rather than fatal
    // to it if the event points at a company that no longer exists.
    final companies = await _settingsRepository.listCompanies();
    final venue = companies
        .where((company) => company.id == event.companyId)
        .cast<Company?>()
        .firstWhere((company) => company != null, orElse: () => null);

    final section = state.paymentSection;
    final paymentContext = ReceiptPaymentContext(
      total: state.total,
      paymentMethod: state.selectedPaymentMethod,
      extraFieldLabel: state.selectedExtraFieldLabel,
      extraFieldValue: state.paymentExtraFieldValue,
      cashTendered: section.requiresTendered ? state.cashTenderedValue : null,
    );

    return ReceiptData(
      storeName: storeName,
      venueName: venue?.name ?? '',
      venueAddress: venue?.address ?? '',
      venueContact: venue?.contact ?? '',
      eventName: event.name,
      receiptNo: _receiptNo(at),
      cashierName: user.name,
      customerName: normalizeCustomerName(state.customerName),
      paymentMethod: state.selectedPaymentMethod,
      timestamp: at,
      lines: [
        for (final item in state.cart)
          ReceiptLine(
            name: item.product.name,
            variantLabel: _variantLabel(item),
            qty: item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: item.lineTotal,
          ),
      ],
      subtotal: state.subtotal,
      total: state.total,
      paymentDetails: section.details(paymentContext),
      footerNote: section.footerNote(paymentContext),
    );
  }

  /// `SB-260810-144233` — readable at a glance and sorts chronologically,
  /// unlike the epoch-millisecond ids the `Sale` rows carry.
  static String _receiptNo(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'SB-${two(at.year % 100)}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }

  /// "Color Black, Size 42" — the variant part of [CartItem.cartLabel], without
  /// the product name the receipt already prints on its own line.
  static String _variantLabel(CartItem item) {
    final parts = <String>[];
    if (item.groupA != null && item.optionA != null) {
      parts.add('${item.groupA!.name} ${item.optionA!.value}');
    }
    if (item.groupB != null && item.optionB != null) {
      parts.add('${item.groupB!.name} ${item.optionB!.value}');
    }
    return parts.join(', ');
  }

  List<PaymentMethodMeta> _methodsForEvent(
    BazaarEvent? event,
    List<PaymentMethodMeta> baseMethods,
  ) {
    if (event == null) {
      return baseMethods;
    }

    final result = <PaymentMethodMeta>[];
    final customByName = {
      for (final method in event.customOtherMethods)
        method.name.trim().toUpperCase(): method,
    };
    final acceptedSet = event.acceptedPaymentMethods
        .map((item) => item.trim().toUpperCase())
        .toSet();

    for (final method in baseMethods) {
      if (acceptedSet.contains(method.name.trim().toUpperCase())) {
        final custom = customByName[method.name.trim().toUpperCase()];
        result.add(
          PaymentMethodMeta(
            name: method.name,
            extraFieldLabel: custom?.extraFieldLabel ?? method.extraFieldLabel,
          ),
        );
      }
    }

    for (final custom in event.customOtherMethods) {
      final upper = custom.name.trim().toUpperCase();
      if (acceptedSet.contains(upper) &&
          !result.any((method) => method.name.trim().toUpperCase() == upper)) {
        result.add(
          PaymentMethodMeta(
            name: custom.name,
            extraFieldLabel: custom.extraFieldLabel,
          ),
        );
      }
    }

    if (result.isEmpty) {
      return const [PaymentMethodMeta(name: 'CASH')];
    }

    return result;
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/event_repository.dart';
import '../../data/repositories/orders_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/bazaar_event.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../models/sale.dart';
import '../../models/user.dart';

class CartItem {
  CartItem({
    required this.product,
    required this.quantity,
    this.variantGroup,
    this.variantOption,
  });

  final Product product;
  int quantity;
  final ProductVariantGroup? variantGroup;
  final ProductVariantOption? variantOption;

  double get unitPrice => product.basePrice + (variantOption?.extraPrice ?? 0);
  double get lineTotal => unitPrice * quantity;

  int? get variantOptionId => variantOption?.id;

  String get cartLabel {
    if (variantGroup == null || variantOption == null) {
      return product.name;
    }
    return '${product.name} (${variantGroup!.name} ${variantOption!.value})';
  }
}

class PosState {
  const PosState({
    this.events = const [],
    this.selectedEvent,
    this.products = const [],
    this.filteredProducts = const [],
    this.cart = const [],
    this.paymentMethods = const [],
    this.selectedPaymentMethod = 'CASH',
    this.customerName = '',
    this.employeeId = '',
    this.quantity = 1,
    this.discountPercent = 0,
    this.category = 'All',
    this.categoryNames = const {},
  });

  final List<BazaarEvent> events;
  final BazaarEvent? selectedEvent;
  final List<Product> products;
  final List<Product> filteredProducts;
  final List<CartItem> cart;
  final List<PaymentMethodMeta> paymentMethods;
  final String selectedPaymentMethod;
  final String customerName;
  final String employeeId;
  final int quantity;
  final int discountPercent;
  final String category;
  final Map<int, String> categoryNames;

  List<String> get categories {
    final values = {'All', ...categoryNames.values};
    return values.toList();
  }

  double get subtotal => cart.fold(0, (sum, item) => sum + item.lineTotal);
  double get discountAmount => subtotal * (discountPercent / 100);
  double get total => subtotal - discountAmount;

  bool get requiresEmployeeId {
    final selected = selectedPaymentMethod.trim().toUpperCase();
    final method = paymentMethods
        .where((m) => m.name.trim().toUpperCase() == selected)
        .cast<PaymentMethodMeta?>()
        .firstWhere((m) => m != null, orElse: () => null);
    return method?.requiresEmployeeId ?? false;
  }

  PosState copyWith({
    List<BazaarEvent>? events,
    BazaarEvent? selectedEvent,
    List<Product>? products,
    List<Product>? filteredProducts,
    List<CartItem>? cart,
    List<PaymentMethodMeta>? paymentMethods,
    String? selectedPaymentMethod,
    String? customerName,
    String? employeeId,
    int? quantity,
    int? discountPercent,
    String? category,
    Map<int, String>? categoryNames,
    bool clearSelectedEvent = false,
  }) {
    return PosState(
      events: events ?? this.events,
      selectedEvent: clearSelectedEvent
          ? null
          : (selectedEvent ?? this.selectedEvent),
      products: products ?? this.products,
      filteredProducts: filteredProducts ?? this.filteredProducts,
      cart: cart ?? this.cart,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      selectedPaymentMethod:
          selectedPaymentMethod ?? this.selectedPaymentMethod,
      customerName: customerName ?? this.customerName,
      employeeId: employeeId ?? this.employeeId,
      quantity: quantity ?? this.quantity,
      discountPercent: discountPercent ?? this.discountPercent,
      category: category ?? this.category,
      categoryNames: categoryNames ?? this.categoryNames,
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

  final EventRepository _eventRepository;
  final ProductRepository _productRepository;
  final SalesRepository _salesRepository;
  final OrdersRepository _ordersRepository;
  final SettingsRepository _settingsRepository;
  List<PaymentMethodMeta> _basePaymentMethods = const [];

  Future<void> load(AppUser user) async {
    final events = await _eventRepository.listVisibleForUser(user);
    final products = await _productRepository.listProducts();
    final categories = await _productRepository.listCategories();
    final globalMethods = await _settingsRepository.paymentMethods();
    _basePaymentMethods = globalMethods;
    final methods = _methodsForEvent(null, globalMethods);
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    emit(
      state.copyWith(
        events: events,
        clearSelectedEvent: true,
        products: products,
        filteredProducts: products,
        paymentMethods: methods,
        selectedPaymentMethod: methods.isEmpty ? 'CASH' : methods.first.name,
        categoryNames: categoryNames,
      ),
    );
  }

  Future<void> selectEvent(BazaarEvent event) async {
    final allProducts = await _productRepository.listProducts();
    final allCategories = await _productRepository.listCategories();
    final allocations = await _eventRepository.allocationsForEventByAllocationKey(
      event.id,
    );

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

    final allowedCategoryIds = allowedProducts
        .map((product) => product.categoryId)
        .toSet();
    final categoryNames = {
      for (final category in allCategories)
        if (allowedCategoryIds.contains(category.id)) category.id: category.name,
    };

    final methods = _methodsForEvent(
      event,
      _basePaymentMethods.isEmpty ? state.paymentMethods : _basePaymentMethods,
    );
    emit(
      state.copyWith(
        selectedEvent: event,
        products: allowedProducts,
        filteredProducts: allowedProducts,
        category: 'All',
        categoryNames: categoryNames,
        paymentMethods: methods,
        selectedPaymentMethod: methods.isEmpty ? 'CASH' : methods.first.name,
      ),
    );
  }

  void backToEventSelection() {
    emit(state.copyWith(clearSelectedEvent: true, cart: const [], quantity: 1));
  }

  void selectCategory(String category) {
    if (category == 'All') {
      emit(
        state.copyWith(category: category, filteredProducts: state.products),
      );
      return;
    }

    final categoryId = state.categoryNames.entries
        .where((entry) => entry.value == category)
        .cast<MapEntry<int, String>?>()
        .firstWhere((entry) => entry != null, orElse: () => null)
        ?.key;
    if (categoryId == null) {
      return;
    }

    emit(
      state.copyWith(
        category: category,
        filteredProducts: state.products
            .where((p) => p.categoryId == categoryId)
            .toList(),
      ),
    );
  }

  void updatePaymentMethod(String value) =>
      emit(state.copyWith(selectedPaymentMethod: value));
  void updateCustomerName(String value) =>
      emit(state.copyWith(customerName: value));
  void updateEmployeeId(String value) =>
      emit(state.copyWith(employeeId: value));
  void setQuantity(int value) =>
      emit(state.copyWith(quantity: value.clamp(1, 99)));

  void setDiscountPercent(int value) {
    emit(state.copyWith(discountPercent: value.clamp(0, 100)));
  }

  Future<int> availableStock({
    required int productId,
    required int? variantOptionId,
  }) {
    return _productRepository.availableStock(
      productId: productId,
      variantOptionId: variantOptionId,
    );
  }

  Future<Map<int, int>> variantStocksByOptionId(int productId) {
    return _productRepository.variantStocksByOptionId(productId);
  }

  int _reservedInCart({required int productId, required int? variantOptionId}) {
    return state.cart
        .where(
          (item) =>
              item.product.id == productId && item.variantOptionId == variantOptionId,
        )
        .fold<int>(0, (sum, item) => sum + item.quantity);
  }

  Future<bool> addToCart(
    Product product, {
    ProductVariantGroup? variantGroup,
    ProductVariantOption? variantOption,
    int quantity = 1,
  }) async {
    final requested = quantity.clamp(1, 9999);
    final variantOptionId = variantOption?.id;
    final available = await availableStock(
      productId: product.id,
      variantOptionId: variantOptionId,
    );
    final alreadyInCart = _reservedInCart(
      productId: product.id,
      variantOptionId: variantOptionId,
    );
    if ((alreadyInCart + requested) > available) {
      return false;
    }

    final updated = [...state.cart];
    final idx = updated.indexWhere(
      (item) =>
          item.product.id == product.id &&
          item.variantOptionId == variantOptionId,
    );

    if (idx == -1) {
      updated.add(
        CartItem(
          product: product,
          quantity: requested,
          variantGroup: variantGroup,
          variantOption: variantOption,
        ),
      );
    } else {
      updated[idx].quantity += requested;
    }
    emit(state.copyWith(cart: updated, quantity: 1));
    return true;
  }

  Future<bool> incrementCartItem(int index) async {
    final updated = [...state.cart];
    if (index < 0 || index >= updated.length) return false;
    final item = updated[index];
    final available = await availableStock(
      productId: item.product.id,
      variantOptionId: item.variantOptionId,
    );
    final reserved = _reservedInCart(
      productId: item.product.id,
      variantOptionId: item.variantOptionId,
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
        employeeId: '',
        quantity: 1,
        discountPercent: 0,
        selectedPaymentMethod:
            state.paymentMethods.isEmpty ? 'CASH' : state.paymentMethods.first.name,
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

  Future<ProductVariantGroup?> variantGroupForProduct(int productId) {
    return _productRepository.variantGroupForProduct(productId);
  }

  Future<List<ProductVariantOption>> variantOptionsForProduct(int productId) {
    return _productRepository.variantOptionsForProduct(productId);
  }

  Future<bool> completeSale({
    required AppUser user,
    required OrderStatus status,
  }) async {
    final event = state.selectedEvent;
    if (event == null || state.cart.isEmpty) {
      return false;
    }

    final subtotal = state.subtotal;
    final ratio = subtotal <= 0 ? 1.0 : state.total / subtotal;

    for (final item in state.cart) {
      final deducted = await _productRepository.reserveForSale(
        productId: item.product.id,
        variantOptionId: item.variantOptionId,
        quantity: item.quantity,
      );
      if (!deducted) {
        return false;
      }

      final sale = Sale(
        id: DateTime.now().millisecondsSinceEpoch + item.product.id,
        eventId: event.id,
        productId: item.product.id,
        variantOptionId: item.variantOptionId,
        customerName: state.customerName.isEmpty
            ? 'Walk-in'
            : state.customerName,
        employeeId: state.employeeId,
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

    emit(
      state.copyWith(
        cart: const [],
        customerName: '',
        employeeId: '',
        discountPercent: 0,
        selectedPaymentMethod:
            state.paymentMethods.isEmpty ? 'CASH' : state.paymentMethods.first.name,
      ),
    );
    return true;
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
            requiresEmployeeId: custom?.requiresEmployeeId ?? method.requiresEmployeeId,
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
            requiresEmployeeId: custom.requiresEmployeeId,
          ),
        );
      }
    }

    if (result.isEmpty) {
      return const [
        PaymentMethodMeta(name: 'CASH'),
      ];
    }

    return result;
  }
}

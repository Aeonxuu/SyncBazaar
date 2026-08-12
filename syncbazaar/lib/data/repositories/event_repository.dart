import '../../models/bazaar_event.dart';
import '../../models/user.dart';
import '../remote/event_api_mapper.dart';
import 'auth_repository.dart';
import 'product_repository.dart';

class EventRepository {
  /// Backed by the vendor's bazaars when [auth] is supplied.
  ///
  /// [products] is required alongside it, not optional: the server allocates
  /// stock against variant ids, and only the catalogue knows which combination
  /// each one stands for. Follows [ProductRepository] in reading the session at
  /// first use rather than at construction, since `app.dart` builds every
  /// repository before anyone has signed in.
  ///
  /// Reads only. Creating, editing, finalizing and clearing allocations still
  /// happen in memory and do not reach the server yet.
  EventRepository({AuthRepository? auth, ProductRepository? products})
    : _auth = auth,
      _products = products;

  final AuthRepository? _auth;
  final ProductRepository? _products;

  int? _loadedVendorId;
  Future<void>? _load;

  final List<BazaarEvent> _events = [];
  final Map<int, Map<String, int>> _allocationsByEventId = {};

  BazaarStatus _statusFor(DateTime startDate, DateTime endDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Compared date-to-date. A bazaar runs for whole days, but its bounds are
    // plain DateTimes that may carry a time: a start of "today 2:30pm" is
    // after midnight-today, so an event opening this morning was reported as
    // still upcoming until tomorrow. Truncating both sides makes the answer
    // depend on the date the user picked and nothing else.
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (end.isBefore(today)) {
      return BazaarStatus.ended;
    }
    if (start.isAfter(today)) {
      return BazaarStatus.upcoming;
    }
    return BazaarStatus.ongoing;
  }

  void _refreshStatuses() {
    for (var i = 0; i < _events.length; i++) {
      final event = _events[i];
      final nextStatus = _statusFor(event.startDate, event.endDate);
      if (event.status == nextStatus) {
        continue;
      }
      _events[i] = BazaarEvent(
        id: event.id,
        name: event.name,
        companyId: event.companyId,
        startDate: event.startDate,
        endDate: event.endDate,
        status: nextStatus,
        acceptedPaymentMethods: event.acceptedPaymentMethods,
        customOtherMethods: event.customOtherMethods,
      );
    }
  }

  /// Fetches the vendor's bazaars and their allocations once signed in.
  ///
  /// Returns immediately without a session, so the mock-seeded and test paths
  /// keep their in-memory behaviour.
  Future<void> _ensureLoaded() async {
    final auth = _auth;
    final products = _products;
    final vendorId = auth?.vendorId;
    if (auth == null ||
        products == null ||
        vendorId == null ||
        _loadedVendorId == vendorId) {
      return;
    }

    final existing = _load;
    if (existing != null) {
      await existing;
      return;
    }
    final load = _loadFromApi(auth, products).then((_) {
      _loadedVendorId = vendorId;
    });
    _load = load.whenComplete(() => _load = null);
    await _load;
  }

  Future<void> _loadFromApi(
    AuthRepository auth,
    ProductRepository products,
  ) async {
    // The catalogue first: an allocation is a variant id until the products are
    // loaded, and a variant id means nothing on its own.
    await products.ensureLoaded();

    final methods = await _paymentMethods(auth);
    final payload = await auth.api.get('/api/bazaar/event/') as List;
    final events = mapEventsResponse(
      payload,
      statusFor: _statusFor,
      fallbackMethods: methods.$1,
      fallbackCustomMethods: methods.$2,
    );

    _events
      ..clear()
      ..addAll(events);

    _allocationsByEventId.clear();
    for (final event in events) {
      final stock =
          await auth.api.get('/api/bazaar/event/${event.id}/stock/') as List;
      _allocationsByEventId[event.id] = mapEventStockResponse(
        stock,
        allocationKeyForVariant: products.allocationKeyForVariant,
      );
    }
  }

  /// The vendor-wide payment methods, standing in for per-venue ones.
  ///
  /// Which methods a bazaar accepts belongs to its `Establishment`, whose
  /// endpoint currently 500s, so this falls back to the global list. Failing
  /// soft rather than throwing: a wrong payment menu is recoverable, an event
  /// list that will not load is not.
  Future<(List<String>, List<BazaarPaymentMethod>)> _paymentMethods(
    AuthRepository auth,
  ) async {
    try {
      final payload = await auth.api.get('/api/core/mode-of-payment/') as List;
      final names = <String>[];
      final custom = <BazaarPaymentMethod>[];
      for (final entry in payload) {
        final map = entry as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';
        if (name.isEmpty) {
          continue;
        }
        names.add(name.toUpperCase());
        final label = map['required_information_name'] as String?;
        if (label != null && label.trim().isNotEmpty) {
          custom.add(
            BazaarPaymentMethod(name: name.toUpperCase(), extraFieldLabel: label),
          );
        }
      }
      return (names.isEmpty ? const ['CASH'] : names, custom);
    } on Object {
      return (const ['CASH'], const <BazaarPaymentMethod>[]);
    }
  }

  /// Re-fetches bazaars and allocations, discarding what is held now.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoaded();
  }

  Future<List<BazaarEvent>> listAll() async {
    await _ensureLoaded();
    _refreshStatuses();
    return _events;
  }

  Future<BazaarEvent> createEvent({
    required String name,
    required int companyId,
    required DateTime startDate,
    required DateTime endDate,
    List<String> acceptedPaymentMethods = const ['CASH'],
    List<BazaarPaymentMethod> customOtherMethods = const [],
    Map<String, int> allocationsByAllocationKey = const {},
  }) async {
    final nextId = _events.isEmpty
        ? 1
        : _events.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
    final eventStatus = _statusFor(startDate, endDate);

    final event = BazaarEvent(
      id: nextId,
      name: name,
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
      status: eventStatus,
      acceptedPaymentMethods: acceptedPaymentMethods,
      customOtherMethods: customOtherMethods,
    );
    _events.add(event);
    _allocationsByEventId[nextId] = Map<String, int>.from(
      allocationsByAllocationKey,
    );
    return event;
  }

  Future<List<BazaarEvent>> listVisibleForUser(AppUser user) async {
    await _ensureLoaded();
    _refreshStatuses();
    if (user.isAdminOrOwner) {
      return _events;
    }
    final assignedEventIds = user.assignedEventIdsEffective.toSet();
    return _events.where((e) => assignedEventIds.contains(e.id)).toList();
  }

  Future<void> finalizeEvent(int eventId) async {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
    final event = _events[idx];
    _events[idx] = BazaarEvent(
      id: event.id,
      name: event.name,
      companyId: event.companyId,
      startDate: event.startDate,
      endDate: event.endDate,
      status: BazaarStatus.ended,
      acceptedPaymentMethods: event.acceptedPaymentMethods,
      customOtherMethods: event.customOtherMethods,
    );
  }

  Future<void> clearAllocationsForEvent(int eventId) async {
    _allocationsByEventId.remove(eventId);
  }

  Future<Map<String, int>> allocationsForEventByAllocationKey(
    int eventId,
  ) async {
    await _ensureLoaded();
    return Map<String, int>.from(_allocationsByEventId[eventId] ?? const {});
  }

  /// Takes [quantity] out of what this bazaar has left of one combination.
  ///
  /// This is what a sale spends. Stock moves out of the master inventory when
  /// it is allocated to a bazaar — the shoes are physically at the stall — so
  /// selling one must come off the bazaar's own pile, not the warehouse's. The
  /// POS used to deduct from the master inventory instead, which both showed a
  /// cashier stock that was not at their table and counted every sale against
  /// the warehouse a second time.
  ///
  /// Returns false and changes nothing when the bazaar does not have that many
  /// left, so a caller can refuse the sale rather than drive the figure
  /// negative.
  Future<bool> consumeAllocation({
    required int eventId,
    required String allocationKey,
    required int quantity,
  }) async {
    await _ensureLoaded();
    if (quantity <= 0) {
      return false;
    }
    final allocations = _allocationsByEventId[eventId];
    final remaining = allocations?[allocationKey] ?? 0;
    if (allocations == null || remaining < quantity) {
      return false;
    }
    allocations[allocationKey] = remaining - quantity;
    return true;
  }

  /// Puts [quantity] back, for a sale that could not be completed.
  Future<void> restoreAllocation({
    required int eventId,
    required String allocationKey,
    required int quantity,
  }) async {
    await _ensureLoaded();
    final allocations = _allocationsByEventId[eventId];
    if (allocations == null || quantity <= 0) {
      return;
    }
    allocations[allocationKey] = (allocations[allocationKey] ?? 0) + quantity;
  }

  Future<void> updateEvent({
    required int eventId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? acceptedPaymentMethods,
    List<BazaarPaymentMethod>? customOtherMethods,
    Map<String, int>? allocationsByAllocationKey,
  }) async {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
    final previous = _events[idx];
    _events[idx] = BazaarEvent(
      id: previous.id,
      name: name,
      companyId: previous.companyId,
      startDate: startDate,
      endDate: endDate,
      status: _statusFor(startDate, endDate),
      acceptedPaymentMethods:
          acceptedPaymentMethods ?? previous.acceptedPaymentMethods,
      customOtherMethods: customOtherMethods ?? previous.customOtherMethods,
    );
    if (allocationsByAllocationKey != null) {
      _allocationsByEventId[eventId] = Map<String, int>.from(
        allocationsByAllocationKey,
      );
    }
  }

  Future<void> deleteEvent(int eventId) async {
    _events.removeWhere((e) => e.id == eventId);
    _allocationsByEventId.remove(eventId);
  }
}

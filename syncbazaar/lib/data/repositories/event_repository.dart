import '../../models/bazaar_event.dart';
import '../../models/user.dart';

class EventRepository {
  final List<BazaarEvent> _events = [
    BazaarEvent(
      id: 1,
      name: 'March Campus Bazaar',
      companyId: 1,
      startDate: DateTime(2026, 3, 25),
      endDate: DateTime(2026, 3, 31),
      status: BazaarStatus.ongoing,
      acceptedPaymentMethods: ['CASH', 'COOP', 'GCASH'],
      customOtherMethods: [
        const BazaarPaymentMethod(name: 'GCASH', requiresEmployeeId: false),
      ],
    ),
    BazaarEvent(
      id: 2,
      name: 'April Trade Fair',
      companyId: 1,
      startDate: DateTime(2026, 4, 5),
      endDate: DateTime(2026, 4, 8),
      status: BazaarStatus.upcoming,
      acceptedPaymentMethods: ['CASH', 'COOP'],
    ),
  ];
  final Map<int, Map<String, int>> _allocationsByEventId = {};

  BazaarStatus _statusFor(DateTime startDate, DateTime endDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (endDate.isBefore(today)) {
      return BazaarStatus.ended;
    }
    if (startDate.isAfter(today)) {
      return BazaarStatus.upcoming;
    }
    return BazaarStatus.ongoing;
  }

  Future<List<BazaarEvent>> listAll() async => _events;

  Future<BazaarEvent> createEvent({
    required String name,
    required int companyId,
    required DateTime startDate,
    required DateTime endDate,
    List<String> acceptedPaymentMethods = const ['CASH', 'COOP'],
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

  Future<Map<String, int>> allocationsForEventByAllocationKey(int eventId) async {
    return Map<String, int>.from(_allocationsByEventId[eventId] ?? const {});
  }

  Future<Map<int, int>> allocationsForEvent(int eventId) async {
    final source = _allocationsByEventId[eventId] ?? const {};
    final byProduct = <int, int>{};
    for (final entry in source.entries) {
      final productId = int.tryParse(entry.key.split(':').first);
      if (productId == null) {
        continue;
      }
      byProduct[productId] = (byProduct[productId] ?? 0) + entry.value;
    }
    return byProduct;
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

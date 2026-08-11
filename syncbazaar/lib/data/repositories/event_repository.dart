import '../../models/bazaar_event.dart';
import '../../models/user.dart';

class EventRepository {
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

  Future<List<BazaarEvent>> listAll() async {
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
    return Map<String, int>.from(_allocationsByEventId[eventId] ?? const {});
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

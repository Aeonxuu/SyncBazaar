import '../../models/bazaar_event.dart';
import '../../models/user.dart';

class EventRepository {
  final List<BazaarEvent> _events = [
    BazaarEvent(
      id: 1,
      name: 'Pasayahan Festival',
      companyId: 4,
      startDate: DateTime(2026, 5, 15),
      endDate: DateTime(2026, 5, 22),
      status: BazaarStatus.upcoming,
      acceptedPaymentMethods: ['CASH', 'GCASH'],
      customOtherMethods: [
        const BazaarPaymentMethod(name: 'GCASH', extraFieldLabel: 'Reference Number'),
      ],
    ),
    BazaarEvent(
      id: 2,
      name: 'MSEUF Festival',
      companyId: 3,
      startDate: DateTime(2026, 4, 14),
      endDate: DateTime(2026, 4, 17),
      status: BazaarStatus.upcoming,
      acceptedPaymentMethods: ['CASH'],
    ),
  ];
  final Map<int, Map<String, int>> _allocationsByEventId = {
    1: {
      '1:9000': 6,
      '1:9001': 6,
      '4:9014': 6,
      '4:9016': 6,
      '7:9032': 5,
      '7:9033': 5,
      '10:9044': 5,
      '10:9046': 5,
      '13:9056': 6,
      '13:9058': 6,
      '2:9005': 5,
      '2:9007': 5,
      '5:9021': 5,
      '5:9023': 5,
      '8:9036': 4,
      '8:9038': 4,
      '11:9048': 4,
      '11:9050': 4,
      '14:9061': 4,
      '14:9063': 4,
    },
    2: {
      '3:9010': 5,
      '3:9012': 5,
      '6:9027': 5,
      '6:9029': 5,
      '9:9040': 5,
      '9:9042': 5,
      '12:9053': 5,
      '12:9055': 5,
      '15:9065': 5,
      '15:9067': 5,
      '1:9002': 5,
      '1:9003': 5,
      '4:9015': 5,
      '4:9017': 5,
    },
  };

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

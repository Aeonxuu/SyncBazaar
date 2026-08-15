import '../../models/bazaar_event.dart';
import '../../models/user.dart';
import '../remote/api_client.dart';
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
  /// Creating, editing, deleting and finalizing a bazaar all reach the server,
  /// as do its stock allocations.
  EventRepository({AuthRepository? auth, ProductRepository? products})
    : _auth = auth,
      _products = products;

  final AuthRepository? _auth;
  final ProductRepository? _products;

  int? _loadedVendorId;
  Future<void>? _load;

  final List<BazaarEvent> _events = [];
  final Map<int, Map<String, int>> _allocationsByEventId = {};

  /// Event id, then combination, to the server's `EventStock` row id.
  ///
  /// What a sale upload sends. The server records a sale against the stock row,
  /// not against a product or a variant: the same shoe allocated to two
  /// bazaars is two rows with two counts, and only the row says which stall's
  /// pile the sale came out of.
  ///
  /// Empty in the in-memory and mock-seeded paths, where no such row exists.
  final Map<int, Map<String, int>> _stockIdsByEventId = {};

  int? stockIdFor({required int eventId, required String allocationKey}) =>
      _stockIdsByEventId[eventId]?[allocationKey];

  /// The same mapping read backwards, for sales arriving from the server.
  ///
  /// A sale names the stock row it came out of; the app names things by
  /// combination. Uploading needs one direction, reading history needs the
  /// other.
  String? allocationKeyForStockId({
    required int eventId,
    required int stockId,
  }) {
    final rows = _stockIdsByEventId[eventId];
    if (rows == null) {
      return null;
    }
    for (final entry in rows.entries) {
      if (entry.value == stockId) {
        return entry.key;
      }
    }
    return null;
  }

  /// The bazaars this vendor has, for callers that need to sweep all of them.
  Future<List<BazaarEvent>> loadedEvents() async {
    await _ensureLoaded();
    return List<BazaarEvent>.unmodifiable(_events);
  }

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

  /// Orders bazaars the way someone standing at a till would look for them.
  ///
  /// The API returns them by creation, which buries the bazaar being sold at
  /// today among ones that finished months ago. Ongoing come first, then
  /// upcoming, then ended — so the one the app is actually for is the one at
  /// the top of the screen.
  ///
  /// Within each group the order follows what the reader wants next: an
  /// ongoing bazaar closing soonest, the next upcoming one to prepare for, and
  /// the most recently finished, since older history matters less the further
  /// back it goes.
  ///
  /// Sorted here rather than in the two screens that show the grid, which
  /// would be two orderings to keep in step.
  List<BazaarEvent> _sortedForDisplay(List<BazaarEvent> events) {
    const rank = {
      BazaarStatus.ongoing: 0,
      BazaarStatus.upcoming: 1,
      BazaarStatus.ended: 2,
    };
    final sorted = [...events];
    sorted.sort((a, b) {
      final byStatus = rank[a.status]!.compareTo(rank[b.status]!);
      if (byStatus != 0) {
        return byStatus;
      }
      return switch (a.status) {
        BazaarStatus.ongoing => a.endDate.compareTo(b.endDate),
        BazaarStatus.upcoming => a.startDate.compareTo(b.startDate),
        BazaarStatus.ended => b.endDate.compareTo(a.endDate),
      };
    });
    return sorted;
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

  /// Bazaars the server holds but has not approved, from the last load.
  ///
  /// These are employees' proposals. Nothing else keeps them -- they are
  /// filtered out of [_events] on the way in, precisely so they cannot be sold
  /// against -- but the approvals list has to find the requests attached to
  /// them, and the API offers approvals only per event. Without this it would
  /// have to ask every bazaar the vendor has ever run.
  final Set<int> _proposalEventIds = <int>{};

  Future<Set<int>> proposalEventIds() async {
    await _ensureLoaded();
    return Set<int>.unmodifiable(_proposalEventIds);
  }

  /// Called when a proposal is decided, so the next approvals load does not
  /// ask about a bazaar that is now either real or gone.
  void forgetProposal(int eventId) => _proposalEventIds.remove(eventId);

  void rememberProposal(int eventId) => _proposalEventIds.add(eventId);

  Future<void> _loadFromApi(
    AuthRepository auth,
    ProductRepository products,
  ) async {
    // The catalogue first: an allocation is a variant id until the products are
    // loaded, and a variant id means nothing on its own.
    await products.ensureLoaded();

    final methods = await _paymentMethods(auth);
    final payload = await auth.api.get('/api/bazaar/event/') as List;
    _proposalEventIds
      ..clear()
      ..addAll(
        payload
            .cast<Map<String, dynamic>>()
            .where((map) => map['is_approved'] == false)
            .map((map) => (map['id'] as num).toInt()),
      );
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
    _stockIdsByEventId.clear();
    for (final event in events) {
      final stock =
          await auth.api.get('/api/bazaar/event/${event.id}/stock/') as List;
      final stockIds = <String, int>{};
      _allocationsByEventId[event.id] = mapEventStockResponse(
        stock,
        allocationKeyForVariant: products.allocationKeyForVariant,
        stockIdByAllocationKey: stockIds,
      );
      _stockIdsByEventId[event.id] = stockIds;
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
            BazaarPaymentMethod(
              name: name.toUpperCase(),
              extraFieldLabel: label,
            ),
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
    return _sortedForDisplay(_events);
  }

  Future<BazaarEvent> createEvent({
    required String name,
    required int companyId,
    required DateTime startDate,
    required DateTime endDate,
    List<String> acceptedPaymentMethods = const ['CASH'],
    List<BazaarPaymentMethod> customOtherMethods = const [],
    Map<String, int> allocationsByAllocationKey = const {},
    bool isApproved = true,
  }) async {
    await _ensureLoaded();

    // Created on the server first, so the bazaar carries the id the server
    // assigned. Inventing one locally and reconciling later would mean the
    // allocations, and every sale rung against them, pointing at a bazaar that
    // does not exist anywhere else.
    final serverId = await _createEventOnServer(
      name: name,
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
      allocationsByAllocationKey: allocationsByAllocationKey,
      isApproved: isApproved,
    );

    final id = serverId ?? _nextLocalEventId();
    final event = BazaarEvent(
      id: id,
      name: name,
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
      status: _statusFor(startDate, endDate),
      acceptedPaymentMethods: acceptedPaymentMethods,
      customOtherMethods: customOtherMethods,
    );
    // An unapproved bazaar is a proposal waiting on an owner, not something
    // to sell against. It exists on the server only so the approval request
    // has an event to hang off, and is deliberately not added here: the till,
    // the sales list and the dashboard all read this collection.
    if (isApproved) {
      _events.add(event);
      _allocationsByEventId[id] = Map<String, int>.from(
        allocationsByAllocationKey,
      );
    } else {
      _proposalEventIds.add(id);
    }
    return event;
  }

  int _nextLocalEventId() => _events.isEmpty
      ? 1
      : _events.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;

  /// Creates the bazaar and its stock allocations, returning the server's id.
  ///
  /// Null without a session, which is the in-memory build.
  ///
  /// Throws on failure rather than falling back to a local-only bazaar: a
  /// bazaar that exists on one tablet and nowhere else is worse than none at
  /// all, because staff will allocate stock to it and sell against it before
  /// anyone notices. The caller reports the failure and the user tries again.
  Future<int?> _createEventOnServer({
    required String name,
    required int companyId,
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, int> allocationsByAllocationKey,
    bool isApproved = true,
  }) async {
    final auth = _auth;
    final products = _products;
    final vendorId = auth?.vendorId;
    if (auth == null || products == null || vendorId == null) {
      return null;
    }

    final created =
        await auth.api.post(
              '/api/bazaar/event/',
              body: {
                'name': name,
                'establishment': companyId,
                // Required even though the view sets it from the signed-in
                // user's vendor; the serializer declares it without
                // read_only.
                'vendor': vendorId,
                'address': await _addressForEstablishment(auth, companyId),
                'start_date': startDate.toUtc().toIso8601String(),
                'end_date': endDate.toUtc().toIso8601String(),
                // An owner creating a bazaar directly has nobody to ask, so
                // it is approved on the spot. A proposal from an employee is
                // not: it exists to give the approval request an event to
                // belong to, and stays out of every listing until decided.
                'is_approved': isApproved,
              },
            )
            as Map<String, dynamic>;

    final eventId = (created['id'] as num).toInt();

    // Stock is committed when the proposal is approved, not when it is made.
    // Reserving it here would let an employee whose request is never answered
    // hold inventory that nobody can sell.
    if (!isApproved) {
      return eventId;
    }

    final stockIds = <String, int>{};
    for (final entry in allocationsByAllocationKey.entries) {
      if (entry.value <= 0) {
        continue;
      }
      final variantId = products.variantIdFor(entry.key);
      if (variantId == null) {
        // A combination the catalogue does not know. Skipped rather than
        // guessed: there is no variant to allocate against.
        continue;
      }
      final row =
          await auth.api.post(
                '/api/bazaar/event/$eventId/stock/',
                body: {
                  'event': eventId,
                  'variant': variantId,
                  'amount_allocated': entry.value,
                  'amount_sold': 0,
                },
              )
              as Map<String, dynamic>;
      stockIds[entry.key] = (row['id'] as num).toInt();
    }
    _stockIdsByEventId[eventId] = stockIds;

    return eventId;
  }

  /// The venue's street address, which the server requires on an event.
  ///
  /// The client models the address on the venue rather than the bazaar, so it
  /// is read back from the venue rather than asked for twice. Falls back to an
  /// empty string, since a missing address should not stop a bazaar being
  /// created.
  Future<String> _addressForEstablishment(
    AuthRepository auth,
    int establishmentId,
  ) async {
    try {
      final payload = await auth.api.get('/api/core/establishment/') as List;
      for (final entry in payload) {
        final map = entry as Map<String, dynamic>;
        if ((map['id'] as num?)?.toInt() == establishmentId) {
          return map['address'] as String? ?? '';
        }
      }
    } on ApiException {
      // Not worth failing the whole creation over.
    }
    return '';
  }

  Future<List<BazaarEvent>> listVisibleForUser(AppUser user) async {
    await _ensureLoaded();
    _refreshStatuses();
    if (user.isAdminOrOwner) {
      return _sortedForDisplay(_events);
    }
    final assignedEventIds = user.assignedEventIdsEffective.toSet();
    return _sortedForDisplay(
      _events.where((e) => assignedEventIds.contains(e.id)).toList(),
    );
  }

  /// Closes a bazaar and returns its unsold stock to the master inventory.
  ///
  /// The server does all three steps -- release the stock, clear the
  /// allocations, mark the bazaar finished -- inside one transaction, which is
  /// why this calls the endpoint rather than doing them one at a time from
  /// here. Done separately, a failure between two of them would count the same
  /// stock twice.
  Future<void> finalizeEvent(int eventId) async {
    await _ensureLoaded();
    final auth = _auth;
    if (auth != null && auth.vendorId != null) {
      await auth.api.post('/api/bazaar/event/$eventId/finalize/', body: {});
      // The bazaar's stock went back to the warehouse, so nothing here is
      // sellable any more and the catalogue's figures have moved.
      _allocationsByEventId[eventId] = {};
      _stockIdsByEventId[eventId] = {};
      await _products?.refresh();
    }
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
    await _ensureLoaded();
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
    final previous = _events[idx];

    // Written to the server before the local copy, so a rejected edit leaves
    // the bazaar as it was rather than showing a change that only exists here.
    // Editing the dates and finding them reverted on the next launch was how
    // this gap showed itself.
    await _updateEventOnServer(
      eventId: eventId,
      name: name,
      startDate: startDate,
      endDate: endDate,
      allocationsByAllocationKey: allocationsByAllocationKey,
    );

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

  Future<void> _updateEventOnServer({
    required int eventId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    Map<String, int>? allocationsByAllocationKey,
  }) async {
    final auth = _auth;
    final products = _products;
    if (auth == null || products == null || auth.vendorId == null) {
      return;
    }

    // Only the fields that changed. A full replace would have to resend the
    // venue, the vendor and the address, none of which this screen edits.
    await auth.api.patch(
      '/api/bazaar/event/$eventId/',
      body: {
        'name': name,
        'start_date': startDate.toUtc().toIso8601String(),
        'end_date': endDate.toUtc().toIso8601String(),
      },
    );

    if (allocationsByAllocationKey == null) {
      return;
    }

    final existing = Map<String, int>.from(_stockIdsByEventId[eventId] ?? {});
    for (final entry in allocationsByAllocationKey.entries) {
      final stockId = existing.remove(entry.key);
      if (stockId != null) {
        await auth.api.patch(
          '/api/bazaar/event/$eventId/stock/$stockId/',
          body: {'amount_allocated': entry.value},
        );
        continue;
      }
      final variantId = products.variantIdFor(entry.key);
      if (variantId == null || entry.value <= 0) {
        continue;
      }
      final row =
          await auth.api.post(
                '/api/bazaar/event/$eventId/stock/',
                body: {
                  'event': eventId,
                  'variant': variantId,
                  'amount_allocated': entry.value,
                  'amount_sold': 0,
                },
              )
              as Map<String, dynamic>;
      _stockIdsByEventId.putIfAbsent(eventId, () => {})[entry.key] =
          (row['id'] as num).toInt();
    }

    // Whatever is left was allocated before and is not any more.
    for (final stockId in existing.values) {
      try {
        await auth.api.delete('/api/bazaar/event/$eventId/stock/$stockId/');
      } on ApiException {
        // The row has sales against it, and the server protects those. Nothing
        // more can be sold from it instead, which is what removing it meant.
        await auth.api.patch(
          '/api/bazaar/event/$eventId/stock/$stockId/',
          body: {'amount_allocated': 0},
        );
      }
    }
    for (final key in existing.keys) {
      _stockIdsByEventId[eventId]?.remove(key);
    }
  }

  /// Turns an approved proposal into a real bazaar.
  ///
  /// The event already exists on the server, created unapproved so the
  /// approval request had something to belong to. This is where it becomes
  /// something staff can sell against: the flag flips and the stock rows are
  /// written, which is also the moment the inventory is actually committed.
  ///
  /// Returns the bazaar, now present in every listing.
  Future<BazaarEvent> approveProposal({
    required int eventId,
    required String name,
    required int companyId,
    required DateTime startDate,
    required DateTime endDate,
    List<String> acceptedPaymentMethods = const ['CASH'],
    List<BazaarPaymentMethod> customOtherMethods = const [],
    Map<String, int> allocationsByAllocationKey = const {},
  }) async {
    await _ensureLoaded();
    final auth = _auth;
    final products = _products;

    if (auth != null && auth.vendorId != null && products != null) {
      // Stock first. If a combination is short, this throws before the bazaar
      // is marked approved -- leaving a proposal that can be decided again,
      // rather than a live bazaar promising stock that is not there.
      final stockIds = <String, int>{};
      for (final entry in allocationsByAllocationKey.entries) {
        if (entry.value <= 0) {
          continue;
        }
        final variantId = products.variantIdFor(entry.key);
        if (variantId == null) {
          continue;
        }
        final row =
            await auth.api.post(
                  '/api/bazaar/event/$eventId/stock/',
                  body: {
                    'event': eventId,
                    'variant': variantId,
                    'amount_allocated': entry.value,
                    'amount_sold': 0,
                  },
                )
                as Map<String, dynamic>;
        stockIds[entry.key] = (row['id'] as num).toInt();
      }
      _stockIdsByEventId[eventId] = stockIds;

      await auth.api.patch(
        '/api/bazaar/event/$eventId/',
        body: {'is_approved': true},
      );
    }

    final event = BazaarEvent(
      id: eventId,
      name: name,
      companyId: companyId,
      startDate: startDate,
      endDate: endDate,
      status: _statusFor(startDate, endDate),
      acceptedPaymentMethods: acceptedPaymentMethods,
      customOtherMethods: customOtherMethods,
    );
    _events.removeWhere((e) => e.id == eventId);
    _events.add(event);
    _allocationsByEventId[eventId] = Map<String, int>.from(
      allocationsByAllocationKey,
    );
    _proposalEventIds.remove(eventId);
    return event;
  }

  Future<void> deleteEvent(int eventId) async {
    await _ensureLoaded();
    final auth = _auth;
    if (auth != null && auth.vendorId != null) {
      // Its stock rows go first. The server protects a bazaar that still has
      // any, and returns a 500 rather than a refusal when one is attempted --
      // so without this, deleting a bazaar fails with nothing to explain why.
      //
      // A row that has sales against it is protected in turn, and that failure
      // is allowed through: a bazaar with takings recorded against it should
      // not be deletable, and the error is how the screen says so.
      for (final stockId in (_stockIdsByEventId[eventId] ?? {}).values) {
        await auth.api.delete('/api/bazaar/event/$eventId/stock/$stockId/');
      }
      // Deleted on the server before here. Removing it locally alone would
      // make it reappear on the next launch, which is more confusing than a
      // delete that visibly failed.
      await auth.api.delete('/api/bazaar/event/$eventId/');
    }
    _events.removeWhere((e) => e.id == eventId);
    _allocationsByEventId.remove(eventId);
    _stockIdsByEventId.remove(eventId);
  }
}

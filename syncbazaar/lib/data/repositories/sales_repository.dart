import '../../models/sale.dart';
import '../../services/local_store.dart';
import '../remote/api_client.dart';
import '../remote/sale_api_mapper.dart';
import 'auth_repository.dart';
import 'event_repository.dart';

class SalesRepository {
  /// Reads recorded sales back from the server when [auth] is supplied.
  ///
  /// [events] comes with it: a sale names the `EventStock` row it came out of,
  /// and only the loaded bazaars know which combination that is.
  ///
  /// Without them this stays the in-memory list it always was, which is what
  /// the mock-seeded build and the tests use.
  SalesRepository({
    AuthRepository? auth,
    EventRepository? events,
    LocalStore store = const LocalStore(),
  }) : _auth = auth,
       _events = events,
       _store = store;

  final AuthRepository? _auth;
  final EventRepository? _events;
  final LocalStore _store;

  /// Where the queue of sales the server has not confirmed is kept.
  static const String _queueKey = 'sales.pendingUpload';

  /// Whether the stored queue has been read back yet this run.
  bool _queueRestored = false;

  int? _loadedVendorId;
  Future<void>? _load;
  Map<int, String> _paymentMethodNames = {};

  final List<Sale> _sales = [];

  Future<void> addSale(Sale sale) async {
    await _restoreQueue();
    _sales.add(sale);
    // Awaited, not fired and forgotten. The caller tells the cashier the sale
    // is done as soon as this returns, and a sale that is only in memory at
    // that moment is one a crash can take with the money already in the till.
    await _persistQueue();
  }

  Future<List<Sale>> listUnsyncedSales() async {
    // Deliberately not loading first. This is what the uploader reads, and a
    // sale waiting to be sent is already in hand — going to the network to
    // find out what to send to the network would deadlock the offline case.
    //
    // The stored queue is restored though, and must be: after a relaunch this
    // is how yesterday's unsent sales are found at all.
    await _restoreQueue();
    return _sales.where((s) => !s.synced).toList();
  }

  Future<List<Sale>> listSales() async {
    await _ensureLoaded();
    return _sales;
  }

  /// Re-reads the sales history, discarding what is held now.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    final auth = _auth;
    final events = _events;
    final vendorId = auth?.vendorId;
    if (auth == null ||
        events == null ||
        vendorId == null ||
        _loadedVendorId == vendorId) {
      return;
    }

    final existing = _load;
    if (existing != null) {
      await existing;
      return;
    }
    final load = _loadFromApi(auth, events).then((_) {
      _loadedVendorId = vendorId;
    });
    _load = load.whenComplete(() => _load = null);
    await _load;
  }

  Future<void> _loadFromApi(AuthRepository auth, EventRepository events) async {
    _paymentMethodNames = await _loadPaymentMethodNames(auth);

    final fetched = <Sale>[];
    for (final event in await events.loadedEvents()) {
      // Two requests per bazaar: the server keeps the amount and the payment
      // apart. Worth knowing as the history grows -- a vendor with a season of
      // bazaars behind them pays for all of it on every load, and this is
      // where a date filter or a single vendor-wide endpoint would go.
      final sales =
          await auth.api.get('/api/bazaar/event/${event.id}/sale/') as List;
      if (sales.isEmpty) {
        continue;
      }
      final payments =
          await auth.api.get('/api/bazaar/event/${event.id}/payment/') as List;

      fetched.addAll(
        mapSalesResponse(
          sales,
          eventId: event.id,
          paymentsPayload: payments,
          allocationKeyForStockId: (stockId) => events.allocationKeyForStockId(
            eventId: event.id,
            stockId: stockId,
          ),
          paymentMethodNameById: (id) => _paymentMethodNames[id] ?? 'CASH',
        ),
      );
    }

    // Restored first, so a sale queued before the last relaunch is counted as
    // pending below rather than being wiped by the clear.
    await _restoreQueue();

    // Anything not yet uploaded is kept and the rest replaced, rather than
    // appending: a sale rung up on this device is also coming back from the
    // server, and adding both would double it in every total on the dashboard.
    final pending = _sales.where((sale) => !sale.synced).toList();
    _sales
      ..clear()
      ..addAll(fetched)
      ..addAll(pending);
    await _persistQueue();
  }

  Future<Map<int, String>> _loadPaymentMethodNames(AuthRepository auth) async {
    try {
      final payload = await auth.api.get('/api/core/mode-of-payment/') as List;
      return {
        for (final entry in payload.cast<Map<String, dynamic>>())
          if ((entry['id'] as num?) != null)
            (entry['id'] as num).toInt(): (entry['name'] as String? ?? 'CASH')
                .toUpperCase(),
      };
    } on ApiException {
      // A sale with an unknown method name still belongs in the history.
      return const {};
    }
  }

  /// Flags sales the server has confirmed it holds.
  ///
  /// Keyed on [Sale.clientUuid] rather than the local id, because that is the
  /// only identifier both sides agree on — the server assigns its own id and
  /// the local one is a timestamp that means nothing to it.
  Future<void> markSynced(Set<String> clientUuids) async {
    if (clientUuids.isEmpty) {
      return;
    }
    await _restoreQueue();
    for (var i = 0; i < _sales.length; i++) {
      if (clientUuids.contains(_sales[i].clientUuid)) {
        _sales[i] = _sales[i].copyWith(synced: true);
      }
    }
    await _persistQueue();
  }

  /// Reads back sales that were queued before the app last closed.
  ///
  /// Once per run. The queue is the only copy of a sale rung up without signal,
  /// so this happens before anything reads or writes it, rather than waiting
  /// for a network load that may never succeed.
  Future<void> _restoreQueue() async {
    if (_queueRestored) {
      return;
    }
    _queueRestored = true;

    final List<Map<String, dynamic>> stored;
    try {
      stored = await _store.readList(_queueKey);
    } catch (_) {
      // Storage unavailable. Carrying on in memory is what this always did, so
      // this is never worse than before; it just is not durable this run.
      return;
    }
    final known = _sales.map((sale) => sale.clientUuid).toSet();
    for (final row in stored) {
      try {
        final sale = Sale.fromJson(row);
        // A sale already in hand wins: it is the live object, and the stored
        // copy is only a record of it.
        if (known.add(sale.clientUuid)) {
          _sales.add(sale);
        }
      } catch (_) {
        // One unreadable row is dropped rather than taking the rest with it.
        // Losing a sale is bad; losing the whole queue to a bad byte is worse.
        continue;
      }
    }
  }

  /// Writes the unsent queue, and only it.
  ///
  /// Sales the server has confirmed are not stored: it holds them now, and a
  /// refresh brings them back. Keeping them here would grow the file for every
  /// sale ever made and duplicate what a load already returns.
  Future<void> _persistQueue() async {
    final pending = _sales.where((sale) => !sale.synced).toList();
    try {
      await _store.writeList(
        _queueKey,
        [for (final sale in pending) sale.toJson()],
      );
    } catch (_) {
      // A sale is never refused because the device could not write it down.
      // The customer has already paid and the money is in the till; recording
      // it in memory and losing durability beats rejecting it outright.
    }
  }
}

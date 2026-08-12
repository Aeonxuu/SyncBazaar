import '../../models/sale.dart';
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
  SalesRepository({AuthRepository? auth, EventRepository? events})
    : _auth = auth,
      _events = events;

  final AuthRepository? _auth;
  final EventRepository? _events;

  int? _loadedVendorId;
  Future<void>? _load;
  Map<int, String> _paymentMethodNames = {};

  final List<Sale> _sales = [];

  Future<void> addSale(Sale sale) async {
    _sales.add(sale);
  }

  Future<List<Sale>> listUnsyncedSales() async {
    // Deliberately not loading first. This is what the uploader reads, and a
    // sale waiting to be sent is already in hand — going to the network to
    // find out what to send to the network would deadlock the offline case.
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
      final sales = await auth.api.get(
        '/api/bazaar/event/${event.id}/sale/',
      ) as List;
      if (sales.isEmpty) {
        continue;
      }
      final payments = await auth.api.get(
        '/api/bazaar/event/${event.id}/payment/',
      ) as List;

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

    // Anything not yet uploaded is kept and the rest replaced, rather than
    // appending: a sale rung up on this device is also coming back from the
    // server, and adding both would double it in every total on the dashboard.
    final pending = _sales.where((sale) => !sale.synced).toList();
    _sales
      ..clear()
      ..addAll(fetched)
      ..addAll(pending);
  }

  Future<Map<int, String>> _loadPaymentMethodNames(AuthRepository auth) async {
    try {
      final payload = await auth.api.get('/api/core/mode-of-payment/') as List;
      return {
        for (final entry in payload.cast<Map<String, dynamic>>())
          if ((entry['id'] as num?) != null)
            (entry['id'] as num).toInt():
                (entry['name'] as String? ?? 'CASH').toUpperCase(),
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
    for (var i = 0; i < _sales.length; i++) {
      if (clientUuids.contains(_sales[i].clientUuid)) {
        _sales[i] = _sales[i].copyWith(synced: true);
      }
    }
  }
}

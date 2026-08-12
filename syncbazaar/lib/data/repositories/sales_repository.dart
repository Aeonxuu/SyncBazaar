import '../../models/sale.dart';

class SalesRepository {
  final List<Sale> _sales = [];

  Future<void> addSale(Sale sale) async {
    _sales.add(sale);
  }

  Future<List<Sale>> listUnsyncedSales() async {
    return _sales.where((s) => !s.synced).toList();
  }

  Future<List<Sale>> listSales() async => _sales;

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

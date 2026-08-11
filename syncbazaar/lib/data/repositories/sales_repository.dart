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
}

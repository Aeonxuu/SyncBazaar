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

  Future<List<Sale>> listSalesByEvent(int eventId) async {
    return _sales.where((s) => s.eventId == eventId).toList();
  }

  Future<double> totalForToday() async {
    final now = DateTime.now();
    return _sales
        .where(
          (s) =>
              s.timestamp.year == now.year &&
              s.timestamp.month == now.month &&
              s.timestamp.day == now.day,
        )
        .fold<double>(0, (sum, sale) => sum + sale.total);
  }
}

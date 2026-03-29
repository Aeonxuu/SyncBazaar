import '../../models/company.dart';

class PaymentMethodMeta {
  const PaymentMethodMeta({
    required this.name,
    this.requiresEmployeeId = false,
  });

  final String name;
  final bool requiresEmployeeId;
}

class SettingsRepository {
  final List<Company> _companies = [
    const Company(
      id: 1,
      name: 'Amkor Technology',
      address: 'Makati City',
      contact: '0917-000-0000',
      incentivePercent: 10,
      bufferPercent: 10,
    ),
    const Company(
      id: 2,
      name: 'Shin-Etsu',
      address: 'Laguna',
      contact: '0917-111-1111',
      incentivePercent: 10,
      bufferPercent: 10,
    ),
  ];

  bool _autoSyncOnReconnect = true;
  final List<PaymentMethodMeta> _paymentMethods = [
    const PaymentMethodMeta(name: 'CASH'),
    const PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
    const PaymentMethodMeta(name: 'OTHER'),
  ];

  Future<List<Company>> listCompanies() async => _companies;

  Future<void> upsertCompany(Company company) async {
    final idx = _companies.indexWhere((c) => c.id == company.id);
    if (idx == -1) {
      _companies.add(company);
      return;
    }
    _companies[idx] = company;
  }

  Future<List<PaymentMethodMeta>> paymentMethods() async =>
      List<PaymentMethodMeta>.from(_paymentMethods);

  Future<void> upsertPaymentMethod(PaymentMethodMeta method) async {
    final idx = _paymentMethods.indexWhere(
      (item) => item.name.trim().toUpperCase() == method.name.trim().toUpperCase(),
    );
    if (idx == -1) {
      _paymentMethods.add(method);
      return;
    }
    _paymentMethods[idx] = method;
  }

  Future<bool> autoSyncEnabled() async => _autoSyncOnReconnect;

  Future<void> setAutoSync(bool enabled) async {
    _autoSyncOnReconnect = enabled;
  }
}

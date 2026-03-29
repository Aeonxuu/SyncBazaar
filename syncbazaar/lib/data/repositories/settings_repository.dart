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
  int _nextCompanyId = 3;

  final Map<int, List<PaymentMethodMeta>> _locationPaymentMethodsByCompanyId = {
    1: const [
      PaymentMethodMeta(name: 'CASH'),
      PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
      PaymentMethodMeta(name: 'GCASH'),
    ],
    2: const [
      PaymentMethodMeta(name: 'CASH'),
      PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
    ],
  };

  final List<PaymentMethodMeta> _paymentMethods = [
    const PaymentMethodMeta(name: 'CASH'),
    const PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
  ];

  Future<List<Company>> listCompanies() async => _companies;

  Future<void> upsertCompany(Company company) async {
    final idx = _companies.indexWhere((c) => c.id == company.id);
    if (idx == -1) {
      _companies.add(company);
      _locationPaymentMethodsByCompanyId.putIfAbsent(
        company.id,
        () => const [
          PaymentMethodMeta(name: 'CASH'),
          PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
        ],
      );
      return;
    }
    _companies[idx] = company;
  }

  Future<Company> createCompany({
    required String name,
    String address = '',
    String contact = '',
    double incentivePercent = 0,
    double bufferPercent = 0,
    String? qrImagePath,
  }) async {
    final created = Company(
      id: _nextCompanyId++,
      name: name.trim(),
      address: address.trim(),
      contact: contact.trim(),
      incentivePercent: incentivePercent,
      bufferPercent: bufferPercent,
      qrImagePath: qrImagePath,
    );
    _companies.add(created);
    _locationPaymentMethodsByCompanyId[created.id] = const [
      PaymentMethodMeta(name: 'CASH'),
      PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
    ];
    return created;
  }

  Future<Map<int, List<PaymentMethodMeta>>> paymentMethodsByCompanyId() async {
    return {
      for (final entry in _locationPaymentMethodsByCompanyId.entries)
        entry.key: List<PaymentMethodMeta>.from(entry.value),
    };
  }

  Future<List<PaymentMethodMeta>> paymentMethodsForCompany(int companyId) async {
    return List<PaymentMethodMeta>.from(
      _locationPaymentMethodsByCompanyId[companyId] ??
          const [
            PaymentMethodMeta(name: 'CASH'),
            PaymentMethodMeta(name: 'COOP', requiresEmployeeId: true),
          ],
    );
  }

  Future<void> upsertCompanyConfiguration({
    required Company company,
    required List<PaymentMethodMeta> paymentMethods,
  }) async {
    await upsertCompany(company);
    _locationPaymentMethodsByCompanyId[company.id] = _normalizePaymentMethods(
      paymentMethods,
    );
  }

  Future<List<PaymentMethodMeta>> paymentMethods() async {
    final methods = <PaymentMethodMeta>[..._paymentMethods];
    for (final locationMethods in _locationPaymentMethodsByCompanyId.values) {
      for (final method in locationMethods) {
        final idx = methods.indexWhere(
          (item) =>
              item.name.trim().toUpperCase() ==
              method.name.trim().toUpperCase(),
        );
        if (idx == -1) {
          methods.add(method);
        } else if (method.requiresEmployeeId && !methods[idx].requiresEmployeeId) {
          methods[idx] = method;
        }
      }
    }
    return methods;
  }

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

  List<PaymentMethodMeta> _normalizePaymentMethods(
    List<PaymentMethodMeta> input,
  ) {
    final normalized = <PaymentMethodMeta>[];
    for (final item in input) {
      final name = item.name.trim();
      if (name.isEmpty) {
        continue;
      }
      final existing = normalized.indexWhere(
        (method) => method.name.toUpperCase() == name.toUpperCase(),
      );
      final next = PaymentMethodMeta(
        name: name,
        requiresEmployeeId: item.requiresEmployeeId,
      );
      if (existing == -1) {
        normalized.add(next);
      } else {
        normalized[existing] = next;
      }
    }
    return normalized;
  }
}

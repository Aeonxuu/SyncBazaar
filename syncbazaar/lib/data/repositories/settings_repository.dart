import 'package:shared_preferences/shared_preferences.dart';

import '../../models/company.dart';

class PaymentMethodMeta {
  const PaymentMethodMeta({required this.name, this.extraFieldLabel});

  final String name;
  final String? extraFieldLabel;
}

class SettingsRepository {
  static const String _storeNameKey = 'settings.storeName';

  /// Printed until the seller sets their own name, so a receipt is never
  /// headed by an empty line.
  static const String _defaultStoreName = 'SyncBazaar';

  final List<Company> _companies = [];

  bool _autoSyncOnReconnect = true;
  int _nextCompanyId = 1;

  final Map<int, List<PaymentMethodMeta>> _locationPaymentMethodsByCompanyId =
      {};

  final List<PaymentMethodMeta> _paymentMethods = [
    const PaymentMethodMeta(name: 'CASH'),
  ];

  Future<List<Company>> listCompanies() async => _companies;

  Future<void> upsertCompany(Company company) async {
    final idx = _companies.indexWhere((c) => c.id == company.id);
    if (idx == -1) {
      _companies.add(company);
      _locationPaymentMethodsByCompanyId.putIfAbsent(
        company.id,
        () => const [PaymentMethodMeta(name: 'CASH')],
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
    ];
    return created;
  }

  Future<Map<int, List<PaymentMethodMeta>>> paymentMethodsByCompanyId() async {
    return {
      for (final entry in _locationPaymentMethodsByCompanyId.entries)
        entry.key: List<PaymentMethodMeta>.from(entry.value),
    };
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
        } else {
          final existing = methods[idx];
          final shouldUpgrade =
              (existing.extraFieldLabel == null ||
                  existing.extraFieldLabel!.trim().isEmpty) &&
              method.extraFieldLabel != null &&
              method.extraFieldLabel!.trim().isNotEmpty;
          if (shouldUpgrade) {
            methods[idx] = method;
          }
        }
      }
    }
    return methods;
  }

  Future<bool> autoSyncEnabled() async => _autoSyncOnReconnect;

  Future<void> setAutoSync(bool enabled) async {
    _autoSyncOnReconnect = enabled;
  }

  /// The seller's own name — the pop-up store, e.g. "SV KICKz".
  ///
  /// Distinct from [Company], which models the venue hosting the bazaar. The
  /// receipt header prints both, because a customer needs to know who sold
  /// them the shoes, not only which mall they were standing in.
  ///
  /// Unlike its in-memory siblings this one is persisted: it is typed once and
  /// then printed on every receipt, so losing it on restart would silently
  /// start producing unbranded receipts. Follows [AuthRepository]'s use of
  /// `shared_preferences`.
  Future<String> storeName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storeNameKey)?.trim();
    return (stored == null || stored.isEmpty) ? _defaultStoreName : stored;
  }

  Future<void> setStoreName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_storeNameKey);
      return;
    }
    await prefs.setString(_storeNameKey, trimmed);
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
        extraFieldLabel: _sanitizeExtraFieldLabel(item.extraFieldLabel),
      );
      if (existing == -1) {
        normalized.add(next);
      } else {
        normalized[existing] = next;
      }
    }
    return normalized;
  }

  String? _sanitizeExtraFieldLabel(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 28) {
      return trimmed;
    }
    return trimmed.substring(0, 28);
  }
}

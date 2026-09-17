import 'package:shared_preferences/shared_preferences.dart';

import '../../models/company.dart';
import '../remote/establishment_api_mapper.dart';
import 'auth_repository.dart';

class PaymentMethodMeta {
  const PaymentMethodMeta({
    required this.name,
    this.extraFieldLabel,
    this.qrImageUrl,
  });

  final String name;
  final String? extraFieldLabel;

  /// A URL, not bytes. The QR lives on the server as the only copy there is
  /// -- see `VendorPaymentMethodRepository` -- so there is nothing local to
  /// fall back on. Its presence is what tells the POS to present a QR at
  /// checkout, so uploading one for a method needs no code here.
  final String? qrImageUrl;

  PaymentMethodMeta copyWith({
    String? name,
    String? extraFieldLabel,
    String? qrImageUrl,
    bool clearQr = false,
  }) {
    return PaymentMethodMeta(
      name: name ?? this.name,
      extraFieldLabel: extraFieldLabel ?? this.extraFieldLabel,
      qrImageUrl: clearQr ? null : (qrImageUrl ?? this.qrImageUrl),
    );
  }
}

class SettingsRepository {
  /// Venues come from the API when [auth] is supplied.
  ///
  /// Everything else here — the store name, auto-sync — stays local, because
  /// they are settings for this device rather than facts about the business.
  SettingsRepository({AuthRepository? auth}) : _auth = auth;

  final AuthRepository? _auth;

  int? _loadedVendorId;
  Future<void>? _load;

  /// Every catalog id, so a venue write still has something to send.
  ///
  /// `Establishment.accepted_payment_methods` is a required field on the
  /// server, left over from when a venue chose its own methods. Nothing
  /// reads it any more -- a vendor's methods live in `VendorPaymentMethod`
  /// now, one list shared by every venue -- but the write still has to carry
  /// something to satisfy it, so every id in the catalog is what goes.
  List<int> _allMethodIds = const [];

  static const String _storeNameKey = 'settings.storeName';

  /// Printed until the seller sets their own name, so a receipt is never
  /// headed by an empty line.
  static const String _defaultStoreName = 'SyncBazaar';

  final List<Company> _companies = [];

  bool _autoSyncOnReconnect = true;
  int _nextCompanyId = 1;

  /// Fetches the venue list once signed in.
  ///
  /// Returns immediately without a session, so the mock-seeded and test paths
  /// keep their in-memory behaviour.
  Future<void> _ensureLoaded() async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null || _loadedVendorId == vendorId) {
      return;
    }

    final existing = _load;
    if (existing != null) {
      await existing;
      return;
    }
    final load = _loadFromApi(
      auth,
      vendorId,
    ).then((_) => _loadedVendorId = vendorId);
    _load = load.whenComplete(() => _load = null);
    await _load;
  }

  Future<void> _loadFromApi(AuthRepository auth, int vendorId) async {
    // Still fetched, and still handed to the mapper below -- not because
    // this repository cares what a payment method is called any more, but
    // because `mapEstablishmentsResponse` asks for it to resolve a field nobody
    // reads. Kept as ids only; the names and labels are wasted here.
    final methodsById = mapPaymentMethodsById(
      await auth.api.get('/api/core/mode-of-payment/') as List,
    );
    _allMethodIds = methodsById.keys.toList();
    final bundle = mapEstablishmentsResponse(
      await auth.api.get(establishmentsPath(vendorId)) as List,
      methodsById: methodsById,
    );

    _companies
      ..clear()
      ..addAll(bundle.companies);

    // Ids come from the server now, so a locally created venue must not be
    // handed one the server might also issue.
    for (final company in _companies) {
      if (company.id >= _nextCompanyId) {
        _nextCompanyId = company.id + 1;
      }
    }
  }

  /// Re-fetches the venue list, discarding what is held now.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoaded();
  }

  Future<List<Company>> listCompanies() async {
    await _ensureLoaded();
    return _companies;
  }

  Future<void> upsertCompany(Company company) async {
    await _ensureLoaded();
    await _saveCompanyToServer(company);

    final idx = _companies.indexWhere((c) => c.id == company.id);
    if (idx == -1) {
      _companies.add(company);
      return;
    }
    _companies[idx] = company;
  }

  /// Writes an existing venue back.
  ///
  /// Failure is not swallowed: a venue is printed on every receipt from the
  /// bazaars held there, and one that looks saved but is not would go
  /// unnoticed until a receipt came out with the old address on it.
  Future<void> _saveCompanyToServer(Company company) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      return;
    }
    // Only for venues the server knows. A locally created one is created
    // through `createCompany`, which is where its id comes from.
    if (!_companies.any((c) => c.id == company.id)) {
      return;
    }
    await auth.api.put(
      establishmentPath(vendorId, company.id),
      body: establishmentBody(
        company: company,
        // Vestigial -- see `_allMethodIds`.
        acceptedPaymentMethodIds: _allMethodIds,
      ),
    );
  }

  Future<Company> createCompany({
    required String name,
    String address = '',
    String contact = '',
    double incentivePercent = 0,
    double bufferPercent = 0,
  }) async {
    await _ensureLoaded();

    var created = Company(
      id: _nextCompanyId++,
      name: name.trim(),
      address: address.trim(),
      contact: contact.trim(),
      incentivePercent: incentivePercent,
      bufferPercent: bufferPercent,
    );

    // Created on the server first so the venue carries the id the server
    // assigned. A locally numbered venue would be referenced by any bazaar
    // held there, and that bazaar's id belongs to the server — so the two
    // would point at different places the moment the app restarted.
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth != null && vendorId != null) {
      final row =
          await auth.api.post(
                establishmentsPath(vendorId),
                body: establishmentBody(
                  company: created,
                  // Vestigial -- see `_allMethodIds`.
                  acceptedPaymentMethodIds: _allMethodIds,
                ),
              )
              as Map<String, dynamic>;
      created = created.copyWith(id: (row['id'] as num).toInt());
    }

    _companies.add(created);
    return created;
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
  /// The signed-in vendor's name, falling back to the device setting.
  ///
  /// Signed in, the server is the only source. The name is a fact about the
  /// business, not a preference of this tablet: it heads every receipt and is
  /// printed six times on the statement of account, which the *server*
  /// renders. Reading a local copy here let the two drift, so the screen said
  /// one name while the document said another — and a second vendor signing
  /// into this app would have printed the first vendor's name on their
  /// receipts.
  ///
  /// The local value survives only for the no-session build, where there is no
  /// vendor to ask.
  Future<String> storeName() async {
    final vendor = _auth?.vendorName?.trim();
    if (vendor != null && vendor.isNotEmpty) {
      return vendor;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storeNameKey)?.trim();
    return (stored == null || stored.isEmpty) ? _defaultStoreName : stored;
  }

  /// Whether a rename would reach the server rather than staying on this
  /// device. Lets the UI say which of the two it is doing.
  bool get storeNameIsVendor => _auth?.vendorId != null;

  /// Renames the vendor where there is a session, and the device otherwise.
  ///
  /// Throws [ApiException] when the server refuses or cannot be reached, so a
  /// name that was not saved is never shown as though it were.
  Future<void> setStoreName(String name) async {
    final auth = _auth;
    if (auth != null && auth.vendorId != null) {
      await auth.renameVendor(name);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_storeNameKey);
      return;
    }
    await prefs.setString(_storeNameKey, trimmed);
  }
}
